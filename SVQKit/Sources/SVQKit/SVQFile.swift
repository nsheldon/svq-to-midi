import Foundation

// MARK: - Errors

public enum SVQError: Error, LocalizedError, Equatable {
    case tooShort
    case notSVQ
    case corruptHeader(String)

    public var errorDescription: String? {
        switch self {
        case .tooShort: return "The file is too short to be a Roland SVQ sequence."
        case .notSVQ: return "The file is not a Roland SVQ sequence (missing \"SV\" signature)."
        case .corruptHeader(let detail): return "The SVQ header is damaged: \(detail)"
        }
    }
}

// MARK: - Events

public struct SVQTimeSignature: Equatable, Hashable, Sendable {
    public var numerator: UInt8
    /// Denominator as a power of two (2 = quarter note).
    public var denominatorPower: UInt8
    public var clocksPerClick: UInt8
    public var thirtySecondsPerQuarter: UInt8

    public init(numerator: UInt8, denominatorPower: UInt8, clocksPerClick: UInt8 = 24, thirtySecondsPerQuarter: UInt8 = 8) {
        self.numerator = numerator
        self.denominatorPower = denominatorPower
        self.clocksPerClick = clocksPerClick
        self.thirtySecondsPerQuarter = thirtySecondsPerQuarter
    }

    public static let fourFour = SVQTimeSignature(numerator: 4, denominatorPower: 2)

    /// Length of one measure in ticks at the given resolution (ticks per quarter note).
    public func ticksPerMeasure(resolution: Int) -> Int {
        let quarterNotesTimes8 = Int(numerator) * 32 >> Int(min(denominatorPower, 5))
        return max(1, quarterNotesTimes8 * resolution / 8)
    }

    public var displayString: String { "\(numerator)/\(1 << Int(min(denominatorPower, 6)))" }
}

public struct SVQEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A note with its gate (duration) in ticks and its release (note-off) velocity.
        case note(channel: UInt8, key: UInt8, velocity: UInt8, releaseVelocity: UInt8, gate: Int)
        /// A complete MIDI channel message (status byte + data bytes): CC, program change, aftertouch, bend.
        case channelMessage([UInt8])
        /// A complete System Exclusive message including the F0 and F7 bytes.
        case sysEx([UInt8])
        case tempo(microsecondsPerQuarter: Int)
        case timeSignature(SVQTimeSignature)
        case keySignature(sharpsFlats: Int8, minor: Bool)
    }

    /// Absolute position in ticks (relative to the start of the song, or of the pattern).
    public var tick: Int
    /// Sequencer track number (0-15 for the song's phrase tracks). Meaningless for tempo/meter/key events.
    public var track: Int
    public var kind: Kind

    public init(tick: Int, track: Int, kind: Kind) {
        self.tick = tick
        self.track = track
        self.kind = kind
    }

    public var isConductorEvent: Bool {
        switch kind {
        case .tempo, .timeSignature, .keySignature: return true
        default: return false
        }
    }

    /// The MIDI channel (0-15) this event plays on, if it is a channel event.
    public var channel: UInt8? {
        switch kind {
        case .note(let channel, _, _, _, _): return channel
        case .channelMessage(let bytes): return bytes.first.map { $0 & 0x0F }
        default: return nil
        }
    }
}

/// A phrase track's instruction to play a pattern from a given tick (Fantom-X).
public struct SVQPatternCall: Equatable, Sendable {
    public var tick: Int
    /// The phrase track (0-15) that plays the pattern.
    public var track: Int
    /// `SVQPattern.number` of the pattern played, or nil if the file doesn't contain it.
    public var patternNumber: Int?
}

/// One key of the song's RPS (Realtime Phrase Sequence) setup.
public struct SVQRPSAssignment: Equatable, Sendable {
    public enum Mode: Int, Sendable {
        /// Repeats while the key is held.
        case loop1
        /// Starts on a key press and repeats until stopped.
        case loop2
        /// Plays once.
        case once

