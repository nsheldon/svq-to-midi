import XCTest
@testable import SVQKit

/// Comparable, order-independent representation of musical events.
private struct Normalized: Hashable {
    var tick: Int
    var bytes: [UInt8]
}

private func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw XCTSkip("Missing fixture \(name)")
    }
    return try Data(contentsOf: url)
}

private func counts<S: Sequence>(_ items: S) -> [Normalized: Int] where S.Element == Normalized {
    items.reduce(into: [:]) { $0[$1, default: 0] += 1 }
}

/// Song events from the SVQ decoder, as MIDI bytes (note-ons, note-offs with release velocity, etc.).
private func normalizedSVQ(_ svq: SVQFile, offset: Int) -> [Normalized] {
    svq.events.flatMap { e -> [Normalized] in
        let t = e.tick + offset
        switch e.kind {
        case .note(let ch, let key, let vel, let rel, let gate):
            return [Normalized(tick: t, bytes: [0x90 | ch, key, vel]),
                    Normalized(tick: t + gate, bytes: [0x80 | ch, key, rel])]
        case .channelMessage(let bytes): return [Normalized(tick: t, bytes: bytes)]
        case .sysEx(let bytes): return [Normalized(tick: t, bytes: bytes)]
        default: return []
        }
    }
}

private func normalizedMIDI(_ midi: MIDIReader, excludingSysExBefore cutoff: Int = 0) -> [Normalized] {
    let scale = 96.0 / Double(midi.division)
    return midi.allEvents.compactMap { e in
        let t = Int((Double(e.tick) * scale).rounded())
        switch e.message {
        case .channel(let bytes):
            // Note-on with velocity 0 is a note-off.
            if bytes[0] & 0xF0 == 0x90, bytes[2] == 0 { return Normalized(tick: t, bytes: [0x80 | bytes[0] & 0x0F, bytes[1], 0x40]) }
            return Normalized(tick: t, bytes: bytes)
        case .sysEx(let bytes):
            return t < cutoff ? nil : Normalized(tick: t, bytes: bytes)
        case .meta: return nil
        }
    }
}

final class SVQDecodingTests: XCTestCase {
    /// SVQ files paired with the MIDI files the XP-80 itself exported from them. Some exports had
    /// measures inserted at the start (holding a Performance SysEx dump); `offset` accounts for that.
    let pairs: [(svq: String, midi: String, offset: Int)] = [
        ("XP-01.SVQ", "XP-01.mid", 1536),
        ("XP-02.SVQ", "XP-02.mid", 1920),
        ("XP-03.SVQ", "XP-03.mid", 0),
        ("XP-04.SVQ", "XP-04.mid", 0),
    ]

    func testSongEventsMatchXP80Exports() throws {
        for pair in pairs {
            let svq = try SVQFile(data: try fixture(pair.svq))
            let midi = try MIDIReader(data: try fixture(pair.midi))
            XCTAssertEqual(svq.resolution, 96)
            XCTAssert(svq.unknownRecordTypes.isEmpty, "\(pair.svq): \(svq.unknownRecordTypes)")
            let decoded = counts(normalizedSVQ(svq, offset: pair.offset))
            // The SysEx dumps added during the inserted measures are not part of the SVQ.
            let exported = counts(normalizedMIDI(midi, excludingSysExBefore: pair.offset))
            XCTAssertEqual(decoded.values.reduce(0, +), exported.values.reduce(0, +), pair.svq)
            XCTAssertEqual(decoded, exported, pair.svq)
        }
    }

    func testTempoMatchesXP80Export() throws {
        for pair in pairs {
            let svq = try SVQFile(data: try fixture(pair.svq))
            let midi = try MIDIReader(data: try fixture(pair.midi))
            let exportedTempo = midi.allEvents.compactMap { e -> Int? in
                if case .meta(0x51, let b) = e.message { return Int(b[0]) << 16 | Int(b[1]) << 8 | Int(b[2]) }
                return nil
            }.first
            XCTAssertEqual(svq.initialTempo, exportedTempo, pair.svq)
        }
    }

