import Foundation

/// Settings that control what is added to the converted MIDI file besides the recorded song data.
public struct SVQConversionOptions: Equatable, Codable, Sendable {
    /// Add Bank Select (CC 0/32) and Program Change at the start of each used channel so the
    /// right XP-80 patch is chosen for every Part.
    public var addPatchSelection = true
    /// Add each Part's level (CC 7), pan (CC 10), reverb send (CC 91) and chorus send (CC 93).
    public var addMixerSettings = true
    /// Add the instrument's setup as System Exclusive: for XP files, the Performance (temporary
    /// Performance Common + 16 Parts); for Fantom-X files, every Part's saved Patch or Rhythm Set
    /// plus Patch mode's keyboard and pad sounds. It goes on its own setup track starting with the
    /// song, so the song's timing is unchanged: the listener solos that track once to set up the
    /// instrument, then mutes it. Fantom-X Parts whose sound is sent this way get no Program
    /// Change, which would replace that sound on later plays.
    public var addPerformanceSysEx = false
    /// Empty measures inserted before the song (the song's timing is otherwise kept as saved).
    public var leadInMeasures = 0
    /// Roland device ID for the SysEx messages (0x10 = device 17, the XP-80 default).
    public var sysExDeviceID: UInt8 = 0x10
    /// Which XP-80 slot (0-3 = A-D) each SR-JV80 expansion board number was installed in.
    /// Boards without an entry are assigned slots in ascending board-number order.
    public var expansionSlots: [Int: Int] = [:]
    /// Include the data of tracks whose Output is set to OFF (the instrument didn't play them).
    public var includeOffTracks = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case addPatchSelection, addMixerSettings, addPerformanceSysEx, leadInMeasures, sysExDeviceID,
             expansionSlots, includeOffTracks
    }

    /// Decodes saved options, using the default for any setting that wasn't saved (so settings
    /// stored by an earlier version keep working when options are added).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SVQConversionOptions()
        addPatchSelection = try c.decodeIfPresent(Bool.self, forKey: .addPatchSelection) ?? d.addPatchSelection
        addMixerSettings = try c.decodeIfPresent(Bool.self, forKey: .addMixerSettings) ?? d.addMixerSettings
        addPerformanceSysEx = try c.decodeIfPresent(Bool.self, forKey: .addPerformanceSysEx) ?? d.addPerformanceSysEx
        leadInMeasures = try c.decodeIfPresent(Int.self, forKey: .leadInMeasures) ?? d.leadInMeasures
        sysExDeviceID = try c.decodeIfPresent(UInt8.self, forKey: .sysExDeviceID) ?? d.sysExDeviceID
        expansionSlots = try c.decodeIfPresent([Int: Int].self, forKey: .expansionSlots) ?? d.expansionSlots
        includeOffTracks = try c.decodeIfPresent(Bool.self, forKey: .includeOffTracks) ?? d.includeOffTracks
    }

    /// The slot used for a board, honoring explicit assignments first.
    public func slot(forBoard board: Int, boardsInUse: [Int]) -> Int {
        if let slot = expansionSlots[board] { return min(max(slot, 0), 3) }
        let index = boardsInUse.sorted().firstIndex(of: board) ?? 0
        return min(index, 3)
    }
}

public enum SVQConverter {
    /// Minimum spacing between SysEx messages so the receiving instrument can keep up.
    static let sysExIntervalMicroseconds = 40_000

    /// Converts the song to a Standard MIDI File (format 1).
    public static func midiData(for svq: SVQFile, title: String? = nil,
                                options: SVQConversionOptions = SVQConversionOptions()) -> Data {
        let name = title ?? svq.songName
        let events = options.includeOffTracks ? svq.events
            : svq.events.filter { $0.isConductorEvent || svq.output(ofTrack: $0.track) != .off }
        return build(svq: svq, title: name, events: events, length: svq.songLength,
                     trackFor: { $0.track }, trackName: { phraseTrackName(svq: svq, track: $0, channels: $1) },
                     copyright: svq.comment, options: options)
    }

    /// Converts one phrase track (0-15) to its own Standard MIDI File: the song's tempo and beat
    /// tracks, then the track with its channel setup. The setup SysEx belongs to the whole song, so
    /// it isn't included (see `setupMIDIData`).
    public static func midiData(for svq: SVQFile, track: Int, title: String? = nil,
                                options: SVQConversionOptions = SVQConversionOptions()) -> Data {
        var options = options
        options.addPerformanceSysEx = false
        let name = title ?? "\(svq.songName) - Track \(track + 1)"
        return build(svq: svq, title: name, events: svq.events.filter { $0.isConductorEvent || $0.track == track },
                     length: svq.songLength, trackFor: { $0.track },
                     trackName: { phraseTrackName(svq: svq, track: $0, channels: $1) },
                     copyright: svq.comment, options: options)
    }

