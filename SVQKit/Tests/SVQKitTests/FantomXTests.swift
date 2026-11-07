import XCTest
@testable import SVQKit

extension MIDIReader.Event {
    var bytes: [UInt8] {
        switch message {
        case .channel(let b), .sysEx(let b): return b
        case .meta(let type, let b): return [0xFF, type] + b
        }
    }
}

/// A Bank Select, Program Change or Part mixer message at the start of a track (the converter's channel setup).
func isChannelSetup(_ e: MIDIReader.Event) -> Bool {
    guard case .channel(let b) = e.message, e.tick < 16 else { return false }
    return b[0] & 0xF0 == 0xC0 || (b[0] & 0xF0 == 0xB0 && [0, 32, 7, 10, 91, 93].contains(b[1]))
}

private func fantomFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Fantom-X") else {
        throw XCTSkip("Missing fixture \(name)")
    }
    return try Data(contentsOf: url)
}

private struct Event: Hashable {
    var tick: Int
    var bytes: [UInt8]
}

private func counts(_ events: [Event]) -> [Event: Int] {
    events.reduce(into: [:]) { $0[$1, default: 0] += 1 }
}

private func decoded(_ svq: SVQFile) -> [Event] {
    svq.events.flatMap { e -> [Event] in
        switch e.kind {
        case .note(let ch, let key, let vel, let rel, let gate):
            return [Event(tick: e.tick, bytes: [0x90 | ch, key, vel]), Event(tick: e.tick + gate, bytes: [0x80 | ch, key, rel])]
        case .channelMessage(let bytes), .sysEx(let bytes):
            return [Event(tick: e.tick, bytes: bytes)]
        default:
            return []
        }
    }
}

private func exported(_ midi: MIDIReader) -> [Event] {
    midi.allEvents.compactMap { e in
        switch e.message {
        case .channel(let b): return Event(tick: e.tick, bytes: b)
        case .sysEx(let b): return Event(tick: e.tick, bytes: b)
        case .meta: return nil
        }
    }
}

final class FantomXDecodingTests: XCTestCase {
    func testEventsMatchFantomXExports() throws {
        for name in ["FX-01", "FX-02", "FX-03"] {
            let svq = try SVQFile(data: try fantomFixture("\(name).SVQ"))
            let midi = try MIDIReader(data: try fantomFixture("\(name).MID"))
            XCTAssertEqual(svq.variant, .fantomX)
            XCTAssertEqual(svq.resolution, 480)
            XCTAssertEqual(midi.division, 480)
            XCTAssert(svq.unknownRecordTypes.isEmpty, "\(name): \(svq.unknownRecordTypes)")
            XCTAssert(svq.warnings.isEmpty, "\(name): \(svq.warnings)")
            let ours = counts(decoded(svq)), theirs = counts(exported(midi))
            XCTAssertEqual(ours.values.reduce(0, +), theirs.values.reduce(0, +), name)
            XCTAssertEqual(ours, theirs, name)
        }
    }

    func testHeaderTempoAndMeter() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-03.SVQ"))
        // The title is the one the Fantom-X wrote into its own export of the song.
        XCTAssertFalse(svq.songName.isEmpty)
        XCTAssertEqual(svq.songName, try MIDIReader(data: try fantomFixture("FX-03.MID")).sequenceName)
        XCTAssertEqual(svq.model, "MC-80      1.1.1")
        XCTAssertEqual(svq.initialTempo, 500_000)
        XCTAssertEqual(svq.initialTimeSignature.displayString, "3/4")
        XCTAssertEqual(svq.songLength, 192_960)