    func testHeaderAndLength() throws {
        let svq = try SVQFile(data: try fixture("XP-01.SVQ"))
        // The title is the one the XP-80 wrote into its own export of the song.
        XCTAssertFalse(svq.songName.isEmpty)
        XCTAssertEqual(svq.songName, try MIDIReader(data: try fixture("XP-01.mid")).sequenceName)
        XCTAssertEqual(svq.model, "XP-80 0105 1.7")
        XCTAssertEqual(svq.songLength, 22272 - 1536)
        XCTAssertEqual(svq.usedTracks, [0, 11])
        XCTAssertEqual(svq.initialTimeSignature, .fourFour)
        XCTAssertEqual(svq.initialBPM, 120, accuracy: 0.001)
        XCTAssertTrue(svq.patterns.isEmpty)
    }
}

final class PerformanceTests: XCTestCase {
    func testPerformanceSysExIsByteIdenticalToXP80Dump() throws {
        for (svqName, midiName) in [("XP-01.SVQ", "XP-01.mid"), ("XP-02.SVQ", "XP-02.mid")] {
            let svq = try SVQFile(data: try fixture(svqName))
            let midi = try MIDIReader(data: try fixture(midiName))
            let performance = try XCTUnwrap(svq.performance)
            let dumped = midi.allEvents.compactMap { e -> [UInt8]? in
                if case .sysEx(let b) = e.message, b.count > 9, b[5] == 0x01 { return b }
                return nil
            }
            XCTAssertEqual(dumped.count, 17, midiName)
            XCTAssertEqual(performance.sysExMessages(), dumped, midiName)
        }
    }

    func testPartsAndPatchMapping() throws {
        let xp1File = try SVQFile(data: try fixture("XP-01.SVQ"))
        let xp1 = try XCTUnwrap(xp1File.performance)
        XCTAssertEqual(xp1.name, xp1File.songName) // this song's Performance is named after it
        XCTAssertEqual(xp1.parts[0].patch.displayName, "USER 001")
        XCTAssertEqual(xp1.parts[1].patch.displayName, "SR-JV80-09 052 NewAge Flute")
        XCTAssertEqual(xp1.parts[3].patch.displayName, "GM 078 Shakuhachi")
        XCTAssertEqual(xp1.parts[9].patch.displayName, "PR-A 001 PopDrumSet 1")
        XCTAssertEqual(xp1.expansionBoards, [9])
        XCTAssert(xp1.parts[1].patch.bankSelect(expansionSlot: 1)! == (84, 2, 51))
        XCTAssertNil(xp1.parts[1].patch.bankSelect(expansionSlot: nil))
        XCTAssert(xp1.parts[3].patch.bankSelect(expansionSlot: nil)! == (81, 3, 77))
        XCTAssertEqual(xp1.parts[3].level, 127)
        XCTAssertEqual(xp1.parts[1].pan, 119)

        let xp2File = try SVQFile(data: try fixture("XP-02.SVQ"))

        let xp2 = try XCTUnwrap(xp2File.performance)
        XCTAssertEqual(xp2.parts[0].patch.displayName, "PR-B 065 Analog Seq")
        XCTAssert(xp2.parts[0].patch.bankSelect(expansionSlot: nil)! == (81, 1, 64))
        XCTAssertEqual(xp2.parts[2].patch.displayName, "PR-C 091 Dawn 2 Dusk")
        XCTAssertEqual(xp2.parts[4].patch.displayName, "PR-A 002 Bright Piano")
    }