    /// The instruments' two conductor tracks.
    public enum ConductorTrack: Sendable {
        /// Tempo changes.
        case tempo
        /// Meter (time signature) and key changes.
        case beat
    }

    /// Converts the song's Tempo track or Beat track to a Standard MIDI File holding only those events.
    public static func midiData(for svq: SVQFile, conductorTrack: ConductorTrack, title: String? = nil,
                                options: SVQConversionOptions = SVQConversionOptions()) -> Data {
        var options = options
        options.addPerformanceSysEx = false
        let name = title ?? "\(svq.songName) - \(conductorTrack == .tempo ? "Tempo" : "Beat") Track"
        return build(svq: svq, title: name, events: conductorTrack == .tempo ? svq.tempoEvents : svq.beatEvents,
                     length: svq.songLength, trackFor: { $0.track }, trackName: { _, _ in "" },
                     copyright: svq.comment, options: options)
    }

    /// The song's setup alone, as a Standard MIDI File: the setup SysEx track (the XP Performance, or
    /// the Fantom-X Parts' saved sounds), then one track per channel the song plays holding that
    /// channel's Bank Select, Program Change and mixer settings, in that order at tick 0. The patch and
    /// mixer options apply; the SysEx is always included. Nil if the song has nothing to set up.
    public static func setupMIDIData(for svq: SVQFile, title: String? = nil,
                                     options: SVQConversionOptions = SVQConversionOptions()) -> Data? {
        var options = options
        options.addPerformanceSysEx = true
        let resolution = svq.resolution
        let tempo = TempoMap(resolution: resolution, initialTempo: svq.initialTempo)

        var conductor = MIDITrackBuilder()
        conductor.addText(0x03, title ?? "\(svq.songName) - Song Setup")
        conductor.addText(0x02, svq.comment)
        for event in svq.events where event.isConductorEvent && event.tick == 0 {
            addConductorEvent(event, at: 0, to: &conductor)
        }

        let (setupTrack, sendsSavedSounds) = setupSysExTrack(svq: svq, options: options, tempo: tempo)
        let parts = channelSetupParts(svq: svq, usedChannels: svq.internallyPlayedChannels)
        var channelTracks: [MIDITrackBuilder] = []
        for channel in parts.keys.sorted() {
            guard let part = parts[channel] else { continue }
            let messages = channelSetup(part: part, channel: channel, svq: svq, options: options,
                                        sendsSavedSounds: sendsSavedSounds)
            if messages.isEmpty { continue }
            var track = MIDITrackBuilder()
            track.addText(0x03, "Ch \(channel + 1): Part \(part.label) \(part.displayName)")
            for message in messages { track.add(message, at: 0, priority: .setup) }
            channelTracks.append(track)
        }
        if setupTrack == nil && channelTracks.isEmpty { return nil }

        // At least one measure long, so a DAW shows a region that can be seen and played.
        let measure = svq.initialTimeSignature.ticksPerMeasure(resolution: resolution)
        let last = ([setupTrack].compactMap { $0 } + channelTracks).map(\.lastTick).max() ?? 0
        let endTick = max(measure, last + 1)
        return MIDIFileWriter.file(format: 1, division: resolution,
                                   tracks: ([conductor] + [setupTrack].compactMap { $0 } + channelTracks)
                                       .map { $0.encoded(endTick: endTick) })
    }

    private static func phraseTrackName(svq: SVQFile, track: Int, channels: Set<UInt8>) -> String {
        let label = "Track \(track + 1)"
        switch svq.output(ofTrack: track) {
        case .midi: return "\(label): MIDI Out"
        case .off: return "\(label): Off"
        default: break
        }
        guard let part = partName(svq: svq, channels: channels) else { return label }
        return "\(label): \(part)"
    }

    /// Converts one of the file's patterns (XP RPS phrases or Fantom-X patterns) to its own Standard MIDI File.
    public static func midiData(for svq: SVQFile, pattern: SVQPattern, title: String? = nil,
                                options: SVQConversionOptions = SVQConversionOptions()) -> Data {
        let name = title ?? "\(svq.songName) - \(pattern.label)"
        // Patterns carry their own meter but use the song's tempo.
        var events = pattern.events
        if !events.contains(where: { if case .tempo = $0.kind { return $0.tick == 0 } else { return false } }) {
            events.insert(SVQEvent(tick: 0, track: 0, kind: .tempo(microsecondsPerQuarter: svq.initialTempo)), at: 0)
        }
        return build(svq: svq, title: name, events: events, length: pattern.length,
                     trackFor: { _ in 0xFF }, trackName: { _, channels in // not a phrase track: no Output setting
                         partName(svq: svq, channels: channels) ?? pattern.label
                     }, copyright: svq.comment, options: options)
    }