        public var displayName: String {
            switch self {
            case .loop1: return "LOOP1"
            case .loop2: return "LOOP2"
            case .once: return "ONCE"
            }
        }
    }

    /// The MIDI note number of the key.
    public var key: UInt8
    /// The pattern the key plays, or nil for the STOP key (or a key with only a Mute Group).
    public var patternNumber: Int?
    public var mode: Mode?
    /// The key's Mute Group (1-32), if it has one.
    public var muteGroup: Int?

    public init(key: UInt8, patternNumber: Int? = nil, mode: Mode? = nil, muteGroup: Int? = nil) {
        self.key = key
        self.patternNumber = patternNumber
        self.mode = mode
        self.muteGroup = muteGroup
    }

    /// The key as the instruments name it (middle C = C4).
    public var keyName: String { SVQEventSummary.noteName(key) }

    /// For example "D2 LOOP2" or "C2 STOP".
    public var summary: String {
        var parts = [keyName]
        if patternNumber == nil, mode != nil { parts.append("STOP") }
        if let mode, patternNumber != nil { parts.append(mode.displayName) }
        if let muteGroup { parts.append("group \(muteGroup)") }
        return parts.joined(separator: " ")
    }
}

/// A pattern (phrase) stored after the song data. On the XP series these are the
/// phrases used by RPS (Realtime Phrase Sequence); they are not part of song playback.
public struct SVQPattern: Equatable, Sendable {
    /// The track identifier byte used inside the file (0xFF for the first pattern, 0xFE for the next, ...).
    public var identifier: UInt8
    /// The pattern's number on the instrument (1-100), from its ID: FF is pattern 1, FE pattern 2 ...
    /// (one Fantom-X song stores patterns 1-4, 10, 12 and 13 with IDs FF-FC, F6, F4 and F3, and its RPS
    /// assignments name those numbers).
    public var number: Int
    /// The pattern's name ("" if it has none).
    public var name = ""
    public var events: [SVQEvent]
    /// Length in ticks.
    public var length: Int

    /// "Pattern 1 Beat", or "Pattern 1" for a pattern without a name.
    public var label: String { name.isEmpty ? "Pattern \(number)" : "Pattern \(number) \(name)" }

    /// The same with a two-digit number, for file names: "Pattern 01 Beat".
    public var fileLabel: String {
        let number = String(format: "%02d", self.number)
        return name.isEmpty ? "Pattern \(number)" : "Pattern \(number) \(name)"
    }

    /// The pattern number an ID stands for (FF = 1 … 9C = 100); `fallback` for any other ID.
    static func number(forIdentifier id: UInt8, fallback: Int) -> Int {
        id >= 0x9C ? 256 - Int(id) : fallback
    }
}

// MARK: - File

/// A phrase track's Output setting.
public enum SVQTrackOutput: Equatable, Sendable {
    case off, `internal`, midi, both

    init(flags: UInt8) {
        switch (flags & 0x80 != 0, flags & 0x01 != 0) {
        case (true, true): self = .both
        case (true, false): self = .internal
        case (false, true): self = .midi
        case (false, false): self = .off
        }
    }

    public var playsInternally: Bool { self == .internal || self == .both }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .internal: return "INT"
        case .midi: return "MIDI Out"
        case .both: return "Both"
        }
    }
}

public enum SVQVariant: String, Sendable {
    /// XP-50/60/80: 8-byte records with an 8-bit step.
    case xp
    /// Fantom-X (MC-80 sequencer engine): 12-byte records with a 16-bit step and 32-bit gate.
    case fantomX

    var recordLayout: (size: Int, stepBytes: Int, dataOffset: Int) {
        switch self {
        case .xp: return (8, 1, 4)
        case .fantomX: return (12, 2, 5)
        }
    }

    public var displayName: String {
        switch self {
        case .xp: return "XP-50/60/80"
        case .fantomX: return "Fantom-X"
        }
    }
}

