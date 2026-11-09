import Foundation

/// The XP-50/60/80 System settings saved with a song (the `SYSb` block, or `SYSa` in older files),
/// limited to the ones that shape how the song sounds.
///
/// The blocks hold System Common (SysEx 00 00 00 00 …) in map order, bit-packed least-significant-
/// bit first like `PRFa`, then the Scale Tunes of Parts 1-16 and Patch mode (12 × 7 bits, padded to
/// 11 bytes each) from bit 408 (`SYSb`) or 400 (`SYSa`). Worked out from 75 blocks in the owner's
/// songs and backups, every value in range; the Performance Number matches the user Performance
/// holding the song's `PRFa` (see docs/SVQ-Format.md). No System dump was available to compare with.
///
/// The player's preferences in the same block (receive switches, control channel, pedals, keyboard
/// velocity, preview notes, …) are sent only on request (`controllerSysExMessages`): they belong to
/// the player's setup, and some (such as Receive Bank Select) could stop the converted song's own
/// setup from working.
public struct XPSystem: Equatable, Sendable {
    /// 0 PERFORM, 1 PATCH, 2 GM.
    public var soundMode: Int
    /// The selected user Performance (0-127 = USER:01-128).
    public var performanceNumber: Int
    /// Patch mode's Patch: group type, group ID and number (0-254).
    public var patchGroupType: Int
    public var patchGroupID: Int
    public var patchNumber: Int
    /// 63 = 440.0 Hz.
    public var masterTune: Int
    public var scaleTuneSwitch: Bool
    public var efxSwitch: Bool
    public var chorusSwitch: Bool
    public var reverbSwitch: Bool
    /// Scale Tune C-B (0-127, 64 = 0 cents) of Parts 1-16, then Patch mode.
    public var scaleTunes: [[Int]]

    /// The saved block, for the player's preferences.
    let block: [UInt8]
    let scaleTunesAt: Int

    /// - Parameter scaleTunesAt: The first Scale Tune bit: 408 in `SYSb`, 400 in `SYSa`.
    init?(block: [UInt8], scaleTunesAt: Int) {
        self.block = block
        self.scaleTunesAt = scaleTunesAt
        guard block.count * 8 >= scaleTunesAt + 17 * 88 else { return nil }
        var r = BitReader(block, msbFirst: false)
        soundMode = r.read(2)
        performanceNumber = r.read(7)
        patchGroupType = r.read(2)
        patchGroupID = r.read(7)
        patchNumber = r.read(8)
        masterTune = r.read(7)
        scaleTuneSwitch = r.read(1) == 1
        efxSwitch = r.read(1) == 1
        chorusSwitch = r.read(1) == 1
        reverbSwitch = r.read(1) == 1
        scaleTunes = (0 ..< 17).map { set in
            var t = BitReader(block, msbFirst: false)
            t.position = scaleTunesAt + set * 88
            return (0 ..< 12).map { _ in t.read(7) }
        }
        guard soundMode <= 2, masterTune <= 126 else { return nil }
    }

    /// Data Set 1 messages: System Common 00-0A (Sound Mode, Performance Number, Patch mode's Patch,
    /// Master Tune, Scale Tune, EFX, Chorus and Reverb switches) as one message, then, when the
    /// Scale Tune switch is on, the 17 Scale Tune sets (00 00 10 00 … 1F 00 for Parts 1-16, 20 00
    /// for Patch mode).
    public func sysExMessages(deviceID: UInt8 = 0x10) -> [[UInt8]] {
        let common: [Int] = [soundMode, performanceNumber, patchGroupType, patchGroupID,
                             patchNumber >> 4, patchNumber & 0x0F, masterTune,
                             scaleTuneSwitch ? 1 : 0, efxSwitch ? 1 : 0, chorusSwitch ? 1 : 0, reverbSwitch ? 1 : 0]
        var messages = [Roland.dataSet1(deviceID: deviceID, address: [0x00, 0x00, 0x00, 0x00],
                                        data: common.map { UInt8($0 & 0x7F) })]
        if scaleTuneSwitch {
            for (set, tunes) in scaleTunes.enumerated() {
                messages.append(Roland.dataSet1(deviceID: deviceID, address: [0x00, 0x00, UInt8(0x10 + set), 0x00],
                                                data: tunes.map { UInt8($0 & 0x7F) }))
            }
        }
        return messages
    }

    // MARK: The player's preferences

    /// System Common 0B-51 in map order with their stored widths: Patch Remain, Clock Source, the
    /// control sources, receive switches, Control and Patch Receive channels, Rhythm Edit Source,
    /// preview, transmit switches, transpose, octave, keyboard and aftertouch sense, Pedal 1-2, C1/C2,
    /// Hold Pedal, Bank Select Groups 1-7. They follow the Reverb Switch, from bit 37 to bit 317.
    static let preferenceWidths: [Int] = [1, 1, 3, 3, 3, 1, 2, 7, 7, 1, 1, 1, 1, 1, 1, 1, 1, 5, 4, 1, 1]
        + [7, 7, 7, 7, 7, 7, 7, 7] + [1, 1, 5, 1, 4, 3, 7, 2, 7, 7, 2, 1, 7, 2, 1, 7, 2, 7, 2, 2, 1]
        + Array(repeating: [1, 7, 7], count: 7).flatMap { $0 }
    /// Pedal 3 and 4 (52-57), then the arpeggio (58-5F, Style, Motif and Beat Pattern stored 7 bits
    /// wide), from bit 336. `SYSa` ends at bit 400, before the arpeggio's octave range and part.
    static let pedalArpeggioWidths: [Int] = [7, 2, 1, 7, 2, 1, 7, 7, 7, 7, 7, 7, 3, 4]

    /// Data Set 1 messages for the player's preferences: System Common 0B-51, then 52-5F (just 52-5D
    /// from a `SYSa` block, which has no room for the rest). Unverified like the rest of the block,
    /// and the arpeggio's identities are inferred (see docs/SVQ-Format.md).
    public func controllerSysExMessages(deviceID: UInt8 = 0x10) -> [[UInt8]] {
        var r = BitReader(block, msbFirst: false)
        r.position = 37
        let preferences = Self.preferenceWidths.map { UInt8(r.read($0) & 0x7F) }
        var messages = [Roland.dataSet1(deviceID: deviceID, address: [0x00, 0x00, 0x00, 0x0B], data: preferences)]
        let available = (scaleTunesAt - 336) >= Self.pedalArpeggioWidths.reduce(0, +)
            ? Self.pedalArpeggioWidths : Array(Self.pedalArpeggioWidths.prefix(12))
        r.position = 336
        messages.append(Roland.dataSet1(deviceID: deviceID, address: [0x00, 0x00, 0x00, 0x52],
                                        data: available.map { UInt8(r.read($0) & 0x7F) }))
        return messages
    }
}