    // MARK: - Implementation

    private static func partName(svq: SVQFile, channels: Set<UInt8>) -> String? {
        guard channels.count == 1, let channel = channels.first,
              let part = svq.setup?.parts.first(where: { $0.receiveSwitch && $0.midiChannel == Int(channel) })
        else { return nil }
        return part.displayName
    }

    private static func build(svq: SVQFile, title: String, events: [SVQEvent], length: Int,
                              trackFor: (SVQEvent) -> Int,
                              trackName: (Int, Set<UInt8>) -> String,
                              copyright: String,
                              options: SVQConversionOptions) -> Data {
        let resolution = svq.resolution
        let initialMeter = events.first(where: {
            if case .timeSignature = $0.kind { return $0.tick == 0 } else { return false }
        }).flatMap { event -> SVQTimeSignature? in
            if case .timeSignature(let ts) = event.kind { return ts } else { return nil }
        } ?? svq.initialTimeSignature
        let initialTempo = events.first(where: {
            if case .tempo = $0.kind { return $0.tick == 0 } else { return false }
        }).flatMap { event -> Int? in
            if case .tempo(let t) = event.kind { return t } else { return nil }
        } ?? svq.initialTempo

        let measure = initialMeter.ticksPerMeasure(resolution: resolution)
        let leadIn = max(0, options.leadInMeasures) * measure

        // The output's tempo map (the lead-in keeps the initial tempo), used to place setup messages
        // at real times even though they now overlap the song.
        var tempo = TempoMap(resolution: resolution, initialTempo: initialTempo)
        for event in events {
            if case .tempo(let us) = event.kind, event.tick > 0 { tempo.add(tick: event.tick + leadIn, microsecondsPerQuarter: us) }
        }

        // Conductor track.
        var conductor = MIDITrackBuilder()
        conductor.addText(0x03, title)
        conductor.addText(0x02, copyright)
        for event in events where event.isConductorEvent {
            addConductorEvent(event, at: event.tick == 0 ? 0 : event.tick + leadIn, to: &conductor)
        }

        // Group the musical events into output tracks.
        var grouped: [Int: [SVQEvent]] = [:]
        for event in events where !event.isConductorEvent {
            grouped[trackFor(event), default: []].append(event)
        }
        let trackNumbers = grouped.keys.sorted()

        // Channel setup (bank/program/mixer). Only channels that the instrument's own sound generator
        // plays get its Part setup; tracks sent only to MIDI Out were playing another instrument.
        let internalChannels = Set(events.filter { svq.output(ofTrack: trackFor($0)).playsInternally }.compactMap(\.channel))
        let setupParts = channelSetupParts(svq: svq, usedChannels: internalChannels)

        // The setup SysEx goes on a track of its own, starting at tick 0 alongside the song: solo it
        // for the first play to set up the instrument, then mute it. It holds only SysEx, so a DAW
        // that gives each track one MIDI channel can't send any of it on the wrong channel.
        let (setupTrack, sendsSavedSounds) = setupSysExTrack(svq: svq, options: options, tempo: tempo)
        // A song shorter than its setup data still lasts until the setup has been sent.
        let endTick = max(length + leadIn, (setupTrack?.lastTick ?? 0) + 1)

        func channelSetup(_ channel: UInt8) -> [[UInt8]] {
            guard let part = setupParts[channel] else { return [] }
            return SVQConverter.channelSetup(part: part, channel: channel, svq: svq, options: options,
                                             sendsSavedSounds: sendsSavedSounds)
        }
        var channelsSetUp = Set<UInt8>()

        // The first tick at which the song itself sends each controller (status byte and number) or
        // Program Change (status byte). The setup leaves out whatever the song sends at tick 0, so
        // the song's own values win.
        var songSends: [[UInt8]: Int] = [:]
        for event in events {
            guard case .channelMessage(let bytes) = event.kind, let status = bytes.first else { continue }
            let key = status & 0xF0 == 0xB0 ? Array(bytes.prefix(2)) : status & 0xF0 == 0xC0 ? [status] : []
            if !key.isEmpty { songSends[key] = min(songSends[key] ?? .max, event.tick + leadIn) }
        }

        var trackChunks: [[UInt8]] = []
        for number in trackNumbers {
            let trackEvents = grouped[number] ?? []
            let channels = Set(trackEvents.compactMap(\.channel))
            var builder = MIDITrackBuilder()
            builder.addText(0x03, trackName(number, channels))

            // Each channel's setup goes at tick 0 of the first track that plays it, in order (Bank
            // Select, then Program Change, then the mixer) and ahead of the track's own tick-0 events,
            // so the first notes already play the right sound. Spreading the setup over several ticks
            // let notes at tick 0 sound before the Program Change on the first play. A track holds
            // one channel's setup at a time in practice (DAWs such as Logic give a track one channel),
            // and a track keeps its own order of same-tick events.
            let setupChannels = svq.output(ofTrack: number).playsInternally ? channels : []
            for channel in setupChannels.sorted() where !channelsSetUp.contains(channel) && setupParts[channel] != nil {
                channelsSetUp.insert(channel)
                for message in channelSetup(channel) {
                    let key = message[0] & 0xF0 == 0xB0 ? Array(message.prefix(2)) : [message[0]]
                    if songSends[key] == 0 { continue } // the song sets it itself at the same tick
                    builder.add(message, at: 0, priority: .setup)
                }
            }

            for event in trackEvents {
                let tick = event.tick + leadIn
                switch event.kind {
                case .note(let channel, let key, let velocity, let release, let gate):
                    builder.add([0x90 | channel, key, max(1, velocity)], at: tick)
                    builder.add([0x80 | channel, key, release], at: tick + gate, priority: .noteOff)
                case .channelMessage(let bytes):
                    builder.add(bytes, at: tick)
                case .sysEx(let message):
                    builder.addSysEx(message, at: tick)
                default:
                    break
                }
            }
            trackChunks.append(builder.encoded(endTick: endTick))
        }

        return MIDIFileWriter.file(format: 1, division: resolution,
                                   tracks: [conductor.encoded(endTick: endTick)]
                                       + (setupTrack.map { [$0.encoded(endTick: endTick)] } ?? []) + trackChunks)
    }