/// A Roland "SVQ" sequence file as written by the XP-50/XP-60/XP-80 ("SV00") or by the
/// Fantom-X6/X7/X8 and other MC-80-based sequencers ("SV03").
///
/// See `docs/SVQ-Format.md` in the project for the reverse-engineered format.
public struct SVQFile: Sendable {
    /// Ticks per quarter note (96 on the XP series).
    public var resolution: Int
    /// The instrument/OS identifier stored in the header, e.g. "XP-80 0105 1.7".
    public var model: String
    public var songName: String
    /// Optional second header string (Roland demo songs store a copyright notice here).
    public var comment: String
    /// Song events, sorted by tick in file order.
    public var events: [SVQEvent]
    /// Length of the song in ticks (the latest End-of-Track marker).
    public var songLength: Int
    public var patterns: [SVQPattern]
    /// Raw data blocks from the embedded "SVD" directory, keyed by tag (e.g. "PRFa", "SYSa", "SYSb").
    public var dataBlocks: [String: [UInt8]]
    /// Which instrument family wrote the file.
    public var variant: SVQVariant
    /// Each phrase track's Output setting (tracks 1-16).
    public var trackOutputs: [SVQTrackOutput]
    /// Phrase tracks (0-15) that were probably muted when the song was saved. **Unconfirmed**: read
    /// from a header mask that is all ones in every sample except one, where it clears exactly
    /// the empty tracks; the XP-80 manual says mute status is saved with the song. Shown only: the
    /// converter still includes muted tracks.
    public var mutedTracks: Set<Int> = []
    /// The XP Performance (patch/part setup) saved with the song, if present.
    public var performance: XPPerformance?
    /// The Fantom-X Performance saved with the song, if present.
    public var fantomPerformance: FantomPerformance?
    /// The song's pattern calls (Fantom-X), which were expanded into the song's events.
    public var patternCalls: [SVQPatternCall]
    /// Number of pattern-call events (Fantom-X phrase references) that were expanded into the song.
    public var patternCallCount: Int { patternCalls.count }
    /// RPS (Realtime Phrase Sequence) key assignments saved with the song, in key order.
    public var rpsAssignments: [SVQRPSAssignment] = []
    /// Count of record types that were not understood and were skipped.
    public var unknownRecordTypes: [UInt8: Int]
    public var warnings: [String]

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let b = [UInt8](data)
        guard b.count >= 0x30 else { throw SVQError.tooShort }
        guard b[2] == 0x53, b[3] == 0x56 else { throw SVQError.notSVQ } // "SV"

        var warnings: [String] = []
        let headerLength = Int(b[0]) << 8 | Int(b[1])
        let dataStart = headerLength + 2
        guard headerLength >= 0x2C, dataStart <= b.count else {
            throw SVQError.corruptHeader("header length \(headerLength) is out of range")
        }

        var resolution = Int(b[6]) << 8 | Int(b[7])
        if resolution <= 0 {
            warnings.append("Missing resolution; assuming 96 ticks per quarter note.")
            resolution = 96
        }
        self.resolution = resolution
        model = SVQFile.text(b[0x11 ..< 0x21])

        // Two length-prefixed strings follow the model string: song name, then comment.
        var p = 0x21
        func pascalString() -> String {
            guard p < dataStart else { return "" }
            let n = Int(b[p])
            let end = min(p + 1 + n, dataStart)
            let s = SVQFile.text(b[(p + 1) ..< end])
            p = end
            return s
        }
        songName = pascalString()
        comment = pascalString()

        // Song settings follow: 10 02 FF FF 02 xx xx, then a count (16) and one byte per phrase
        // track holding its Output setting (bit 7 = internal sound generator, bit 0 = MIDI Out).
        if p + 24 <= dataStart, b[p] == 0x10, b[p + 7] == 16 {
            trackOutputs = (0 ..< 16).map { SVQTrackOutput(flags: b[p + 8 + $0]) }
            // `10 02`, then mask A (bit n = track n+1; probably "not muted", see `mutedTracks`), `02`, then
            // mask B (the tracks that exist).
            if b[p + 1] == 0x02, b[p + 4] == 0x02 {
                let playing = Int(b[p + 2]) << 8 | Int(b[p + 3])
                mutedTracks = Set((0 ..< 16).filter { playing >> $0 & 1 == 0 })
            }
        } else {
            trackOutputs = Array(repeating: .both, count: 16)
        }

