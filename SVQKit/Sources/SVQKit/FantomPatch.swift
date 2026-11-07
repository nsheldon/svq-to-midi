import Foundation

/// A complete Fantom-X Patch or Rhythm Set as saved in an SVQ file's "PATa" / "RHYa" block,
/// convertible back to the System Exclusive data the Fantom-X itself transmits for it.
///
/// A saved sound is the parameters of the SysEx parameter map (Patch: Common, MFX, Chorus,
/// Reverb, Tone Mix Table, Tones 1-4; Rhythm Set: Common, MFX, Chorus, Reverb, 88 Rhythm Tones)
/// in address order, bit-packed most-significant-bit first using `FantomPatchLayout`. Each section
/// starts on a byte boundary, and in a Patch one extra byte precedes Tone 1.
///
/// Patches are verified byte-for-byte against Fantom-X Patch dumps. Rhythm Sets follow the same
/// rules and decode plausibly (all names readable, all values in range) but have not been checked
/// against a Fantom-X Rhythm Set dump.
public struct FantomPatch: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case patch, rhythmSet
    }

    public struct Section: Equatable, Sendable {
        /// The section's offset within the Patch or Rhythm Set: the 2nd and 3rd address bytes
        /// (e.g. [0x00, 0x02] for MFX, [0x01, 0x3E] for Rhythm Tone key 108).
        public var offset: [UInt8]
        /// The section's SysEx data bytes.
        public var data: [UInt8]
    }

    public var kind: Kind
    public var name: String
    public var sections: [Section]

    /// Patch sections: (offset, parameters, extra bytes skipped before the section).
    static let patchLayout: [([UInt8], [FantomParameter], Int)] = [
        ([0x00, 0x00], FantomPatchLayout.common, 0), ([0x00, 0x02], FantomPatchLayout.mfx, 0),
        ([0x00, 0x04], FantomPatchLayout.chorus, 0), ([0x00, 0x06], FantomPatchLayout.reverb, 0),
        ([0x00, 0x10], FantomPatchLayout.toneMixTable, 0),
        ([0x00, 0x20], FantomPatchLayout.tone, 1), ([0x00, 0x22], FantomPatchLayout.tone, 0),
        ([0x00, 0x24], FantomPatchLayout.tone, 0), ([0x00, 0x26], FantomPatchLayout.tone, 0),
    ]

    /// Rhythm Set sections: Common, effects, then Rhythm Tones for keys 21-108 at 00 10, 00 12 … 01 3E.
    static let rhythmLayout: [([UInt8], [FantomParameter], Int)] = {
        var layout: [([UInt8], [FantomParameter], Int)] = [
            ([0x00, 0x00], FantomPatchLayout.rhythmCommon, 0), ([0x00, 0x02], FantomPatchLayout.mfx, 0),
            ([0x00, 0x04], FantomPatchLayout.chorus, 0), ([0x00, 0x06], FantomPatchLayout.reverb, 0),
        ]
        for key in 0 ..< 88 {
            let offset = 0x10 + key * 2 // 7-bit address arithmetic
            layout.append(([UInt8(offset / 128), UInt8(offset % 128)], FantomPatchLayout.rhythmTone, 0))
        }
        return layout
    }()

    /// Decodes one record. Returns nil for an empty record or one too short to hold the sound.
    public init?<C: Collection>(record: C, kind: Kind = .patch) where C.Element == UInt8 {
        let bytes = Array(record)
        let layout = kind == .patch ? Self.patchLayout : Self.rhythmLayout
        let neededBits = layout.reduce(0) { total, section in
            total + section.1.reduce(0) { $0 + $1.bits } + 8 + section.2 * 8
        }
        guard bytes.count * 8 >= neededBits, let name = FantomPerformance.name(at: 0, in: bytes) else { return nil }
        self.kind = kind
        self.name = name

        var reader = BitReader(bytes, msbFirst: true)
        var sections: [Section] = []
        for (offset, parameters, skippedBytes) in layout {
            reader.position = (reader.position + 7) / 8 * 8 + skippedBytes * 8
            var data: [UInt8] = []
            for parameter in parameters {
                var value = reader.read(parameter.bits)
                if parameter.centered { value += 64 - (1 << (parameter.bits - 1)) }
                if parameter.sysExBytes == 1 {
                    data.append(UInt8(value & 0x7F))
                } else {
                    for nibble in (0 ..< parameter.sysExBytes).reversed() {
                        data.append(UInt8((value >> (nibble * 4)) & 0x0F))
                    }
                }
            }
            sections.append(Section(offset: offset, data: data))
        }
        self.sections = sections
    }

    /// Data Set 1 messages that load this sound into a temporary area.
    /// - Parameter base: The first two address bytes of the destination's temporary Patch, e.g.
    ///   `[0x1F, 0x00]` for Patch mode's keyboard part or `temporaryAddress(forPart:)`. A Rhythm Set
    ///   goes to the matching temporary Rhythm Set (+ 00 10 00 00).
    public func sysExMessages(to base: [UInt8], deviceID: UInt8 = 0x10) -> [[UInt8]] {
        let second = base[1] + (kind == .rhythmSet ? 0x10 : 0)
        return sections.map { section in
            Roland.dataSet1(deviceID: deviceID, modelID: Roland.fantomXModelID,
                            address: [base[0], second + section.offset[0], section.offset[1], 0x00],
                            data: section.data)
        }
    }

    /// The temporary Patch address of a Performance Part (1-16): 11 00, 11 20, 11 40, 11 60, 12 00 …
    public static func temporaryAddress(forPart part: Int) -> [UInt8] {
        let index = max(0, min(15, part - 1))
        return [UInt8(0x11 + index / 4), UInt8((index % 4) * 0x20)]
    }

    /// Patch mode's keyboard and pad parts.
    public static let keyboardAddress: [UInt8] = [0x1F, 0x00]
    public static let padAddress: [UInt8] = [0x1F, 0x20]
}