    /// The setup SysEx track (nil if the option is off or there's nothing to send), and whether it
    /// sends the Fantom-X Parts' saved sounds.
    static func setupSysExTrack(svq: SVQFile, options: SVQConversionOptions,
                                tempo: TempoMap) -> (track: MIDITrackBuilder?, sendsSavedSounds: Bool) {
        guard options.addPerformanceSysEx else { return (nil, false) }
        if let performance = svq.performance {
            // XP: the Performance, spaced so the XP can process each message.
            var track = MIDITrackBuilder()
            track.addText(0x03, setupTrackName)
            track.addText(0x01, "XP-80 Performance \"\(performance.name)\". \(setupTrackNote)")
            for (i, message) in performance.sysExMessages(deviceID: options.sysExDeviceID).enumerated() {
                track.addSysEx(message, at: tempo.ticks(microseconds: i * sysExIntervalMicroseconds), priority: .setup)
            }
            return (track, false)
        }
        if let fantom = svq.fantomPerformance {
            // Fantom-X: every saved sound, each message waiting for the previous one's transmission
            // time plus a processing gap.
            let messages = fantomSoundMessages(fantom, deviceID: options.sysExDeviceID)
            if messages.isEmpty { return (nil, false) }
            var track = MIDITrackBuilder()
            track.addText(0x03, setupTrackName)
            let what = fantom.soundMode == nil || fantom.soundMode == .performance
                ? "Fantom-X Performance \"\(fantom.name)\" (effects and Part settings unverified), then the Parts' Patches and Rhythm Sets"
                : "Fantom-X Patch mode keyboard and pad sounds"
            track.addText(0x01, "\(what) (Rhythm Set data unverified). \(setupTrackNote)")
            var time = 0
            for message in messages {
                track.addSysEx(message, at: tempo.ticks(microseconds: time), priority: .setup)
                time += message.count * midiByteMicroseconds + fantomDumpGapMicroseconds
            }
            return (track, true)
        }
        return (nil, false)
    }