        // Then length-prefixed song settings (u16 length, data): the Loop settings, then the RPS
        // settings (4 bytes, then 3 per entry: key, pattern number - 1 or FF for STOP, playback mode;
        // an entry whose key has bit 7 set gives that key's Mute Group as a u16 instead).
        var chunks: [[UInt8]] = []
        var q = p + 24
        while q + 2 <= dataStart - 4 {
            let n = Int(b[q]) << 8 | Int(b[q + 1])
            guard q + 2 + n <= dataStart - 4 else { break }
            chunks.append(Array(b[(q + 2) ..< (q + 2 + n)]))
            q += 2 + n
        }
        if chunks.count > 1, chunks[1].count > 4 {
            let rps = chunks[1]
            var byKey: [UInt8: SVQRPSAssignment] = [:]
            var i = 4
            while i + 3 <= rps.count {
                let key = rps[i] & 0x7F
                var entry = byKey[key] ?? SVQRPSAssignment(key: key)
                if rps[i] & 0x80 != 0 {
                    entry.muteGroup = Int(rps[i + 1]) << 8 | Int(rps[i + 2])
                } else {
                    entry.patternNumber = rps[i + 1] == 0xFF ? nil : Int(rps[i + 1]) + 1
                    entry.mode = SVQRPSAssignment.Mode(rawValue: Int(rps[i + 2]))
                }
                byKey[key] = entry
                i += 3
            }
            rpsAssignments = byKey.values.sorted { $0.key < $1.key }
        }

        let variant: SVQVariant = (b[4] == 0x30 && b[5] == 0x30) ? .xp : .fantomX
        if variant == .fantomX, !(b[4] == 0x30 && b[5] == 0x33) {
            warnings.append("Unrecognized SVQ version \"SV\(Character(UnicodeScalar(b[4])))\(Character(UnicodeScalar(b[5])))\"; reading it like a Fantom-X file.")
        }
        self.variant = variant
        let layout = variant.recordLayout

        let declaredLength = Int(b[dataStart - 4]) << 24 | Int(b[dataStart - 3]) << 16
            | Int(b[dataStart - 2]) << 8 | Int(b[dataStart - 1])
        var dataEnd = dataStart + declaredLength
        if dataEnd > b.count {
            warnings.append("The sequence data is truncated; converting what is present.")
            dataEnd = b.count
        }
        if declaredLength % layout.size != 0 {
            warnings.append("The sequence length is not a multiple of \(layout.size) bytes; trailing bytes were ignored.")
        }

        // MARK: Event records
        var events: [SVQEvent] = []
        var patterns: [SVQPattern] = []
        var patternCalls: [(tick: Int, track: Int, pattern: UInt8)] = []
        var trackEnds: [Int: Int] = [:]
        var unknown: [UInt8: Int] = [:]
        var tick = 0
        var songEnd = 0
        var tempoNumerator: Int?
        var sysEx: (track: Int, tick: Int, length: Int, bytes: [UInt8])?
        var pattern: (identifier: UInt8, start: Int, events: [SVQEvent])?

        func u32(_ o: Int) -> Int {
            Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }
        func append(_ event: SVQEvent) {
            if pattern != nil {
                var e = event
                e.tick -= pattern!.start
                pattern!.events.append(e)
            } else {
                events.append(event)
            }
        }

