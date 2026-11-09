import XCTest
@testable import SVQKit

final class FantomPatchTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Fantom-X") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    private func savedPatch(_ song: String, record: Int) throws -> FantomPatch {
        let svq = try SVQFile(data: try fixture(song))
        let block = try XCTUnwrap(svq.dataBlocks["PATa"])
        return try XCTUnwrap(FantomPatch(record: try XCTUnwrap(FantomPerformance.record(record, in: block))))
    }

    private func dump(_ file: String) throws -> [[UInt8]] {
        try MIDIReader(data: try fixture(file)).allEvents.compactMap { e in
            if case .sysEx(let bytes) = e.message { return bytes } else { return nil }
        }
    }

    /// The Patch saved in a song regenerates the Fantom-X's own dump of that Patch, byte for byte.
    func testSavedPatchesReproduceFantomXDumps() throws {
        let cases: [(song: String, record: Int, dump: String, name: String)] = [
            ("FX-04.SVQ", 0, "FX-PATCH-1.MID", "Sylky Bells"),
            ("FX-07.SVQ", 0, "FX-PATCH-2.MID", "DrkUltmtGrnd"),
        ]
        for c in cases {
            let patch = try savedPatch(c.song, record: c.record)
            XCTAssertEqual(patch.name, c.name)
            let expected = try dump(c.dump)
            XCTAssertEqual(expected.count, 9)
            // The dumps were sent to Patch mode's keyboard Patch (1F 00 00 00) with device ID 17.
            XCTAssertEqual(patch.sysExMessages(to: [0x1F, 0x00], deviceID: 0x10), expected, c.dump)
        }
    }

    func testRhythmSetDecoding() throws {
        // Fantom-X song 3, Part 10: PRST 006 "Brush Jz Kit"
        let svq = try SVQFile(data: try fixture("FX-03.SVQ"))
        let fantom = try XCTUnwrap(svq.fantomPerformance)
        let kit = try XCTUnwrap(fantom.savedSound(of: fantom.parts[9]))
        XCTAssertEqual(kit.kind, .rhythmSet)
        XCTAssertEqual(kit.name, "Brush Jz Kit")
        XCTAssertEqual(kit.name, fantom.parts[9].factoryName)
        XCTAssertEqual(kit.sections.count, 4 + 88)
        XCTAssertEqual(kit.sections.prefix(4).map(\.data.count), [18, 145, 84, 83])
        XCTAssert(kit.sections.dropFirst(4).allSatisfy { $0.data.count == 195 })
        // Every Rhythm Tone has a readable 12-character name.
        XCTAssert(kit.sections.dropFirst(4).allSatisfy { $0.data.prefix(12).allSatisfy { (0x20 ... 0x7E).contains($0) } })

        // Part 10's temporary Rhythm Set is at 13 30 00 00; key 108's tone at 13 31 3E 00.
        let messages = kit.sysExMessages(to: FantomPatch.temporaryAddress(forPart: 10))
        XCTAssertEqual(Array(messages[0][6 ..< 10]), [0x13, 0x30, 0x00, 0x00])
        XCTAssertEqual(Array(messages.last![6 ..< 10]), [0x13, 0x31, 0x3E, 0x00])
    }

    func testConversionReplicatesEverySavedSound() throws {
        let svq = try SVQFile(data: try fixture("FX-04.SVQ"))
        var options = SVQConversionOptions()
        options.addPerformanceSysEx = true
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq, options: options))
        let dumps = midi.allEvents.compactMap { e -> (Int, [UInt8])? in
            // Temporary Patch/Rhythm areas (11 00 00 00 - 14 7F, 1F xx); the song's own SysEx goes elsewhere.
            if case .sysEx(let b) = e.message, b[3] == 0x00, b[4] == 0x6B, (0x11 ... 0x14).contains(b[6]) || b[6] == 0x1F {
                return (e.tick, b)
            }
            return nil
        }
        // 15 Patches + Part 10's Rhythm Set + keyboard Patch + pad Rhythm Set
        let fantom = try XCTUnwrap(svq.fantomPerformance)
        let rhythmParts = fantom.parts.filter(\.isRhythmSet).count
        XCTAssertEqual(dumps.count, (16 - rhythmParts) * 9 + rhythmParts * 92 + 9 + 92)

        // Part 1's dump is the Fantom-X's own "Sylky Bells" dump, sent to Part 1's temporary Patch.
        let reference = try dump("FX-PATCH-1.MID")
        let part1 = dumps.filter { $0.1[6] == 0x11 && $0.1[7] == 0x00 }.map(\.1)
        XCTAssertEqual(part1.map { Array($0[8 ..< $0.count - 2]) }, reference.map { Array($0[8 ..< $0.count - 2]) })

        // The setup is a track of its own holding only the dumps, in order from tick 0.
        let setup = try XCTUnwrap(midi.tracks.first { track in
            track.contains { if case .meta(0x03, let b) = $0.message { return String(decoding: b, as: UTF8.self) == SVQConverter.setupTrackName } else { return false } }
        })
        let setupDumps = setup.compactMap { e -> Int? in if case .sysEx = e.message { return e.tick } else { return nil } }
        // First the Performance (to the temporary Performance, 10 00 xx 00), then the sounds. Without the
        // controller option, the 16 Zones and the Controller are left out: 38 of its 55 sections.
        let performance = fantom.performanceSysExMessages(includeControllers: false)
        XCTAssertEqual(performance.count, 38)
        XCTAssertEqual(fantom.performanceSysExMessages().count, 55)
        XCTAssertEqual(setupDumps.count, 1 + performance.count + dumps.count)
        let setupMessages = setup.compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } }
        // The Setup comes first: a Fantom-X song sends its whole Setup section (52 bytes) to 01 00 00 00.
        XCTAssertEqual(setupMessages[0], try XCTUnwrap(fantom.setupSysExMessages().first))
        XCTAssertEqual(Array(setupMessages[0][6 ..< 10]), [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(setupMessages[0].count - 12, 52)
        XCTAssertEqual(setupMessages[0][10], 1) // Sound Mode PERFORM
        XCTAssertEqual(Array(setupMessages.dropFirst().prefix(38)), performance)
        // With it, all 55.
        var withControllers = options
        withControllers.addControllerSetup = true
        let full = try MIDIReader(data: SVQConverter.midiData(for: svq, options: withControllers))
        let fullSetup = try XCTUnwrap(full.tracks.first { track in
            track.contains { if case .meta(0x03, let b) = $0.message { return String(decoding: b, as: UTF8.self) == SVQConverter.setupTrackName } else { return false } }
        })
        let fullSysEx = fullSetup.compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } }
        XCTAssertEqual(fullSysEx.count, setupMessages.count + 17)
        XCTAssertEqual(Array(fullSysEx.dropFirst().prefix(55)), fantom.performanceSysExMessages())
        XCTAssertTrue(performance.allSatisfy { $0[6] == 0x10 && $0[7] == 0x00 })
        XCTAssertEqual(setupDumps.min(), 0)
        XCTAssertEqual(dumps.map(\.0), dumps.map(\.0).sorted())
        XCTAssertFalse(setup.contains { if case .channel = $0.message { return true } else { return false } })

        // Parts whose sound is sent get no Program Change (it would replace the sound on later plays),
        // but keep their mixer settings; channel messages stay on their own channel's track.
        XCTAssertFalse(midi.allEvents.contains { isChannelSetup($0) && ($0.bytes[0] & 0xF0 == 0xC0 || $0.bytes[1] == 0) })
        XCTAssert(midi.allEvents.contains { isChannelSetup($0) && $0.bytes[0] & 0xF0 == 0xB0 && $0.bytes[1] == 7 })

        // Apart from that, the song is exactly what it is without the SysEx: same timing, no lead-in, same length.
        let plain = try MIDIReader(data: SVQConverter.midiData(for: svq))
        func songEvents(_ m: MIDIReader, skipping skipped: [MIDIReader.Event]) -> [MIDIReader.Event: Int] {
            var result: [MIDIReader.Event: Int] = [:]
            for track in m.tracks where track != skipped {
                for e in track where !isChannelSetup(e) {
                    if case .meta(0x03, _) = e.message { continue }
                    result[e, default: 0] += 1
                }
            }
            return result
        }
        XCTAssertEqual(songEvents(midi, skipping: setup), songEvents(plain, skipping: []))
        XCTAssertEqual(midi.tracks[0].last?.tick, max(svq.songLength, setupDumps.max()! + 1))
    }

    func testTemporaryPartAddresses() {
        XCTAssertEqual(FantomPatch.temporaryAddress(forPart: 1), [0x11, 0x00])
        XCTAssertEqual(FantomPatch.temporaryAddress(forPart: 4), [0x11, 0x60])
        XCTAssertEqual(FantomPatch.temporaryAddress(forPart: 5), [0x12, 0x00])
        XCTAssertEqual(FantomPatch.temporaryAddress(forPart: 16), [0x14, 0x60])
    }

    func testEmptyRecordsAreNotPatches() throws {
        // GM2 Parts have empty records in the patch block.
        let svq = try SVQFile(data: try fixture("FX-01.SVQ"))
        let block = try XCTUnwrap(svq.dataBlocks["PATa"])
        XCTAssertNil(FantomPatch(record: try XCTUnwrap(FantomPerformance.record(1, in: block))))
    }

    /// The Performance dump: every section has the manual's size, and Common starts with the name.
    /// (Unverified against a Fantom-X Performance dump; none was available.)
    func testPerformanceDumpSections() throws {
        let svq = try SVQFile(data: try fixture("FX-01.SVQ"))
        let messages = try XCTUnwrap(svq.fantomPerformance).performanceSysExMessages()
        let sizes = Dictionary(messages.map { (Int($0[8]), $0.count - 12) }, uniquingKeysWith: { a, _ in a })
        // Data bytes per section from the manual: Common 0x38, MFX 0x91, Chorus 0x54, Reverb 0x53,
        // MIDI 0x0C, Part 0x31, Zone 0x1B, Controller 0x58.
        XCTAssertEqual(sizes[0x00], 0x38)
        for mfx in [0x02, 0x08, 0x0A] { XCTAssertEqual(sizes[mfx], 0x91) }
        XCTAssertEqual(sizes[0x04], 0x54)
        XCTAssertEqual(sizes[0x06], 0x53)
        XCTAssertEqual(sizes[0x10], 0x0C)
        XCTAssertEqual(sizes[0x20], 0x31)
        XCTAssertEqual(sizes[0x50], 0x1B)
        XCTAssertEqual(sizes[0x60], 0x58)
        XCTAssertEqual(String(decoding: messages[0][10 ..< 22], as: UTF8.self), "GM2 Template")
        // Part 1's Part section repeats what the converter already reads: channel, switch, (2 reserved),
        // bank, program, level, pan.
        let part = try XCTUnwrap(svq.fantomPerformance?.parts.first)
        let part1 = try XCTUnwrap(messages.first { $0[8] == 0x20 })
        XCTAssertEqual(Array(part1[10 ..< 19]).map(Int.init),
                       [part.midiChannel, part.receiveSwitch ? 1 : 0, 0, 0, part.bankMSB, part.bankLSB, part.program, part.level, part.pan])
    }
}
