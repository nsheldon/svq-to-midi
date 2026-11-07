import Foundation

/// What a phrase track or pattern contains, for showing it in a list.
public struct SVQEventSummary: Equatable, Sendable {
    public var notes = 0
    public var controllers = 0
    public var programChanges = 0
    public var pitchBends = 0
    /// Channel and polyphonic aftertouch.
    public var aftertouch = 0
    public var sysEx = 0
    public var tempoChanges = 0
    public var meterChanges = 0
    public var keyChanges = 0
    /// MIDI channels (0-15) of the notes and channel messages.
    public var channels: Set<UInt8> = []
    public var lowestKey: UInt8?
    public var highestKey: UInt8?
    /// The first event's tick, and the tick after the last one (a note ends after its gate).
    public var firstTick: Int?
    public var endTick: Int?

    public init(events: [SVQEvent]) {
        for event in events {
            var end = event.tick + 1
            switch event.kind {
            case .note(let channel, let key, _, _, let gate):
                notes += 1
                channels.insert(channel)
                lowestKey = min(lowestKey ?? key, key)
                highestKey = max(highestKey ?? key, key)
                end = event.tick + max(1, gate)
            case .channelMessage(let bytes):
                if let status = bytes.first { channels.insert(status & 0x0F) }
                switch (bytes.first ?? 0) & 0xF0 {
                case 0xB0: controllers += 1
                case 0xC0: programChanges += 1
                case 0xE0: pitchBends += 1
                case 0xA0, 0xD0: aftertouch += 1
                default: break
                }
            case .sysEx: sysEx += 1
            case .tempo: tempoChanges += 1
            case .timeSignature: meterChanges += 1
            case .keySignature: keyChanges += 1
            }
            firstTick = min(firstTick ?? event.tick, event.tick)
            endTick = max(endTick ?? end, end)
        }
    }

    public var isEmpty: Bool { firstTick == nil }

    /// The events other than notes, as text such as "12 controllers, 1 program change".
    public var otherEventsText: String {
        func count(_ n: Int, _ noun: String) -> String? {
            n == 0 ? nil : "\(n) \(noun)\(n == 1 ? "" : "s")"
        }
        return [count(controllers, "controller"), count(programChanges, "program change"),
                count(pitchBends, "pitch bend"), count(aftertouch, "aftertouch"), count(sysEx, "SysEx message")]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// The same, abbreviated for a narrow column: "12 CC, 1 PC, 40 bend, 3 AT, 1 SysEx".
    public var compactOtherEventsText: String {
        [(controllers, "CC"), (programChanges, "PC"), (pitchBends, "bend"), (aftertouch, "AT"), (sysEx, "SysEx")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    /// The note range as text such as "C2–G5" (middle C = C4).
    public var keyRangeText: String? {
        guard let low = lowestKey, let high = highestKey else { return nil }
        return low == high ? SVQEventSummary.noteName(low) : "\(SVQEventSummary.noteName(low))–\(SVQEventSummary.noteName(high))"
    }

    public static func noteName(_ key: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[Int(key) % 12])\(Int(key) / 12 - 1)"
    }
}

extension SVQFile {
    /// The song events of one phrase track (0-15), pattern calls already expanded.
    public func events(onTrack track: Int) -> [SVQEvent] {
        events.filter { !$0.isConductorEvent && $0.track == track }
    }

    /// The Tempo track: every tempo event.
    public var tempoEvents: [SVQEvent] {
        events.filter { if case .tempo = $0.kind { return true } else { return false } }
    }

    /// The Beat track: every time signature and key signature event.
    public var beatEvents: [SVQEvent] {
        events.filter {
            switch $0.kind {
            case .timeSignature, .keySignature: return true
            default: return false
            }
        }
    }

    /// The 1-based measure that contains `tick`, following the song's meter changes.
    public func measure(atTick tick: Int) -> Int {
        var measure = 1, start = 0
        var length = SVQTimeSignature.fourFour.ticksPerMeasure(resolution: resolution)
        for event in events {
            guard case .timeSignature(let ts) = event.kind else { continue }
            if event.tick > tick { break }
            // A meter change takes effect at the start of the measure it falls in (or at once if
            // it falls on a measure boundary, which is where the instruments put them).
            measure += (event.tick - start) / length
            start += (event.tick - start) / length * length
            length = ts.ticksPerMeasure(resolution: resolution)
        }
        return measure + max(0, tick - start) / length
    }

    /// The measures from `first` to the measure holding `end` (exclusive), as "1–24" or "5".
    public func measureRangeText(from first: Int, to end: Int) -> String {
        let a = measure(atTick: first), b = measure(atTick: max(first, end - 1))
        return a == b ? "\(a)" : "\(a)–\(b)"
    }
}

/// A key signature's name, such as "C major" or "F# minor".
public func keySignatureName(sharpsFlats: Int8, minor: Bool) -> String {
    let majors = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"]
    let minors = ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"]
    let index = Int(max(-7, min(7, sharpsFlats))) + 7
    return minor ? "\(minors[index]) minor" : "\(majors[index]) major"
}