    /// Expansion-board patch names match the temporary patch names in the XP-80's own SysEx dumps.
    func testExpansionBoardNamesMatchXP80Dumps() throws {
        var checked = 0
        for (svqName, midiName) in [("XP-01.SVQ", "XP-01.mid"), ("XP-03.SVQ", "XP-03.mid")] {
            let performanceFile = try SVQFile(data: try fixture(svqName))
            let performance = try XCTUnwrap(performanceFile.performance)
            let midi = try MIDIReader(data: try fixture(midiName))
            // Temporary Patch (or Rhythm Set) of Part n: address 02 0n 00 00, name in the first 12 data bytes.
            var dumpedNames: [Int: Set<String>] = [:]
            for case .sysEx(let b) in midi.allEvents.map(\.message) where b.count > 22 && b[5] == 0x02 && b[7] == 0 && b[8] == 0 {
                let name = String(decoding: b[9 ..< 21], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                dumpedNames[Int(b[6]) + 1, default: []].insert(name)
            }
            for part in performance.parts where part.patch.isExpansionBoard {
                let name = try XCTUnwrap(part.patch.name, "\(svqName) Part \(part.number)")
                XCTAssert(dumpedNames[part.number]?.contains(name) == true, "\(svqName) Part \(part.number): \(name)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 6)
        XCTAssertEqual(XPPatchReference(groupType: 2, groupID: 9, number: 66).displayName, "SR-JV80-09 067 SessionNylon")
        XCTAssertEqual(XPPatchReference(groupType: 2, groupID: 10, number: 2, isRhythmSet: true).name, "Natural SET")
        XCTAssertEqual(SRJV80Boards.titles[9], "Session")
    }

    /// Spot checks against names published independently of the lists the tables came from
    /// (a Super Sound Set review, synthmania.com demo pages, a Dance board sample credit).
    func testExpansionBoardNamesAgainstIndependentSources() {
        func name(_ board: Int, _ number: Int) -> String? {
            XPPatchReference(groupType: 2, groupID: board, number: number - 1).name
        }
        XCTAssertEqual([1, 8, 9, 115, 119, 127, 131].map { name(7, $0) },
                       ["Ac.Piano 1", "Dusty Piano", "NewAge Piano", "Mandolins", "ResonatorGt3", "Musette tun", "Master2"])
        XCTAssertEqual([1, 4, 154, 158, 180, 188, 200].map { name(15, $0) },
                       ["Siren Song", "Cobra", "PromisedLand", "Bubblin'Over", "Ghost Train", "Heat Seeker", "Heavy Hit 2"])
        XCTAssertEqual(name(6, 141), "Spooky")
        XCTAssertEqual(name(99, 12), "*Tnr/SopSax1")
        XCTAssertEqual(SRJV80Boards.boards.count, 22) // all 19 retail boards plus Experience (99), II (98) and III (97)
        XCTAssertEqual(name(97, 6), "118:ChinaPh1")
        XCTAssertEqual(name(97, 32), "*Full Orch.1")
    }

    func testExpansionPatchAbove128UsesOddLSB() {
        let patch = XPPatchReference(groupType: 2, groupID: 9, number: 233)
        XCTAssert(patch.bankSelect(expansionSlot: 2)! == (84, 5, 105))
    }
}

final class ConversionTests: XCTestCase {
    func testConvertedFileReproducesXP80Export() throws {
        let svq = try SVQFile(data: try fixture("XP-01.SVQ"))
        var options = SVQConversionOptions()
        options.addPerformanceSysEx = true
        options.leadInMeasures = 4
        let data = SVQConverter.midiData(for: svq, options: options)

        let ours = try MIDIReader(data: data)
        let reference = try MIDIReader(data: try fixture("XP-01.mid"))
        XCTAssertEqual(ours.format, 1)
        XCTAssertEqual(ours.division, 96)

        func notesAndBends(_ m: MIDIReader) -> [Normalized: Int] {
            counts(normalizedMIDI(m).filter { n in
                let status = n.bytes[0] & 0xF0
                return status == 0x80 || status == 0x90 || status == 0xD0 || status == 0xE0
                    || (status == 0xB0 && n.bytes[1] == 64)
            })
        }
        XCTAssertEqual(notesAndBends(ours), notesAndBends(reference))

        // The saved System settings, then all 17 Performance messages, in order, inside the lead-in.
        let sysEx = ours.allEvents.compactMap { e -> (Int, [UInt8])? in
            if case .sysEx(let b) = e.message { return (e.tick, b) } else { return nil }
        }
        XCTAssertEqual(sysEx.map(\.1), try XCTUnwrap(svq.xpSystem).sysExMessages() + svq.performance!.sysExMessages())
        XCTAssert(sysEx.allSatisfy { $0.0 < 1536 })

        // Patch selection for Part 4 (channel 4): GM 078 → Bank 81/3, Program 77.
        let ch4 = ours.allEvents.compactMap { e -> [UInt8]? in
            if case .channel(let b) = e.message, b[0] & 0x0F == 3, e.tick < 1536 { return b } else { return nil }
        }
        XCTAssertEqual(ch4, [])  // Channel 4 is not played in this song, so it gets no setup.
        let ch1 = ours.allEvents.compactMap { e -> [UInt8]? in
            if case .channel(let b) = e.message, b[0] & 0x0F == 0, e.tick < 1536 { return b } else { return nil }
        }
        XCTAssertEqual(ch1, [[0xB0, 0, 80], [0xB0, 32, 0], [0xC0, 0], [0xB0, 7, 127], [0xB0, 10, 64], [0xB0, 91, 127], [0xB0, 93, 127]])

        // Song length matches the XP-80 export (end of track at 22272).
        let end = ours.tracks[0].last!
        XCTAssertEqual(end.tick, 22272)
    }

    func testSetupTrackKeepsSongTimingForXP() throws {
        let svq = try SVQFile(data: try fixture("XP-01.SVQ"))
        var options = SVQConversionOptions()
        options.addPerformanceSysEx = true
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq, options: options))
        let plain = try MIDIReader(data: SVQConverter.midiData(for: svq))
        XCTAssertEqual(midi.tracks.count, plain.tracks.count + 1)
        let setup = midi.tracks[1]
        XCTAssertEqual(setup.compactMap { e -> [UInt8]? in if case .sysEx(let b) = e.message { return b } else { return nil } },
                       try XCTUnwrap(svq.xpSystem).sysExMessages() + svq.performance!.sysExMessages())
        // The XP-80 Performance messages stay 40 ms apart, and the setup track holds nothing else.
        let sysExTicks = setup.compactMap { e -> Int? in if case .sysEx = e.message { return e.tick } else { return nil } }
        let usPerTick = Double(svq.initialTempo) / Double(svq.resolution)
        for (a, b) in zip(sysExTicks, sysExTicks.dropFirst()) {
            XCTAssertGreaterThanOrEqual(Double(b - a) * usPerTick, 40_000 - usPerTick)
        }
        XCTAssertFalse(setup.contains { if case .channel = $0.message { return true } else { return false } })
        // The music tracks, with their own channel setup, are exactly as without the SysEx.
        XCTAssertEqual(Array(midi.tracks.dropFirst(2)), Array(plain.tracks.dropFirst()))
        XCTAssertEqual(midi.tracks[0].last?.tick, svq.songLength)
    }

    func testNoteOffsPrecedeNoteOnsAtSameTick() throws {
        let svq = try SVQFile(data: try fixture("XP-02.SVQ"))
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq))
        for track in midi.tracks {
            var active: [Int: Int] = [:]
            for e in track {
                guard case .channel(let b) = e.message else { continue }
                let key = Int(b[0] & 0x0F) << 8 | Int(b[1])
                if b[0] & 0xF0 == 0x90 { active[key, default: 0] += 1 }
                if b[0] & 0xF0 == 0x80 { active[key, default: 0] -= 1; XCTAssertGreaterThanOrEqual(active[key]!, 0) }
            }
            XCTAssert(active.values.allSatisfy { $0 == 0 })
        }
    }
}