        // FX-02's tempo was raised to 145 BPM before exporting, but the song was saved at 125 BPM.
        XCTAssertEqual(try SVQFile(data: try fantomFixture("FX-02.SVQ")).initialTempo, 480_000)
    }

    func testPerformancePartsAndNames() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-03.SVQ"))
        let setup = try XCTUnwrap(svq.setup)
        XCTAssertEqual(setup.instrument, "Fantom-X")
        XCTAssertEqual(setup.name, "Seq:Template")
        let p1 = setup.parts[0]
        XCTAssertEqual(p1.displayName, "PR-H 119 Nylon Harp")
        XCTAssertEqual(p1.bankSelect(slotForBoard: { _ in 0 }), BankSelect(msb: 87, lsb: 71, program: 118))
        XCTAssertEqual([p1.level, p1.pan, p1.reverbSendLevel, p1.chorusSendLevel], [124, 45, 91, 86])
        XCTAssertEqual(setup.parts[9].displayName, "PRST 006 Brush Jz Kit")
        XCTAssertTrue(setup.parts[9].isRhythmSet)
        XCTAssertEqual(setup.parts.map(\.midiChannel), Array(0 ..< 16))

        let fx4File = try SVQFile(data: try fantomFixture("FX-04.SVQ"))

        let fx4 = try XCTUnwrap(fx4File.setup)
        XCTAssertEqual(fx4.parts[0].displayName, "USER 253 Sylky Bells")
        XCTAssertEqual(fx4.parts[0].bankSelect(slotForBoard: { _ in 0 }), BankSelect(msb: 87, lsb: 1, program: 124))

        // GM2 sounds aren't stored with the song; their names and numbers come from the Sound List.
        let fx1File = try SVQFile(data: try fantomFixture("FX-01.SVQ"))
        let fx1 = try XCTUnwrap(fx1File.setup)
        XCTAssertEqual(fx1.name, "GM2 Template")
        XCTAssertEqual(fx1.parts[0].displayName, "GM2 167 Wire Lead") // MSB 121, LSB 1, PC 85
        XCTAssertEqual(fx1.parts[1].displayName, "GM2 001 Piano 1")
        XCTAssertEqual(fx1.parts[9].displayName, "GM2 001 GM2 STANDARD")
    }

    func testPatchModeSongUsesKeyboardAndPadSounds() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-05.SVQ"))
        XCTAssertEqual(svq.fantomPerformance?.soundMode, .patch)
        let setup = try XCTUnwrap(svq.setup)
        XCTAssertEqual(setup.parts.map(\.label), ["Kbd", "Pad"])
        XCTAssertEqual(setup.parts[0].displayName, "USER 001 UltimatGrnd+")
        XCTAssertEqual(setup.parts[0].midiChannel, 0)
        XCTAssertEqual(setup.parts[1].displayName, "USER 001 StudioX Kit1")
        XCTAssertEqual(setup.parts[1].midiChannel, 9)
        XCTAssertNotNil(setup.note)

        // Only Bank Select and Program Change: Patch mode has no part mixer.
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq))
        let setupMessages = midi.allEvents.filter(isChannelSetup)
        XCTAssertEqual(Array(setupMessages.prefix(3)).map(\.tick), [0, 0, 0])
        XCTAssertEqual(Array(setupMessages.prefix(3)).map(\.bytes), [[0xB0, 0, 87], [0xB0, 32, 0], [0xC0, 0]])
        XCTAssertFalse(setupMessages.contains { $0.bytes == [0xB0, 7, 100] })
    }

    func testPerformanceModeSongKeepsPatchModeSoundsAside() throws {
        let performanceFile = try SVQFile(data: try fantomFixture("FX-03.SVQ"))
        let performance = try XCTUnwrap(performanceFile.fantomPerformance)
        XCTAssertEqual(performance.soundMode, .performance)
        XCTAssertEqual(performance.keyboardPart?.displayName, "USER 001 UltimatGrnd+")
        XCTAssertEqual(performance.padPart?.displayName, "PRST 019 House Kit")
        XCTAssertEqual(performance.padPart?.storedName, performance.padPart?.factoryName)
    }

    func testTrackOutputsAndExternalTracks() throws {
        // Fantom-X song 6: track 3 played a V-Synth through MIDI Out; tracks 1, 2, 5 and 10 were
        // internal only; track 16 (a V-Synth SysEx setup dump) was switched off.
        let svq = try SVQFile(data: try fantomFixture("FX-06.SVQ"))
        XCTAssertEqual(Array(svq.trackOutputs.prefix(5)), [.internal, .internal, .midi, .both, .internal])
        XCTAssertEqual(svq.trackOutputs[15], .off)
        XCTAssertEqual(svq.usedChannels, [0, 1, 2, 4, 9])
        XCTAssertEqual(svq.internallyPlayedChannels, [0, 1, 4, 9])
        XCTAssertEqual(svq.setup?.parts[0].displayName, "PR-I 002 Punch Piano") // Audio Track Expansion bank

        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq))
        let names = midi.tracks.compactMap { track in
            track.compactMap { e -> String? in
                if case .meta(0x03, let b) = e.message { return String(decoding: b, as: UTF8.self) } else { return nil }
            }.first
        }
        XCTAssert(names.contains("Track 3: MIDI Out"), "\(names)")
        XCTAssert(names.contains("Track 16: Off"), "\(names)")
        XCTAssert(names.contains("Track 1: PR-I 002 Punch Piano"), "\(names)")
        // No Fantom-X patch selection is sent on the V-Synth's channel.
        let channel3Setup = midi.allEvents.contains { e in
            if case .channel(let b) = e.message { return b == [0xB0, 0, 87] && b[0] & 0x0F == 2 } else { return false }
        }
        XCTAssertFalse(channel3Setup)
        let channel1Bank = midi.allEvents.compactMap { e -> [UInt8]? in
            if case .channel(let b) = e.message, b[0] == 0xB0, b[1] == 0 || b[1] == 32 { return b } else { return nil }
        }.prefix(2)
        XCTAssertEqual(Array(channel1Bank), [[0xB0, 0, 87], [0xB0, 32, 72]])
    }

    func testOffTracksCanBeLeftOut() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-06.SVQ"))
        func trackNames(_ options: SVQConversionOptions) throws -> [String] {
            try MIDIReader(data: SVQConverter.midiData(for: svq, options: options)).tracks.compactMap { track in
                track.compactMap { e -> String? in
                    if case .meta(0x03, let b) = e.message { return String(decoding: b, as: UTF8.self) } else { return nil }
                }.first
            }
        }
        var options = SVQConversionOptions()
        XCTAssertTrue(options.includeOffTracks)
        XCTAssert(try trackNames(options).contains("Track 16: Off"))

        options.includeOffTracks = false
        let names = try trackNames(options)
        XCTAssertFalse(names.contains("Track 16: Off"))
        XCTAssert(names.contains("Track 3: MIDI Out"))
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq, options: options))
        XCTAssertFalse(midi.allEvents.contains { if case .sysEx(let b) = $0.message { return b[4] == 0x53 } else { return false } },
                       "the V-Synth SysEx on the Off track should be gone")
        XCTAssertEqual(midi.tracks[0].last?.tick, svq.songLength) // song length is unchanged
    }

    func testOptionsSavedBeforeANewSettingStillDecode() throws {
        var saved = SVQConversionOptions()
        saved.addPatchSelection = false
        saved.leadInMeasures = 2
        saved.expansionSlots = [9: 1]
        saved.includeOffTracks = false
        // What an earlier version stored: the same JSON without the newer key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json["includeOffTracks"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        let options = try JSONDecoder().decode(SVQConversionOptions.self, from: old)
        XCTAssertFalse(options.addPatchSelection)
        XCTAssertEqual(options.leadInMeasures, 2)
        XCTAssertEqual(options.expansionSlots, [9: 1])
        XCTAssertTrue(options.includeOffTracks)
    }

    func testXPFilesDefaultToBothOutputs() throws {
        guard let url = Bundle.module.url(forResource: "XP-01.SVQ", withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture")
        }
        let svq = try SVQFile(contentsOf: url)
        XCTAssertEqual(svq.trackOutputs, Array(repeating: .both, count: 16))
    }

    func testStoredNamesMatchSoundList() throws {
        var checked = 0
        for name in ["FX-01", "FX-02", "FX-03", "FX-04", "FX-05", "FX-06"] {
            let file = try SVQFile(data: try fantomFixture("\(name).SVQ"))
            let performance = try XCTUnwrap(file.fantomPerformance)
            for part in performance.parts {
                guard let factory = part.factoryName, let stored = part.storedName else { continue }
                XCTAssertEqual(stored, factory, "\(name) Part \(part.number)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 40)
    }

    func testSoundListTables() {
        XCTAssertEqual(FantomPatchNames.presets.count, 9)
        XCTAssert(FantomPatchNames.presets.allSatisfy { $0.count == 128 })
        XCTAssertEqual(FantomPatchNames.gm2.count, 256)
        XCTAssertEqual(Set(FantomPatchNames.gm2.map { "\($0.lsb)/\($0.program)" }).count, 256)
        XCTAssertEqual(FantomPatchNames.presets[5][8], "UltimatGrand") // PR-F 009
        XCTAssertEqual(FantomPatchNames.presetRhythmSets.count, 40)
    }

    func testPatternCallsAreExpanded() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-04.SVQ"))
        XCTAssertEqual(svq.patterns.count, 4)
        XCTAssertEqual(svq.patternCallCount, 21)
        XCTAssertEqual(svq.usedTracks, [0, 1, 2, 3, 9])

        // Track 1 calls pattern 0xFF every 7680 ticks (4 measures).
        let pattern = try XCTUnwrap(svq.patterns.first { $0.identifier == 0xFF })
        XCTAssertEqual(pattern.length, 7680)
        let expected = pattern.events.filter { !$0.isConductorEvent }.map { e -> SVQEvent in
            var copy = e
            copy.tick += 7680
            copy.track = 0
            return copy
        }
        let actual = svq.events.filter { $0.track == 0 && (7680 ..< 15360).contains($0.tick) }
        XCTAssertFalse(actual.isEmpty)
        XCTAssertEqual(actual, expected)

        // Five calls on each of four tracks, plus track 1's single call at bar 1.
        let direct = svq.events.filter { // notes recorded directly on track 2
            if case .note = $0.kind { return $0.track == 1 } else { return false }
        }.count
        let patternNotes = Dictionary(uniqueKeysWithValues: svq.patterns.map { p in
            (p.identifier, p.events.filter { if case .note = $0.kind { return true } else { return false } }.count)
        })
        let calls: [UInt8: Int] = [0xFF: 6, 0xFE: 5, 0xFD: 5, 0xFC: 5]
        XCTAssertEqual(svq.noteCount, direct + calls.reduce(0) { $0 + patternNotes[$1.key]! * $1.value })
    }

    func testConversionAddsFantomXPatchSelection() throws {
        let svq = try SVQFile(data: try fantomFixture("FX-03.SVQ"))
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq))
        XCTAssertEqual(midi.division, 480)

        // The setup is at tick 0 in order (Bank Select, Program Change, mixer), ahead of the song's
        // own tick-0 events. The song sets channel 1's level and pan itself at tick 0, so the setup
        // leaves those to the song.
        let channel1Setup = midi.allEvents.filter { isChannelSetup($0) && $0.bytes[0] & 0x0F == 0 }
        XCTAssertEqual(channel1Setup.map(\.bytes),
                       [[0xB0, 0, 87], [0xB0, 32, 71], [0xC0, 118], [0xB0, 91, 91], [0xB0, 93, 86], [0xB0, 7, 124], [0xB0, 10, 45]])
        XCTAssertEqual(channel1Setup.map(\.tick), [0, 0, 0, 0, 0, 0, 0])
        // Nothing at tick 0 on that track comes before the Program Change.
        let track1 = try XCTUnwrap(midi.tracks.first { $0.contains { $0.bytes == [0xC0, 118] } })
        let pc = try XCTUnwrap(track1.firstIndex { $0.bytes == [0xC0, 118] })
        XCTAssertFalse(track1[..<pc].contains { $0.bytes.first.map { $0 & 0xF0 == 0x90 } ?? false })

        // The song's own events are untouched.
        // Seven channels are played, each gets 7 setup messages, except the level and pan that the
        // song sets itself at the start on every channel.
        let setupEvents = 7 * 7 - 7 * 2
        XCTAssertEqual(exported(midi).count, decoded(svq).count + setupEvents)

        // Without the SysEx option there are no dumps.
        XCTAssertFalse(midi.allEvents.contains { if case .sysEx = $0.message { return true } else { return false } })
    }
}