        var off = dataStart
        while off + layout.size <= dataEnd {
            // Record: step (1 or 2 bytes), type, channel, track, then data bytes.
            let step = layout.stepBytes == 1 ? Int(b[off]) : Int(b[off]) << 8 | Int(b[off + 1])
            let type = b[off + layout.stepBytes]
            let channelByte = b[off + layout.stepBytes + 1]
            let trackByte = b[off + layout.stepBytes + 2]
            let track = Int(trackByte)
            let d = off + layout.dataOffset // first data byte
            let lastWord = u32(off + layout.size - 4)

            if type != 0x92, let pending = sysEx {
                warnings.append("A System Exclusive message at tick \(pending.tick) was incomplete and was dropped.")
                sysEx = nil
            }

            switch type {
            case 0x00 ... 0x7F:
                let rawGate = layout.size == 8 ? Int(b[d + 2]) << 8 | Int(b[d + 3]) : lastWord
                append(SVQEvent(tick: tick, track: track, kind: .note(
                    channel: channelByte & 0x0F, key: type, velocity: b[d] & 0x7F,
                    releaseVelocity: b[d + 1] & 0x7F, gate: max(1, rawGate))))

            case 0x80:
                break // rest: only advances time

            case 0x82:
                append(SVQEvent(tick: tick, track: track, kind: .timeSignature(SVQTimeSignature(
                    numerator: max(1, b[d]), denominatorPower: min(b[d + 1], 6)))))

            case 0x83:
                tempoNumerator = lastWord

            case 0x84:
                // Tempo is stored as a ratio: (time units) / (ticks), with 24,000 time units per second.
                if let numerator = tempoNumerator, lastWord > 0, numerator > 0 {
                    // µs per quarter = numerator × resolution × 1,000,000 / 24,000 / denominator, rounded.
                    let usPerQuarter = (numerator * resolution * 250 + 3 * lastWord) / (6 * lastWord)
                    append(SVQEvent(tick: tick, track: track,
                                    kind: .tempo(microsecondsPerQuarter: min(max(usPerQuarter, 1), 0xFFFFFF))))
                }
                tempoNumerator = nil

            case 0x86:
                append(SVQEvent(tick: tick, track: track, kind: .keySignature(
                    sharpsFlats: max(-7, min(7, Int8(bitPattern: b[d]))), minor: b[d + 1] != 0)))

            case 0x87:
                // Pattern call: this track plays the pattern whose identifier is in the first data byte.
                if pattern == nil { patternCalls.append((tick, track, b[d])) }

            case 0x88:
                break // size bookkeeping

            case 0x89:
                if let open = pattern {
                    patterns.append(SVQPattern(identifier: open.identifier, number: SVQPattern.number(forIdentifier: open.identifier, fallback: patterns.count + 1),
                                               events: open.events, length: tick - open.start))
                }
                pattern = (trackByte, tick, [])

            case 0x8E:
                if let open = pattern {
                    if trackByte == open.identifier {
                        patterns.append(SVQPattern(identifier: open.identifier, number: SVQPattern.number(forIdentifier: open.identifier, fallback: patterns.count + 1),
                                                   events: open.events, length: tick - open.start))
                        pattern = nil
                    }
                } else {
                    songEnd = max(songEnd, tick)
                    trackEnds[track] = tick
                }

            case 0x8F:
                break // end of song

            case 0x91:
                sysEx = (track, tick, lastWord, [])

            case 0x92:
                if var pending = sysEx {
                    pending.bytes.append(contentsOf: b[d ..< (off + layout.size)])
                    if pending.bytes.count >= pending.length {
                        let message = Array(pending.bytes.prefix(pending.length))
                        if message.first == 0xF0 {
                            append(SVQEvent(tick: pending.tick, track: pending.track, kind: .sysEx(message)))
                        }
                        sysEx = nil
                    } else {
                        sysEx = pending
                    }
                }

            case 0x9A ... 0x9E:
                // Channel message; the first data byte holds the actual MIDI status byte.
                var status = b[d]
                let expectedHigh = (type - 0x90) << 4 | 0x80
                if status & 0xF0 != expectedHigh { status = expectedHigh | (channelByte & 0x0F) }
                let message: [UInt8]
                switch status & 0xF0 {
                case 0xC0, 0xD0: message = [status, b[d + 1] & 0x7F]
                default: message = [status, b[d + 1] & 0x7F, b[d + 2] & 0x7F]
                }
                append(SVQEvent(tick: tick, track: track, kind: .channelMessage(message)))

            default:
                unknown[type, default: 0] += 1
            }

            tick += step
            off += layout.size
        }

