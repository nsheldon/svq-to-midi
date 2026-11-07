import Foundation

/// Accumulates timed events for one MTrk chunk.
struct MIDITrackBuilder {
    private struct Entry {
        var tick: Int
        var priority: Int
        var sequence: Int
        var bytes: [UInt8]
    }

    /// Ordering of events that share a tick.
    enum Priority: Int {
        case meta = 0
        case setup = 1
        case noteOff = 2
        case normal = 3
    }

    private var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }
    var lastTick: Int { entries.map(\.tick).max() ?? 0 }

    mutating func add(_ bytes: [UInt8], at tick: Int, priority: Priority = .normal) {
        entries.append(Entry(tick: max(0, tick), priority: priority.rawValue, sequence: entries.count, bytes: bytes))
    }

    mutating func addMeta(_ type: UInt8, _ data: [UInt8], at tick: Int, priority: Priority = .meta) {
        add([0xFF, type] + MIDIFileWriter.variableLength(data.count) + data, at: tick, priority: priority)
    }

    mutating func addText(_ type: UInt8, _ text: String, at tick: Int = 0) {
        let bytes = Array((text.data(using: .isoLatin1, allowLossyConversion: true) ?? Data(text.utf8)))
        guard !bytes.isEmpty else { return }
        addMeta(type, bytes, at: tick)
    }

    mutating func addSysEx(_ message: [UInt8], at tick: Int, priority: Priority = .normal) {
        guard message.first == 0xF0 else { return }
        let body = Array(message.dropFirst())
        add([0xF0] + MIDIFileWriter.variableLength(body.count) + body, at: tick, priority: priority)
    }

    /// Encodes the chunk, ending it at `endTick` (or at the last event, if later).
    func encoded(endTick: Int) -> [UInt8] {
        let sorted = entries.sorted { a, b in
            if a.tick != b.tick { return a.tick < b.tick }
            if a.priority != b.priority { return a.priority < b.priority }
            return a.sequence < b.sequence
        }
        var body: [UInt8] = []
        var now = 0
        for entry in sorted {
            body += MIDIFileWriter.variableLength(entry.tick - now)
            body += entry.bytes
            now = entry.tick
        }
        body += MIDIFileWriter.variableLength(max(0, endTick - now)) + [0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + MIDIFileWriter.bigEndian(body.count, bytes: 4) + body
    }
}

enum MIDIFileWriter {
    static func file(format: Int, division: Int, tracks: [[UInt8]]) -> Data {
        var data = Array("MThd".utf8)
        data += bigEndian(6, bytes: 4)
        data += bigEndian(format, bytes: 2)
        data += bigEndian(tracks.count, bytes: 2)
        data += bigEndian(division, bytes: 2)
        for track in tracks { data += track }
        return Data(data)
    }

    static func variableLength(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var out: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            out.insert(UInt8(v & 0x7F) | 0x80, at: 0)
            v >>= 7
        }
        return out
    }

    static func bigEndian(_ value: Int, bytes: Int) -> [UInt8] {
        (0 ..< bytes).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }
}