final class SyntheticFileTests: XCTestCase {
    /// Builds a minimal SVQ: header, records, then nothing else.
    private func makeSVQ(name: String, records: [[UInt8]], signature: String = "SV00", resolution: Int = 96) -> Data {
        var header: [UInt8] = Array(signature.utf8) + MIDIFileWriter.bigEndian(resolution, bytes: 2)
            + [UInt8](repeating: 0, count: 8) + [0xFF]
        header += Array("XP-80 0105 1.7  ".utf8)
        header += [UInt8(name.utf8.count)] + Array(name.utf8) + [0x00]
        header += [UInt8](repeating: 0, count: 8)
        let body = records.flatMap { $0 }
        header += MIDIFileWriter.bigEndian(body.count, bytes: 4)
        return Data(MIDIFileWriter.bigEndian(header.count, bytes: 2) + header + body)
    }

    func testRestsTempoPatternsAndSysEx() throws {
        let data = makeSVQ(name: "Test", records: [
            [0x00, 0x83, 0, 0, 0x00, 0x02, 0x49, 0xF0], // 150000
            [0x00, 0x84, 0, 0, 0x00, 0x00, 0x04, 0xB0], // / 1200 → 500000 µs
            [0x00, 0x82, 0, 0, 3, 2, 0x18, 0],          // 3/4
            [0x00, 0x86, 0, 0, 0xFE, 1, 0, 0],          // 2 flats, minor
            [0xFF, 0x80, 0, 0, 0, 0, 0, 0],             // rest 255
            [0x45, 0x80, 0, 0, 0, 0, 0, 0],             // rest 69 → tick 324
            [0x10, 0x3C, 2, 1, 100, 64, 0x01, 0x00],    // C4 on ch 3, track 2, gate 256
            [0x00, 0x91, 0, 1, 0, 0, 0, 6],             // SysEx (6 bytes)
            [0x00, 0x92, 0, 1, 0xF0, 0x41, 0x10, 0x6A],
            [0x00, 0x92, 0, 1, 0x12, 0xF7, 0x00, 0x00],
            [0x00, 0x9E, 2, 1, 0xE2, 0x00, 0x40, 0],    // pitch bend center
            [0x20, 0x9C, 2, 1, 0xC2, 0x05, 0, 0],       // program change
            [0x00, 0x8E, 0, 1, 0, 0, 0, 0],             // end of track 2 at 372
            [0x00, 0x89, 0, 0xFF, 0, 0, 0, 0x18],       // pattern 1
            [0x30, 0x40, 9, 0xFF, 90, 0, 0, 0x18],      // note in pattern, ch 10
            [0x00, 0x8E, 0, 0xFF, 0, 0, 0, 0],
            [0x00, 0x8F, 0, 0, 0, 0, 0, 0],
        ])
        let svq = try SVQFile(data: data)
        XCTAssertEqual(svq.songName, "Test")
        XCTAssertEqual(svq.initialTempo, 500_000)
        XCTAssertEqual(svq.initialTimeSignature.displayString, "3/4")
        XCTAssertEqual(svq.songLength, 324 + 256)
        XCTAssertEqual(svq.events.count, 7)
        XCTAssertEqual(svq.events[3], SVQEvent(tick: 324, track: 1, kind: .note(channel: 2, key: 60, velocity: 100, releaseVelocity: 64, gate: 256)))
        XCTAssertEqual(svq.events[4].kind, .sysEx([0xF0, 0x41, 0x10, 0x6A, 0x12, 0xF7]))
        XCTAssertEqual(svq.events[5].kind, .channelMessage([0xE2, 0x00, 0x40]))
        XCTAssertEqual(svq.events[6], SVQEvent(tick: 340, track: 1, kind: .channelMessage([0xC2, 0x05])))
        XCTAssertEqual(svq.patterns.count, 1)
        XCTAssertEqual(svq.patterns[0].length, 0x30)
        XCTAssertEqual(svq.patterns[0].events, [SVQEvent(tick: 0, track: 0xFF, kind: .note(channel: 9, key: 0x40, velocity: 90, releaseVelocity: 0, gate: 0x18))])
        XCTAssertNil(svq.performance)

        // Lead-in uses the 3/4 meter.
        var options = SVQConversionOptions()
        options.leadInMeasures = 2
        let midi = try MIDIReader(data: SVQConverter.midiData(for: svq, options: options))
        let noteOn = midi.allEvents.first { if case .channel(let b) = $0.message { return b[0] == 0x92 } else { return false } }
        XCTAssertEqual(noteOn?.tick, 324 + 2 * 288)

        let pattern = try MIDIReader(data: SVQConverter.midiData(for: svq, pattern: svq.patterns[0]))
        XCTAssertEqual(pattern.tracks.count, 2)
    }

