import XCTest
@testable import SVQKit

/// The exports behind dragging one phrase track, the Tempo or Beat track, or the song setup.
final class TrackExportTests: XCTestCase {
    private func song(_ name: String) throws -> SVQFile {
        let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)
        for folder in ["", "Fantom-X"] {
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
        XCTAssertEqual(sysEx, svq.performance!.sysExMessages())
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
}
