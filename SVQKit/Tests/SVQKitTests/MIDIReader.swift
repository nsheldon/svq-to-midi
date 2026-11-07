import Foundation

/// Minimal, lenient Standard MIDI File reader used to check conversions.
struct MIDIReader {
    enum Message: Hashable {
        case channel([UInt8])
        case sysEx([UInt8]) // including F0
        case meta(UInt8, [UInt8])
    }

    struct Event: Hashable {
        var tick: Int
        var message: Message
    }

    var format: Int
    var division: Int
    var tracks: [[Event]]

    init(data: Data) throws {
        let d = [UInt8](data)
        guard d.count >= 14, Array(d[0 ..< 4]) == Array("MThd".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        format = Int(d[8]) << 8 | Int(d[9])
        division = Int(d[12]) << 8 | Int(d[13])
        tracks = []
        var p = 8 + (Int(d[4]) << 24 | Int(d[5]) << 16 | Int(d[6]) << 8 | Int(d[7]))
        func vlq() -> Int {
            var v = 0
            while true {
                let b = d[p]; p += 1
                v = (v << 7) | Int(b & 0x7F)
                if b < 0x80 { return v }
            }
        }
        while p + 8 <= d.count {
            let tag = Array(d[p ..< p + 4])
            let length = Int(d[p + 4]) << 24 | Int(d[p + 5]) << 16 | Int(d[p + 6]) << 8 | Int(d[p + 7])
            p += 8
            let end = p + length
            guard tag == Array("MTrk".utf8) else { p = end; continue }
            var events: [Event] = []
            var tick = 0
            var running: UInt8 = 0
            while p < end {
                tick += vlq()
                let b = d[p]
                if b == 0xFF {
                    let type = d[p + 1]; p += 2
                    let n = vlq()
                    events.append(Event(tick: tick, message: .meta(type, Array(d[p ..< p + n]))))
                    p += n
                } else if b == 0xF0 || b == 0xF7 {
                    p += 1
                    let n = vlq()
                    events.append(Event(tick: tick, message: .sysEx([0xF0] + Array(d[p ..< p + n]))))
                    p += n
                } else {
                    if b & 0x80 != 0 { running = b; p += 1 }
                    let count = (running & 0xF0 == 0xC0 || running & 0xF0 == 0xD0) ? 1 : 2
                    events.append(Event(tick: tick, message: .channel([running] + Array(d[p ..< p + count]))))
                    p += count
                }
            }
            tracks.append(events)
            p = end
        }
    }

    var allEvents: [Event] { tracks.flatMap { $0 } }
}

extension MIDIReader {
    /// The sequence name: the first track's name, as the instruments' own exports write the song title.
    var sequenceName: String? {
        for event in tracks.first ?? [] {
            if case .meta(0x03, let bytes) = event.message {
                return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