        if let open = pattern {
            patterns.append(SVQPattern(identifier: open.identifier, number: SVQPattern.number(forIdentifier: open.identifier, fallback: patterns.count + 1),
                                       events: open.events, length: tick - open.start))
        }

        // MARK: Expand pattern calls into the song
        if !patternCalls.isEmpty {
            var byIdentifier: [UInt8: SVQPattern] = [:]
            for p in patterns where byIdentifier[p.identifier] == nil { byIdentifier[p.identifier] = p }
            var missing = 0
            var expanded: [SVQEvent] = []
            for (track, calls) in Dictionary(grouping: patternCalls, by: { $0.track }) {
                let ordered = calls.sorted { $0.tick < $1.tick }
                for (i, call) in ordered.enumerated() {
                    guard let called = byIdentifier[call.pattern] else { missing += 1; continue }
                    // A call plays until the pattern ends, the track's next call, or the end of the track.
                    var window = called.length
                    if i + 1 < ordered.count { window = min(window, ordered[i + 1].tick - call.tick) }
                    if let end = trackEnds[track] { window = min(window, end - call.tick) }
                    for event in called.events where !event.isConductorEvent && event.tick < window {
                        var copy = event
                        copy.tick += call.tick
                        copy.track = track
                        expanded.append(copy)
                    }
                }
            }
            if missing > 0 {
                warnings.append("\(missing) pattern call\(missing == 1 ? "" : "s") referred to a missing pattern and were skipped.")
            }
            events = (events + expanded).enumerated()
                .sorted { $0.element.tick != $1.element.tick ? $0.element.tick < $1.element.tick : $0.offset < $1.offset }
                .map(\.element)
        }
        self.patternCalls = patternCalls.map { call in
            SVQPatternCall(tick: call.tick, track: call.track,
                           patternNumber: patterns.first { $0.identifier == call.pattern }?.number)
        }

        var lastSongTick = 0
        for event in events {
            var end = event.tick
            if case .note(_, _, _, _, let gate) = event.kind { end += gate }
            lastSongTick = max(lastSongTick, end)
        }

        self.events = events
        self.patterns = patterns
        self.songLength = songEnd > 0 ? max(songEnd, lastSongTick) : lastSongTick
        self.unknownRecordTypes = unknown
        if !unknown.isEmpty {
            let list = unknown.keys.sorted().map { String(format: "0x%02X", $0) }.joined(separator: ", ")
            warnings.append("Skipped unrecognized sequence record types: \(list).")
        }

        // MARK: Pattern names
        // After the event data: the length of the rest (u16 on the XP, u32 on the Fantom-X); on the XP
        // a 40-byte block (zeros in every sample); then a u16-length list of pattern names, each
        // pattern ID, name length, name.
        var namesAt = variant == .xp ? dataEnd + 2 : dataEnd + 4
        if variant == .xp, namesAt + 2 <= b.count { namesAt += 2 + (Int(b[namesAt]) << 8 | Int(b[namesAt + 1])) }
        if namesAt + 2 <= b.count {
            let n = Int(b[namesAt]) << 8 | Int(b[namesAt + 1])
            var i = namesAt + 2
            while i + 2 <= min(namesAt + 2 + n, b.count) {
                let id = b[i], length = Int(b[i + 1])
                guard i + 2 + length <= b.count else { break }
                let name = SVQFile.text(b[(i + 2) ..< (i + 2 + length)])
                for k in patterns.indices where patterns[k].identifier == id { patterns[k].name = name }
                i += 2 + length
            }
        }
        self.patterns = patterns

