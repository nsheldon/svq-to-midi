// Generated from the "Parameter Address Map" in the Fantom-X Owner's Manual (MIDI Implementation).
// Each entry is one parameter in address order: how many SysEx bytes it occupies (multi-byte values
// are sent as 4-bit nibbles), how many bits it uses in an SVQ file, and whether its SysEx value is
// centered on 64 but stored re-centered in fewer bits.

struct FantomParameter: Equatable, Sendable {
    let sysExBytes: Int
    let bits: Int
    let centered: Bool
}

private let c = true
private func F(_ sysExBytes: Int, _ bits: Int, _ centered: Bool = false) -> FantomParameter {
    FantomParameter(sysExBytes: sysExBytes, bits: bits, centered: centered)
}

enum FantomPatchLayout {
    /// Patch Common (78 parameters, 79 SysEx bytes)
    static let common: [FantomParameter] = [
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 7), F(1, 7),
        F(1, 1), F(1, 7), F(1, 7), F(1, 3, c), F(1, 2), F(1, 7), F(1, 1), F(1, 1),
        F(1, 1), F(1, 1), F(1, 1), F(1, 1), F(1, 1), F(1, 7), F(1, 1), F(2, 8),
        F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 4), F(1, 1),
        F(1, 6), F(1, 6), F(1, 7), F(1, 6), F(1, 7), F(1, 6), F(1, 7), F(1, 6),
        F(1, 7), F(1, 6), F(1, 7), F(1, 7), F(1, 6), F(1, 7), F(1, 6), F(1, 7),
        F(1, 6), F(1, 7), F(1, 6), F(1, 7), F(1, 7), F(1, 6), F(1, 7), F(1, 6),
        F(1, 7), F(1, 6), F(1, 7), F(1, 6), F(1, 7), F(1, 7), F(1, 6), F(1, 7),
        F(1, 6), F(1, 7), F(1, 6), F(1, 7), F(1, 6), F(1, 7),
    ]

    /// Patch Common MFX (49 parameters, 145 SysEx bytes)
    static let mfx: [FantomParameter] = [
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 2), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 5), F(1, 5), F(1, 5),
        F(1, 5), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16),
    ]

    /// Patch Common Chorus (24 parameters, 84 SysEx bytes)
    static let chorus: [FantomParameter] = [
        F(1, 4), F(1, 7), F(1, 2), F(1, 2), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
    ]

    /// Patch Common Reverb (23 parameters, 83 SysEx bytes)
    static let reverb: [FantomParameter] = [
        F(1, 4), F(1, 7), F(1, 2), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
        F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16), F(4, 16),
    ]

    /// Patch TMT (Tone Mix Table) (41 parameters, 41 SysEx bytes)
    static let toneMixTable: [FantomParameter] = [
        F(1, 4), F(1, 2), F(1, 4), F(1, 2), F(1, 2), F(1, 1), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7),
    ]

    /// Patch Tone (142 parameters, 154 SysEx bytes)
    static let tone: [FantomParameter] = [
        F(1, 7), F(1, 7), F(1, 7), F(1, 5), F(1, 7), F(1, 5, c), F(1, 6), F(1, 7),
        F(1, 1), F(1, 2), F(2, 8), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 4), F(1, 1), F(1, 1), F(1, 1), F(1, 1), F(1, 1), F(1, 2), F(1, 2),
        F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2),
        F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(1, 2), F(4, 16),
        F(4, 16), F(4, 16), F(1, 2), F(1, 1), F(1, 2), F(1, 5), F(1, 1), F(1, 6, c),
        F(1, 5, c), F(1, 7), F(1, 7), F(1, 7), F(1, 5, c), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 3), F(1, 7),
        F(1, 6, c), F(1, 3), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 3), F(1, 7),
        F(1, 7), F(1, 7), F(1, 5, c), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 5, c), F(1, 7), F(1, 2), F(1, 3),
        F(1, 7), F(1, 7), F(1, 7), F(1, 5, c), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 4), F(2, 8), F(1, 3), F(1, 7), F(1, 7),
        F(1, 5, c), F(1, 2), F(1, 7), F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 4), F(2, 8), F(1, 3), F(1, 7), F(1, 7), F(1, 5, c), F(1, 2), F(1, 7),
        F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 4), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
    ]

    /// Rhythm Common (17 parameters, 18 SysEx bytes)
    static let rhythmCommon: [FantomParameter] = [
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(2, 8), F(1, 1),
        F(1, 4),
    ]

    /// Rhythm Tone (159 parameters, 195 SysEx bytes)
    static let rhythmTone: [FantomParameter] = [
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 5), F(1, 7), F(1, 7),
        F(1, 7), F(1, 5), F(1, 7), F(1, 6), F(1, 7), F(1, 1), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 4), F(1, 6), F(1, 1), F(1, 1), F(1, 1),
        F(1, 2), F(1, 1), F(1, 2), F(4, 16), F(4, 16), F(4, 16), F(1, 2), F(1, 1),
        F(1, 2), F(1, 5), F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 2),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 2), F(4, 16),
        F(4, 16), F(4, 16), F(1, 2), F(1, 1), F(1, 2), F(1, 5), F(1, 1), F(1, 7),
        F(1, 7), F(1, 7), F(1, 1), F(1, 2), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 1), F(1, 2), F(4, 16), F(4, 16), F(4, 16), F(1, 2), F(1, 1),
        F(1, 2), F(1, 5), F(1, 1), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 2),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 2), F(4, 16),
        F(4, 16), F(4, 16), F(1, 2), F(1, 1), F(1, 2), F(1, 5), F(1, 1), F(1, 7),
        F(1, 7), F(1, 7), F(1, 1), F(1, 2), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 5, c), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 3), F(1, 7),
        F(1, 3), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 3), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 3), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7),
        F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 7), F(1, 1), F(1, 7),
    ]
}

extension Array where Element == FantomParameter {
    /// The SysEx data of a section whose parameters are packed MSB-first from `bit` of `record`:
    /// one byte per parameter, or one nibble per byte for multi-byte parameters, re-centering the
    /// 64-centered ones. `overrides` replaces parameters' values by index.
    func sysExData(reading record: [UInt8], at bit: Int, overrides: [Int: Int] = [:]) -> [UInt8] {
        var reader = BitReader(record, msbFirst: true)
        reader.position = bit
        var data: [UInt8] = []
        for (index, parameter) in enumerated() {
            var value = reader.read(parameter.bits)
            if parameter.centered { value += 64 - (1 << (parameter.bits - 1)) }
            if let override = overrides[index] { value = override }
            if parameter.sysExBytes == 1 {
                data.append(UInt8(value & 0x7F))
            } else {
                for nibble in (0 ..< parameter.sysExBytes).reversed() {
                    data.append(UInt8((value >> (nibble * 4)) & 0x0F))
                }
            }
        }
        return data
    }
}
