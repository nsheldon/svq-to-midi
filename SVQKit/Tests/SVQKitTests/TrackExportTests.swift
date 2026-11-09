import XCTest
@testable import SVQKit

/// The exports behind dragging one phrase track, the Tempo or Beat track, or the song setup.
final class TrackExportTests: XCTestCase {
    private func song(_ name: String) throws -> SVQFile {
        let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)
        for folder in ["", "Fantom-X", "Fantom-S", "Fantom"] {
            if let url = fixtures?.appendingPathComponent(folder).appendingPathComponent(name),
               FileManager.default.fileExists(atPath: url.path) {
                return try SVQFile(contentsOf: url)
            }
        }
        throw XCTSkip("Missing fixture \(name)")
    }

    private func withoutTitle(_ track: [MIDIReader.Event]) -> [MIDIReader.Event] {
        track.filter { if case .meta(0x03, _) = $0.message { return false } else { return true } }
    }

    /// Each phrase track's file is the song's conductor track plus exactly that track as the
    /// whole-song conversion writes it, channel setup included.
    func testPhraseTrackFilesMatchTheSongConversion() throws {
        for name in ["XP-02.SVQ", "XP-01.SVQ", "FX-04.SVQ", "FX-03.SVQ"] {
            let svq = try song(name)
            let whole = try MIDIReader(data: SVQConverter.midiData(for: svq))
            XCTAssertEqual(whole.tracks.count, svq.usedTracks.count + 1, name)
            for (index, track) in svq.usedTracks.enumerated() {
                let file = try MIDIReader(data: SVQConverter.midiData(for: svq, track: track))
                XCTAssertEqual(file.tracks.count, 2, "\(name) track \(track + 1)")
                XCTAssertEqual(withoutTitle(file.tracks[0]), withoutTitle(whole.tracks[0]), "\(name) track \(track + 1)")
                // Channel setup lands on the first track that plays a channel, so a later track
                // sharing a channel gets it in its own file but not in the song.
                let own = file.tracks[1].filter { $0.tick >= 16 }
                XCTAssertEqual(own, whole.tracks[index + 1].filter { $0.tick >= 16 }, "\(name) track \(track + 1)")
            }
            // The SysEx option doesn't add the setup track to a single track's file.
            var options = SVQConversionOptions()
            options.addPerformanceSysEx = true
            let first = try MIDIReader(data: SVQConverter.midiData(for: svq, track: svq.usedTracks[0], options: options))
            XCTAssertEqual(first.tracks.count, 2, name)
        }
    }

    func testTempoAndBeatTrackFiles() throws {
        let svq = try song("FX-04.SVQ")
        let tempo = try MIDIReader(data: SVQConverter.midiData(for: svq, conductorTrack: .tempo))
        XCTAssertEqual(tempo.tracks.count, 1)
        let tempoMetas = tempo.tracks[0].compactMap { e -> UInt8? in if case .meta(let t, _) = e.message { return t } else { return nil } }
        XCTAssertEqual(tempoMetas.filter { $0 == 0x51 }.count, svq.tempoEvents.count)
        XCTAssertFalse(tempoMetas.contains(0x58) || tempoMetas.contains(0x59))

        let beat = try MIDIReader(data: SVQConverter.midiData(for: svq, conductorTrack: .beat))
        XCTAssertEqual(beat.tracks.count, 1)
        let beatMetas = beat.tracks[0].compactMap { e -> UInt8? in if case .meta(let t, _) = e.message { return t } else { return nil } }
        XCTAssertEqual(beatMetas.filter { $0 == 0x58 || $0 == 0x59 }.count, svq.beatEvents.count)
        XCTAssertFalse(beatMetas.contains(0x51))
        XCTAssertEqual(beat.tracks[0].last?.tick, svq.songLength)
    }

    func testSetupFileForXP() throws {
        let svq = try song("XP-01.SVQ")
        let file = try MIDIReader(data: XCTUnwrap(SVQConverter.setupMIDIData(for: svq)))
        let sysEx = file.tracks[1].compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } }
        XCTAssertEqual(sysEx, try XCTUnwrap(svq.xpSystem).sysExMessages() + svq.performance!.sysExMessages())
        // Then one track per channel the song plays: Bank Select, Program Change, mixer, at tick 0.
        let channelTracks = Array(file.tracks.dropFirst(2))
        XCTAssertEqual(channelTracks.count, svq.internallyPlayedChannels.count)
        for track in channelTracks {
            let messages = track.compactMap { e -> (Int, [UInt8])? in if case .channel(let b) = e.message { return (e.tick, b) } else { return nil } }
            XCTAssertEqual(messages.map(\.0), Array(repeating: 0, count: 7))
            XCTAssertEqual(messages.map { $0.1[0] & 0xF0 == 0xC0 ? -1 : Int($0.1[1]) }, [0, 32, -1, 7, 10, 91, 93])
            XCTAssertEqual(Set(messages.map { $0.1[0] & 0x0F }).count, 1)
        }
    }

    func testSetupFileForFantomX() throws {
        let svq = try song("FX-03.SVQ")
        let file = try MIDIReader(data: XCTUnwrap(SVQConverter.setupMIDIData(for: svq)))
        XCTAssertTrue(file.tracks[1].contains { if case .sysEx = $0.message { return true } else { return false } })
        // The saved sounds are sent, so their Parts get no Bank Select or Program Change.
        let channelMessages = file.tracks.dropFirst(2).flatMap { $0 }.compactMap { e -> [UInt8]? in
            if case .channel(let b) = e.message { return b } else { return nil }
        }
        XCTAssertFalse(channelMessages.isEmpty)
        XCTAssertFalse(channelMessages.contains { $0[0] & 0xF0 == 0xC0 })
    }

    func testPatternCallsAndSummaries() throws {
        let svq = try song("FX-04.SVQ")
        XCTAssertEqual(svq.patternCalls.count, 21)
        XCTAssertEqual(Set(svq.patternCalls.map(\.track)), [0, 2, 3, 9])
        XCTAssertTrue(svq.patternCalls.allSatisfy { $0.patternNumber != nil })
        let notes = svq.usedTracks.map { SVQEventSummary(events: svq.events(onTrack: $0)).notes }.reduce(0, +)
        XCTAssertEqual(notes, svq.noteCount)

        let xp1 = try song("XP-01.SVQ")
        XCTAssertEqual(xp1.measure(atTick: 0), 1)
        XCTAssertEqual(xp1.measure(atTick: xp1.initialTimeSignature.ticksPerMeasure(resolution: xp1.resolution)), 2)
        XCTAssertEqual(SVQEventSummary.noteName(60), "C4")
        XCTAssertEqual(keySignatureName(sharpsFlats: -3, minor: true), "C minor")
        XCTAssertEqual(keySignatureName(sharpsFlats: 2, minor: false), "D major")
    }

    func testPatternNamesNumbersAndRPS() throws {
        let fx4 = try song("FX-04.SVQ")
        XCTAssertEqual(fx4.patterns.map(\.name), ["SylkyBels", "808 A", "Seq A", "Bass A"])
        XCTAssertEqual(fx4.patterns.map(\.number), [1, 2, 3, 4])

        // Pattern numbers come from the IDs, which can skip: FF-FC, F6, F4, F3. The RPS setup
        // assigns exactly these numbers to seven keys.
        let fx6 = try song("FX-06.SVQ")
        XCTAssertEqual(fx6.patterns.map(\.number), [1, 2, 3, 4, 10, 12, 13])
        XCTAssertEqual(fx6.patterns.first?.name, "A1SoloPno")
        XCTAssertEqual(fx6.rpsAssignments.compactMap(\.patternNumber), [1, 2, 3, 4, 10, 12, 13])

        // XP: names, and an RPS setup with a STOP key, loops, one-shot fills and a Mute Group.
        let xp5 = try song("XP-05.SVQ")
        XCTAssertEqual(xp5.patterns.map(\.name), ["Beat", "Bass", "Guitar", "MusicBox", "Beat Fil01", "Beat Fil02"])
        XCTAssertEqual(xp5.rpsAssignments.map(\.summary),
                       ["C2 STOP", "D2 LOOP2 group 1", "E2 LOOP2", "F2 LOOP2", "G2 LOOP2", "A2 ONCE group 1", "B2 ONCE group 1"])
        XCTAssertEqual(xp5.rpsAssignments.map(\.patternNumber), [nil, 1, 2, 3, 4, 5, 6])

        // The probable mute mask: only XP song 6 (not a fixture) clears any bits, and only for its empty tracks.
        XCTAssertTrue(xp5.mutedTracks.isEmpty)

        // Songs without patterns have no names or RPS setup.
        XCTAssertTrue(try song("XP-01.SVQ").rpsAssignments.isEmpty)
    }

    /// The layout detector used for untested format versions picks each real file's own layout.
    func testLayoutDetectorPicksEachRealFilesLayout() throws {
        for name in ["XP-01.SVQ", "XP-02.SVQ", "XP-05.SVQ", "FX-01.SVQ", "FX-04.SVQ", "FX-06.SVQ"] {
            let svq = try song(name)
            let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            let path = url.appendingPathComponent(name.hasPrefix("FX") ? "Fantom-X/\(name)" : name)
            let b = [UInt8](try Data(contentsOf: path))
            let start = (Int(b[0]) << 8 | Int(b[1])) + 2
            let length = Int(b[start - 4]) << 24 | Int(b[start - 3]) << 16 | Int(b[start - 2]) << 8 | Int(b[start - 1])
            let xp = SVQFile.layoutFit(b, from: start, length: length, layout: SVQVariant.xp.recordLayout)
            let fantom = SVQFile.layoutFit(b, from: start, length: length, layout: SVQVariant.fantomX.recordLayout)
            XCTAssertEqual(xp > fantom ? SVQVariant.xp : .fantomX, svq.variant, name)
            XCTAssertGreaterThan(max(xp, fantom), 0.99, name)
        }
    }

    /// Roland's five Fantom-S demo songs (from the Fantom-S 1.09 system update): the Fantom-S writes
    /// the same "SV03" format and data blocks as the Fantom-X, and every part of them decodes.
    /// No Fantom-S MIDI export of them is available, so this checks consistency, not exact output.
    /// The Fantom-S's own sound list: five preset groups plus the S88's 8-Patch PR-F, 32 PRST kits,
    /// and names that differ from the Fantom-X's.
    func testFantomSFactoryNames() {
        func part(_ msb: Int, _ lsb: Int, _ program: Int, fantomS: Bool) -> FantomPart {
            var part = FantomPart(number: 1, isFantomS: fantomS)
            (part.bankMSB, part.bankLSB, part.program) = (msb, lsb, program)
            return part
        }
        XCTAssertEqual(FantomSPatchNames.presets.map(\.count), [128, 128, 128, 128, 128, 8])
        XCTAssertEqual(FantomSPatchNames.presetRhythmSets.count, 32)
        XCTAssertEqual(part(87, 64, 12, fantomS: true).displayName, "PR-A 013 FS Rhodes")
        XCTAssertEqual(part(87, 64, 12, fantomS: false).displayName, "PR-A 013 FS 70'EP")
        XCTAssertEqual(part(87, 68, 98, fantomS: true).name, "OutOf  sortz")
        XCTAssertEqual(part(87, 69, 5, fantomS: true).displayName, "PR-F 006 Rhodes mkI")
        XCTAssertNil(part(87, 69, 8, fantomS: true).name)
        XCTAssertEqual(part(87, 70, 0, fantomS: true).displayName, "Bank 87/70 001")
        XCTAssertEqual(part(87, 70, 0, fantomS: false).groupLabel, "PR-G")
        XCTAssertEqual(part(121, 3, 4, fantomS: true).displayName, "GM2 013 60's Rhodes")
        XCTAssertEqual(part(120, 0, 48, fantomS: true).name, "GM2 ORCHSTRA")
        XCTAssertNil(part(86, 64, 32, fantomS: true).name)
        XCTAssertNotNil(part(86, 64, 32, fantomS: false).name)
    }

    /// A Fantom-X song's audio tracks are saved beside it as "<name>.SVA", which is only reported.
    func testAudioTrackFileIsFoundBesideTheSong() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = folder.appendingPathComponent("SONG1.SVQ")
        try Data().write(to: song)
        XCTAssertNil(SVQFile.audioTrackFile(forSongAt: song))
        try Data("SThd".utf8).write(to: folder.appendingPathComponent("SONG1.SVA"))
        XCTAssertEqual(SVQFile.audioTrackFile(forSongAt: song)?.lastPathComponent, "SONG1.SVA")
        XCTAssertNil(SVQFile.audioTrackFile(forSongAt: folder.appendingPathComponent("SONG2.SVQ")))
    }

    func testFantomSDemoSongs() throws {
        for i in 0 ..< 5 {
            let name = "FS-DEMO-\(i).SVQ"
            let svq = try song(name)
            XCTAssertEqual(svq.formatVersion, 3, name)
            XCTAssertEqual(svq.variant, .fantomX, name)
            XCTAssertEqual(svq.model, "MC-80      1.2", name)
            XCTAssertEqual(svq.formatDescription, "Fantom-S/X", name)
            XCTAssertEqual(svq.resolution, 480, name)
            XCTAssertTrue(svq.unknownRecordTypes.isEmpty, name)
            XCTAssertTrue(svq.warnings.isEmpty, "\(name): \(svq.warnings)")
            XCTAssertGreaterThan(svq.noteCount, 500, name)

            let fantom = try XCTUnwrap(svq.fantomPerformance, name)
            XCTAssertTrue(fantom.name.hasPrefix("Demo "), name)
            // Every Part on a USER patch has its saved Patch, which converts to a full 9-message dump.
            for part in fantom.parts where part.receiveSwitch && part.bankMSB == 87 && part.bankLSB < 2 {
                let sound = try XCTUnwrap(fantom.savedSound(of: part), "\(name) Part \(part.number)")
                XCTAssertEqual(sound.name, part.storedName, "\(name) Part \(part.number)")
                XCTAssertEqual(sound.sysExMessages(to: FantomPatch.temporaryAddress(forPart: part.number)).count, 9)
            }
            XCTAssertTrue(fantom.isFantomS, name)
            XCTAssertEqual(svq.setup?.instrument, "Fantom-S", name)
            let performance = fantom.performanceSysExMessages()
            XCTAssertEqual(performance.count, 55, name)
            // The Fantom-S Controller section is 86 bytes (the Fantom-X's 88).
            let controller = try XCTUnwrap(performance.last, name)
            XCTAssertEqual(Array(controller[6 ..< 10]), [0x10, 0x00, 0x60, 0x00], name)
            XCTAssertEqual(controller.count, 12 + 86, name)
            // The Fantom-S Setup: its 47 bytes, from Sound Mode PERFORM and the selected USER
            // Performance (85/0/0-4).
            let setup = fantom.setupSysExMessages()
            XCTAssertEqual(setup.count, 1, name)
            let message = try XCTUnwrap(setup.first, name)
            XCTAssertEqual(message.count, 12 + 47, name)
            XCTAssertEqual(Array(message[6 ..< 13]), [0x01, 0x00, 0x00, 0x00, 0x01, 85, 0], name)
            XCTAssertLessThan(message[13], 5, name)
            XCTAssertTrue(message[10 ..< 57].allSatisfy { $0 < 0x80 }, name)

            // The whole song converts, with the setup SysEx, and reads back.
            var options = SVQConversionOptions()
            options.addPerformanceSysEx = true
            let midi = try MIDIReader(data: SVQConverter.midiData(for: svq, options: options))
            let notes = midi.allEvents.filter { if case .channel(let b) = $0.message { return b[0] & 0xF0 == 0x90 } else { return false } }
            XCTAssertEqual(notes.count, svq.noteCount, name)
        }
    }

    /// "SV02": the original Fantom's and the MC-80's format, from the songs inside the Fantom's
    /// version 1.20 firmware (its demo song, an MC-80 demo song and its blank new-song template).
    /// No MIDI export of them is available, so this checks consistency, not exact output.
    func testSV02Songs() throws {
        let fantom = try song("FA-DEMO-1.SVQ")
        XCTAssertEqual(fantom.formatVersion, 2)
        XCTAssertTrue(fantom.isKnownFormatVersion)
        XCTAssertEqual(fantom.variant, .fantomX)
        XCTAssertEqual(fantom.formatDescription, "Fantom/MC-80")
        XCTAssertEqual(fantom.resolution, 480)
        XCTAssertTrue(fantom.unknownRecordTypes.isEmpty)
        XCTAssertEqual(fantom.noteCount, 3352)
        XCTAssertEqual(fantom.usedTracks, Array(0 ..< 16))
        // Its sound settings are the original Fantom's ("NEXY"): saved in Multitimbre mode, so the
        // Multitimbre's 16 Parts play. Names come from the Fantom's Patch and Rhythm Set Lists.
        XCTAssertTrue(fantom.warnings.isEmpty, "\(fantom.warnings)")
        let fa76 = try XCTUnwrap(fantom.fa76Setup)
        XCTAssertEqual(fa76.soundMode, .multitimbre)
        XCTAssertEqual(fa76.multitimbreName, "FantomMedley")
        XCTAssertEqual(fa76.performanceName, "Fantasm")
        let setup = try XCTUnwrap(fantom.setup)
        XCTAssertEqual(setup.kind, "Multitimbre")
        XCTAssertEqual(setup.name, "FantomMedley")
        XCTAssertEqual(setup.parts.map(\.midiChannel), Array(0 ..< 16))
        XCTAssertEqual(setup.parts[0].displayName, "PR-B 043 Metal 5150")
        XCTAssertEqual(setup.parts[0].bankSelect(slotForBoard: { _ in 0 }), BankSelect(msb: 87, lsb: 72, program: 42))
        XCTAssertEqual(setup.parts[0].level, 55)
        XCTAssertEqual(setup.parts[9].displayName, "PRST 007 XV Rock Kit")
        XCTAssertTrue(setup.parts[9].isRhythmSet)
        XCTAssertEqual(setup.parts[15].displayName, "PRST 005 XV Pop Kit")
        // Converting adds each channel's Bank Select and Program Change.
        let converted = try MIDIReader(data: SVQConverter.midiData(for: fantom))
        let channel1 = converted.allEvents.compactMap { e -> [UInt8]? in
            if case .channel(let b) = e.message, e.tick == 0, b[0] & 0x0F == 0, b[0] & 0xF0 == 0xB0 || b[0] & 0xF0 == 0xC0 { return b }
            return nil
        }
        XCTAssertEqual(Array(channel1.prefix(3)), [[0xB0, 0, 87], [0xB0, 32, 72], [0xC0, 42]])

        // The SysEx setup: Sound Mode MULTI, then the Multitimbre into the temporary Multitimbre
        // (19 00 xx 00) section by section, each the size the Fantom's MIDI Implementation gives.
        // (Unverified against the instrument: no Fantom dump was available.)
        let dump = try XCTUnwrap(fa76.sysExMessages())
        XCTAssertEqual(dump.count, 1 + 6 + 16 + 16)
        // The Setup: Sound Mode MULTI, Multitimbre, Performance and Patch selections (85/0/0, 85/0/0,
        // 87/0/0), MFX/Chorus/Reverb on, no transpose or octave shift.
        XCTAssertEqual(Array(dump[0][0 ..< 10]), [0xF0, 0x41, 0x10, 0x00, 0x10, 0x12, 0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(Array(dump[0][10 ..< 25]), [2, 85, 0, 0, 85, 0, 0, 87, 0, 0, 1, 1, 1, 64, 64])
        XCTAssertTrue(dump.dropFirst().allSatisfy { Array($0[0 ..< 6]) == [0xF0, 0x41, 0x10, 0x00, 0x10, 0x12] && $0[6] == 0x19 && $0[7] == 0 })
        let sizes = Dictionary(dump.dropFirst().map { (Int($0[8]), $0.count - 12) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual([sizes[0x00], sizes[0x02], sizes[0x04], sizes[0x06], sizes[0x10], sizes[0x20]], [53, 145, 52, 83, 12, 49])
        XCTAssertEqual(String(decoding: dump[1][10 ..< 22], as: UTF8.self), "FantomMedley")
        let part1 = try XCTUnwrap(dump.first { $0[8] == 0x20 })
        XCTAssertEqual(Array(part1[10 ..< 19]), [0, 1, 1, 1, 87, 72, 42, 55, 64]) // ch 1, receive on, MIDI 1/2 on, MSB, LSB, PC, level, pan
        XCTAssertEqual(part1[10 + 0x21], 64) // Decay Time Offset: sent as 64
        XCTAssertEqual(fa76.sysExDescription, "Multitimbre \"FantomMedley\"")

        var withSysEx = SVQConversionOptions()
        withSysEx.addPerformanceSysEx = true
        let full = try MIDIReader(data: SVQConverter.midiData(for: fantom, options: withSysEx))
        let setupTrack = try XCTUnwrap(full.tracks.first { track in
            track.contains { if case .meta(0x03, let b) = $0.message { return String(decoding: b, as: UTF8.self) == SVQConverter.setupTrackName } else { return false } }
        })
        let sent = setupTrack.compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } }
        XCTAssertEqual(sent, dump)

        let mc80 = try song("MC80-DEMO-1.SVQ")
        XCTAssertEqual(mc80.formatVersion, 2)
        XCTAssertEqual(mc80.noteCount, 5834)
        XCTAssertTrue(mc80.unknownRecordTypes.isEmpty)
        XCTAssertTrue(mc80.dataBlocks.isEmpty) // the MC-80 saves no sound settings
        XCTAssertEqual(mc80.warnings.count, 1)

        let blank = try song("FA-NEW-SONG.SVQ")
        XCTAssertEqual(blank.formatVersion, 2)
        XCTAssertTrue(blank.events.isEmpty)
        XCTAssertEqual(blank.trackOutputs, Array(repeating: .both, count: 16))

        for svq in [fantom, mc80] {
            let midi = try MIDIReader(data: SVQConverter.midiData(for: svq))
            let notes = midi.allEvents.filter { if case .channel(let b) = $0.message { return b[0] & 0xF0 == 0x90 } else { return false } }
            XCTAssertEqual(notes.count, svq.noteCount)
        }
    }

    /// The original Fantom's factory names, from its MIDI Implementation's lists.
    func testFA76Names() {
        XCTAssertEqual(FA76Names.presets.map(\.count), [128, 128, 128, 128, 128])
        XCTAssertEqual(FA76Names.presets[0][0], "Grand XV")
        XCTAssertEqual(FA76Names.presets[1][71], "101  Bass") // two spaces, as the Fantom stores it
        XCTAssertEqual(FA76Names.presetRhythmSets.count, 16)
        XCTAssertEqual(FA76Names.presetRhythmSets.last, "OrchestraKit")
        XCTAssertEqual(FA76Names.gm2.count, 256)
        XCTAssertEqual(FA76Names.gm2[12].name, "Wurly") // the Fantom-X calls this GM2 slot "60's EP"
        XCTAssertEqual(FA76Names.gm2RhythmSets.count, 9)
        var part = FA76Part(number: 1)
        part.bankMSB = 87; part.bankLSB = 75; part.program = 127
        XCTAssertEqual(part.displayName, "PR-E 128 \(FA76Names.presets[4][127])")
        part.bankLSB = 0; part.program = 11
        XCTAssertEqual(part.displayName, "USER 012") // user Patches aren't saved with the song
        part.bankMSB = 121; part.bankLSB = 3; part.program = 4
        XCTAssertEqual(part.displayName, "GM2 013 Wurly")
        part.bankMSB = 120; part.bankLSB = 0; part.program = 56
        XCTAssertEqual(part.displayName, "GM2 009 GM2 SFX")
    }

    /// The XP's saved System settings. The Performance Number is checked against the owner's
    /// .SVD backups, where the user Performance in that slot has the song's Performance name.
    func testXPSystemSettings() throws {
        for (name, performanceNumber) in [("XP-02.SVQ", 8), ("XP-03.SVQ", 10), ("XP-04.SVQ", 11), ("XP-05.SVQ", 12)] {
            let system = try XCTUnwrap(try song(name).xpSystem, name)
            XCTAssertEqual(system.performanceNumber, performanceNumber, name)
            XCTAssertEqual(system.soundMode, 0, name) // PERFORM
            XCTAssertEqual(system.masterTune, 63, name) // 440 Hz
            XCTAssertFalse(system.scaleTuneSwitch, name)
            XCTAssertTrue(system.scaleTunes.allSatisfy { $0 == Array(repeating: 64, count: 12) }, name)
        }
        // One message, System Common 00-0A, while the scale tune switch is off.
        let messages = try XCTUnwrap(try song("XP-02.SVQ").xpSystem).sysExMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(Array(messages[0][0 ..< 9]), [0xF0, 0x41, 0x10, 0x6A, 0x12, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(messages[0].count - 11, 11)
        XCTAssertEqual(messages[0][10], 8)
        // With the switch on, the 17 scale tune sets follow (Parts 1-16 at 00 00 1n 00, Patch mode at 20 00).
        var tuned = try XCTUnwrap(try song("XP-02.SVQ").xpSystem)
        tuned.scaleTuneSwitch = true
        let withTunes = tuned.sysExMessages()
        XCTAssertEqual(withTunes.count, 18)
        XCTAssertEqual(withTunes.last.map { Array($0[5 ..< 9]) }, [0x00, 0x00, 0x20, 0x00])
    }

    /// The controller option: the XP's System preferences (00 0B-51, then 52-5F) after the
    /// sound-shaping System settings, only when asked for.
    func testXPControllerSetup() throws {
        let svq = try song("XP-02.SVQ")
        let system = try XCTUnwrap(svq.xpSystem)
        let controllers = system.controllerSysExMessages()
        XCTAssertEqual(controllers.count, 2)
        XCTAssertEqual(Array(controllers[0][5 ..< 9]), [0x00, 0x00, 0x00, 0x0B])
        XCTAssertEqual(controllers[0].count - 11, 0x51 - 0x0B + 1)
        let data = Array(controllers[0][9 ..< controllers[0].count - 2])
        XCTAssertEqual(Array(data[(0x14 - 0x0B) ... (0x1B - 0x0B)]), Array(repeating: 1, count: 8)) // every receive switch on
        XCTAssertEqual(Array(data[(0x3D - 0x0B) ... (0x3F - 0x0B)]), [1, 80, 0]) // Bank Select Group 1: on, USER
        XCTAssertEqual(Array(controllers[1][5 ..< 9]), [0x00, 0x00, 0x00, 0x52])
        XCTAssertEqual(controllers[1].count - 11, 14)
        XCTAssertEqual(controllers[1][9 + (0x5C - 0x52)], 50) // Arpeggio Shuffle Rate 50 (its minimum)

        var options = SVQConversionOptions()
        options.addPerformanceSysEx = true
        func setupSysEx() throws -> [[UInt8]] {
            try MIDIReader(data: SVQConverter.midiData(for: svq, options: options)).tracks[1]
                .compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } }
        }
        XCTAssertEqual(try setupSysEx(), system.sysExMessages() + svq.performance!.sysExMessages())
        options.addControllerSetup = true
        XCTAssertEqual(try setupSysEx(), system.sysExMessages() + controllers + svq.performance!.sysExMessages())

        // Settings saved by an earlier version, without the option, decode with it off.
        let old = try JSONDecoder().decode(SVQConversionOptions.self, from: Data(#"{"addPerformanceSysEx":true}"#.utf8))
        XCTAssertFalse(old.addControllerSetup)
    }
}