    func testXPPatternCallsAreExpanded() throws {
        // Track 1 calls pattern 0xFF at ticks 0 and 96; the second call is cut off by the end of the track.
        let data = makeSVQ(name: "Calls", records: [
            [0x00, 0x87, 0, 0, 0xFF, 0, 0, 0],          // call pattern FF on track 1
            [0x60, 0x3C, 0, 1, 100, 64, 0x00, 0x10],    // a direct note on track 2
            [0x30, 0x87, 0, 0, 0xFF, 0, 0, 0],          // tick 96: call again
            [0x00, 0x8E, 0, 0, 0, 0, 0, 0],             // tick 144: end of track 1
            [0x00, 0x8E, 0, 1, 0, 0, 0, 0],
            [0x00, 0x89, 0, 0xFF, 0, 0, 0, 0x20],       // pattern FF, 96 ticks long
            [0x40, 0x40, 3, 0xFF, 90, 10, 0, 0x08],     //   note at 0 on channel 4
            [0x20, 0x41, 3, 0xFF, 91, 11, 0, 0x08],     //   note at 64 on channel 4
            [0x00, 0x8E, 0, 0xFF, 0, 0, 0, 0],          //   end at 96
            [0x00, 0x8F, 0, 0, 0, 0, 0, 0],
        ])
        let svq = try SVQFile(data: data)
        XCTAssertEqual(svq.patternCallCount, 2)
        let track1 = svq.events.filter { $0.track == 0 }.map(\.tick)
        XCTAssertEqual(track1, [0, 64, 96]) // the second call's note at 96 + 64 is past the track end
        XCTAssertEqual(svq.events.first { $0.track == 0 }?.channel, 3)
        XCTAssertEqual(svq.usedTracks, [0, 1])
    }