    /// A channel's setup: Bank Select MSB, LSB, Program Change, then level, pan, reverb and chorus.
    static func channelSetup(part: SetupPart, channel: UInt8, svq: SVQFile, options: SVQConversionOptions,
                             sendsSavedSounds: Bool) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        let cc: UInt8 = 0xB0 | channel
        let boards = svq.performance?.expansionBoards ?? []
        // A Program Change would replace a Fantom-X Part's sound sent by the setup track.
        if options.addPatchSelection, !(sendsSavedSounds && part.hasSavedSound),
           let bank = part.bankSelect(slotForBoard: { options.slot(forBoard: $0, boardsInUse: boards) }) {
            messages += [[cc, 0, bank.msb], [cc, 32, bank.lsb], [0xC0 | channel, bank.program]]
        }
        if options.addMixerSettings, part.hasMixerSettings {
            messages += [[cc, 7, UInt8(part.level & 0x7F)], [cc, 10, UInt8(part.pan & 0x7F)],
                         [cc, 91, UInt8(part.reverbSendLevel & 0x7F)], [cc, 93, UInt8(part.chorusSendLevel & 0x7F)]]
        }
        return messages
    }

    static func addConductorEvent(_ event: SVQEvent, at tick: Int, to track: inout MIDITrackBuilder) {
        switch event.kind {
        case .tempo(let us):
            track.addMeta(0x51, MIDIFileWriter.bigEndian(us, bytes: 3), at: tick)
        case .timeSignature(let ts):
            track.addMeta(0x58, [ts.numerator, ts.denominatorPower, ts.clocksPerClick, ts.thirtySecondsPerQuarter], at: tick)
        case .keySignature(let sf, let minor):
            track.addMeta(0x59, [UInt8(bitPattern: sf), minor ? 1 : 0], at: tick)
        default:
            break
        }
    }

    /// The setup track's name, and the instructions in its text event.
    static let setupTrackName = "Setup SysEx (solo once, then mute)"
    static let setupTrackNote = "Solo this track and play it through once to set up the instrument; "
        + "then mute it and play the song."

    /// Fantom-X dump timing: MIDI sends one byte per 320 µs; Roland asks for at least 20 ms between
    /// SysEx packets.
    static let midiByteMicroseconds = 320
    static let fantomDumpGapMicroseconds = 20_000

    /// For a song saved in Performance mode, the Performance itself (its effects and Part settings;
    /// unverified, see `FantomPerformance.performanceSysExMessages`); then the saved sound of every
    /// Performance Part (whether or not the song plays it) and of Patch mode's keyboard and pad
    /// parts, as Fantom-X Data Set 1 messages to their temporary areas. The Performance goes first:
    /// its Part settings select each Part's stored sound, which the saved sounds then replace.
    static func fantomSoundMessages(_ fantom: FantomPerformance, deviceID: UInt8) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        if fantom.soundMode == nil || fantom.soundMode == .performance {
            messages += fantom.performanceSysExMessages(deviceID: deviceID)
        }
        for part in fantom.parts {
            if let sound = fantom.savedSound(of: part) {
                messages += sound.sysExMessages(to: FantomPatch.temporaryAddress(forPart: part.number), deviceID: deviceID)
            }
        }
        if let keyboard = fantom.keyboardPart, let sound = fantom.savedSound(of: keyboard) {
            messages += sound.sysExMessages(to: FantomPatch.keyboardAddress, deviceID: deviceID)
        }
        if let pad = fantom.padPart, let sound = fantom.savedSound(of: pad) {
            messages += sound.sysExMessages(to: FantomPatch.padAddress, deviceID: deviceID)
        }
        return messages
    }

    /// For each MIDI channel that the song uses, the lowest-numbered receiving Part on that channel.
    static func channelSetupParts(svq: SVQFile, usedChannels: Set<UInt8>) -> [UInt8: SetupPart] {
        var result: [UInt8: SetupPart] = [:]
        for part in svq.setup?.parts ?? [] where part.receiveSwitch {
            let channel = UInt8(part.midiChannel & 0x0F)
            if usedChannels.contains(channel), result[channel] == nil { result[channel] = part }
        }
        return result
    }
}

/// A file's tempo changes, for placing events at real times.
struct TempoMap {
    let resolution: Int
    private(set) var segments: [(tick: Int, microsecondsPerQuarter: Int)]

    init(resolution: Int, initialTempo: Int) {
        self.resolution = resolution
        segments = [(0, initialTempo)]
    }

    mutating func add(tick: Int, microsecondsPerQuarter: Int) {
        segments.append((tick, microsecondsPerQuarter))
        segments.sort { $0.tick < $1.tick }
    }

    /// The first tick at or after `microseconds` from the start of the file.
    func ticks(microseconds: Int) -> Int {
        var remaining = Double(microseconds)
        for (i, segment) in segments.enumerated() {
            let usPerTick = Double(segment.microsecondsPerQuarter) / Double(resolution)
            if i + 1 < segments.count {
                let span = Double(segments[i + 1].tick - segment.tick) * usPerTick
                if remaining > span { remaining -= span; continue }
            }
            return segment.tick + Int((remaining / usPerTick).rounded(.up))
        }
        return 0
    }
}