        // MARK: Embedded "SVD" directory (system + performance data)
        var blocks: [String: [UInt8]] = [:]
        let directory = SVQFile.find([0x53, 0x56, 0x44, 0x30], in: b, from: dataEnd)   // "SVD0" (XP)
            ?? SVQFile.find([0x53, 0x56, 0x44, 0x31], in: b, from: dataEnd)            // "SVD1" (Fantom-X)
        if let svd = directory, svd >= 2 {
            let base = svd - 2
            let directoryEnd = base + 2 + (Int(b[base]) << 8 | Int(b[base + 1]))
            var entry = svd + 14
            while entry + 16 <= min(directoryEnd, b.count) {
                let tag = SVQFile.text(b[entry ..< entry + 4])
                let offset = u32(entry + 8), length = u32(entry + 12)
                if base + offset + length <= b.count, length > 0 {
                    blocks[tag] = Array(b[(base + offset) ..< (base + offset + length)])
                }
                entry += 16
            }
        }
        dataBlocks = blocks
        switch variant {
        case .xp:
            performance = blocks["PRFa"].flatMap(XPPerformance.init(packed:))
            fantomPerformance = nil
        case .fantomX:
            performance = nil
            fantomPerformance = blocks["PRFa"].flatMap {
                FantomPerformance(performanceBlock: $0, patchBlock: blocks["PATa"], rhythmBlock: blocks["RHYa"],
                                  setupBlock: blocks["STPa"])
            }
        }
        if performance == nil && fantomPerformance == nil {
            warnings.append("This file has no saved Performance, so patch selections and mixer settings cannot be added.")
        }
        self.warnings = warnings
    }

    // MARK: Conveniences

    /// The tracks (0-15) that contain song events, in order.
    public var usedTracks: [Int] {
        Array(Set(events.filter { !$0.isConductorEvent }.map(\.track))).sorted()
    }

    /// The MIDI channels (0-15) played by the song.
    public var usedChannels: Set<UInt8> {
        Set(events.compactMap(\.channel))
    }

    /// The Output setting of a track (tracks outside 0-15, such as patterns, count as BOTH).
    public func output(ofTrack track: Int) -> SVQTrackOutput {
        trackOutputs.indices.contains(track) ? trackOutputs[track] : .both
    }

    /// The MIDI channels played on the instrument's own sound generator (excluding tracks set
    /// to send to MIDI Out only).
    public var internallyPlayedChannels: Set<UInt8> {
        Set(events.filter { output(ofTrack: $0.track).playsInternally }.compactMap(\.channel))
    }

    public var initialTempo: Int {
        for e in events where e.tick == 0 {
            if case .tempo(let t) = e.kind { return t }
        }
        return 500_000
    }

    public var initialTimeSignature: SVQTimeSignature {
        for e in events where e.tick == 0 {
            if case .timeSignature(let ts) = e.kind { return ts }
        }
        return .fourFour
    }

    public var initialBPM: Double { 60_000_000.0 / Double(initialTempo) }

    public var hasTempoChanges: Bool {
        events.contains { if case .tempo = $0.kind { return $0.tick > 0 } else { return false } }
    }

    public var noteCount: Int {
        events.reduce(0) { if case .note = $1.kind { return $0 + 1 } else { return $0 } }
    }

    public var containsSysEx: Bool {
        events.contains { if case .sysEx = $0.kind { return true } else { return false } }
    }

    /// Song duration in seconds, following the tempo map.
    public var duration: TimeInterval {
        var seconds = 0.0, lastTick = 0, tempo = 500_000
        for e in events {
            if case .tempo(let t) = e.kind {
                seconds += Double(e.tick - lastTick) * Double(tempo) / Double(resolution) / 1_000_000
                lastTick = e.tick
                tempo = t
            }
        }
        seconds += Double(max(0, songLength - lastTick)) * Double(tempo) / Double(resolution) / 1_000_000
        return seconds
    }

    // MARK: Helpers

    static func text<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        let chars = bytes.prefix { $0 != 0 }.map { byte -> Character in
            (0x20 ... 0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : " "
        }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }

    static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        var i = max(0, start)
        while i + needle.count <= haystack.count {
            if haystack[i] == needle[0], Array(haystack[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }
}