    func testRejectsNonSVQData() {
        XCTAssertThrowsError(try SVQFile(data: Data(repeating: 0, count: 100))) { error in
            XCTAssertEqual(error as? SVQError, .notSVQ)
        }
        XCTAssertThrowsError(try SVQFile(data: Data([0, 1]))) { error in
            XCTAssertEqual(error as? SVQError, .tooShort)
        }
    }

    // MARK: Untested format versions

    /// A Fantom-X-layout record (12 bytes): u16 step, type, channel, track, 7 data bytes.
    private func fx(_ step: Int, _ type: UInt8, _ channel: UInt8, _ track: UInt8, _ data: [UInt8]) -> [UInt8] {
        MIDIFileWriter.bigEndian(step, bytes: 2) + [type, channel, track] + data + [UInt8](repeating: 0, count: 7 - data.count)
    }

    func testUnknownVersionInTheFantomXLayoutIsReadLikeOne() throws {
        let data = makeSVQ(name: "V2", records: [
            fx(0, 0x83, 0, 0, [0, 0, 0, 0x00, 0x02, 0x49, 0xF0]),       // 150000 (u32 in bytes 8-11)
            fx(0, 0x84, 0, 0, [0, 0, 0, 0x00, 0x00, 0x17, 0x70]),       // / 6000 ticks at 480 → 500000 µs
            fx(480, 0x3C, 1, 0, [100, 64, 0, 0x00, 0x00, 0x01, 0xE0]),     // tick 0: C4, ch 2, gate 480
            fx(0, 0x8E, 0, 0, []),                                          // tick 480: end of track 1
            fx(0, 0x8F, 0, 0, []),
        ], signature: "SV04", resolution: 480)
        let svq = try SVQFile(data: data)
        XCTAssertEqual(svq.formatVersion, 4)
        XCTAssertFalse(svq.isKnownFormatVersion)
        XCTAssertEqual(svq.variant, .fantomX)
        XCTAssertEqual(svq.formatDescription, "SVQ version 4 (untested)")
        XCTAssertTrue(svq.warnings.contains { $0.contains("\"SV04\"") && $0.contains("Fantom-S/X") })
        XCTAssertEqual(svq.initialTempo, 500_000)
        XCTAssertEqual(svq.events.last, SVQEvent(tick: 0, track: 0, kind: .note(channel: 1, key: 60, velocity: 100, releaseVelocity: 64, gate: 480)))
        XCTAssertEqual(svq.songLength, 480)
    }

    func testUnknownVersionInTheXPLayoutIsReadLikeOne() throws {
        let data = makeSVQ(name: "V2", records: [
            [0x00, 0x83, 0, 0, 0x00, 0x02, 0x49, 0xF0],
            [0x00, 0x84, 0, 0, 0x00, 0x00, 0x04, 0xB0],
            [0x60, 0x3C, 2, 1, 100, 64, 0x00, 0x60],
            [0x00, 0x8E, 0, 1, 0, 0, 0, 0],
            [0x00, 0x8F, 0, 0, 0, 0, 0, 0],
        ], signature: "SV04")
        let svq = try SVQFile(data: data)
        XCTAssertEqual(svq.variant, .xp)
        XCTAssertEqual(svq.formatVersion, 4)
        XCTAssertEqual(svq.events.last, SVQEvent(tick: 0, track: 1, kind: .note(channel: 2, key: 60, velocity: 100, releaseVelocity: 64, gate: 96)))
    }

    func testTestedVersionsAreReadAsBefore() throws {
        let svq = try SVQFile(data: makeSVQ(name: "V0", records: [[0x00, 0x8F, 0, 0, 0, 0, 0, 0]]))
        XCTAssertEqual(svq.formatVersion, 0)
        XCTAssertTrue(svq.isKnownFormatVersion)
        XCTAssertEqual(svq.formatDescription, "XP-50/60/80")
        XCTAssertFalse(svq.warnings.contains { $0.contains("hasn't been seen") })
    }
}
