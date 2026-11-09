import Foundation

/// Reads bit fields packed back to back. The XP packs least-significant-bit first; the
/// Fantom-X packs most-significant-bit first.
struct BitReader {
    private let bytes: [UInt8]
    private let msbFirst: Bool
    var position = 0

    init<C: Collection>(_ bytes: C, msbFirst: Bool = false) where C.Element == UInt8 {
        self.bytes = Array(bytes)
        self.msbFirst = msbFirst
    }

    mutating func read(_ width: Int) -> Int {
        var value = 0
        for i in 0 ..< width {
            let byteIndex = position >> 3
            let bit: Bool
            if byteIndex >= bytes.count {
                bit = false
            } else if msbFirst {
                bit = (bytes[byteIndex] >> UInt8(7 - (position & 7))) & 1 == 1
            } else {
                bit = (bytes[byteIndex] >> UInt8(position & 7)) & 1 == 1
            }
            if msbFirst {
                value = value << 1 | (bit ? 1 : 0)
            } else if bit {
                value |= 1 << i
            }
            position += 1
        }
        return value
    }
}

// MARK: - Performance

/// An XP-50/60/80 Performance (the 16-part multitimbral setup) as stored in the "PRFa"
/// block of an SVQ file.
///
/// The block is the Performance's parameters bit-packed least-significant-bit first, each
/// parameter using the bit width given in the XP-80 MIDI Implementation, in the same order
/// as the System Exclusive parameter map: 52 bytes of Common, then 14 bytes per Part.
public struct XPPerformance: Equatable, Sendable {
    /// Performance Common parameter values in MIDI-implementation order (the 2-byte tempo is one value).
    public var common: [Int]
    public var parts: [XPPart]

    static let commonWidths: [Int] =
        Array(repeating: 7, count: 12) // name
        + [4, 6] // EFX source, type
        + Array(repeating: 7, count: 12) // EFX parameters
        + [2, 7, 7, 7, 4, 7, 4, 7] // EFX output assign ... control depth 2
        + [7, 7, 7, 7, 7, 2] // chorus level, rate, depth, pre-delay, feedback, output
        + [3, 7, 7, 5, 7] // reverb type, level, time, HF damp, delay feedback
        + [8, 1] // tempo, keyboard range switch
        + Array(repeating: 7, count: 16) // voice reserve
        + [1, 1] // keyboard mode, clock source
    static let commonPackedBytes = 52
    static let partPackedBytes = 14
    /// Byte offset of the 2-byte (nibblized) Performance Tempo in the SysEx parameter map.
    static let commonTempoIndex = 0x2D

    public init?(packed: [UInt8]) {
        let needed = Self.commonPackedBytes + 16 * Self.partPackedBytes
        guard packed.count >= needed else { return nil }
        // Some variants may carry extra leading data; parts are always the last 16 × 14 bytes.
        let partsStart = packed.count - 16 * Self.partPackedBytes
        let commonStart = partsStart - Self.commonPackedBytes

        var reader = BitReader(packed[commonStart ..< partsStart])
        common = Self.commonWidths.map { reader.read($0) }
        parts = (0 ..< 16).map { index in
            let start = partsStart + index * Self.partPackedBytes
            return XPPart(number: index + 1, packed: packed[start ..< start + Self.partPackedBytes])
        }
    }

    public init(common: [Int], parts: [XPPart]) {
        self.common = common
        self.parts = parts
    }

    public var name: String {
        SVQFile.text(common.prefix(12).map { UInt8(clamping: $0) })
    }

    public var tempo: Int { common[Self.commonTempoIndex] }

    /// Performance Common as the 0x42 data bytes of its System Exclusive parameter map.
    public var commonSysExData: [UInt8] {
        var data: [UInt8] = []
        for (index, value) in common.enumerated() {
            if index == Self.commonTempoIndex {
                data.append(UInt8((value >> 4) & 0x0F))
                data.append(UInt8(value & 0x0F))
            } else {
                data.append(UInt8(value & 0x7F))
            }
        }
        return data
    }

    /// Data Set 1 (DT1) messages that load this Performance into the XP's temporary
    /// Performance (Common at 01 00 00 00, Part n at 01 00 1n 00), exactly as the XP-80
    /// itself transmits them.
    public func sysExMessages(deviceID: UInt8 = 0x10) -> [[UInt8]] {
        var messages = [Roland.dataSet1(deviceID: deviceID, address: [0x01, 0x00, 0x00, 0x00], data: commonSysExData)]
        for part in parts {
            messages.append(Roland.dataSet1(deviceID: deviceID,
                                            address: [0x01, 0x00, 0x10 + UInt8(part.number - 1), 0x00],
                                            data: part.sysExData))
        }
        return messages
    }

    /// Expansion board IDs used by the parts that receive MIDI, in ascending order.
    public var expansionBoards: [Int] {
        Array(Set(parts.filter(\.receiveSwitch).compactMap { part -> Int? in
            part.patch.groupType == 2 ? part.patch.groupID : nil
        })).sorted()
    }
}

// MARK: - Part

public struct XPPart: Equatable, Sendable, Identifiable {
    public var id: Int { number }
    /// 1-16.
    public var number: Int
    /// Parameter values in MIDI-implementation order (2-byte values are single entries).
    public var values: [Int]

    static let widths = [1, 4, 2, 7, 8, 7, 7, 7, 7, 3, 7, 7, 7, 1, 1, 1, 7, 7, 3, 1, 1, 3, 8]
    /// Indices (in `values`) of parameters that are sent as two nibbles in SysEx.
    static let nibblizedIndices: Set<Int> = [4, 22]

    init<C: Collection>(number: Int, packed: C) where C.Element == UInt8 {
        self.number = number
        var reader = BitReader(packed)
        values = Self.widths.map { reader.read($0) }
    }

    public init(number: Int, values: [Int]) {
        self.number = number
        self.values = values
    }

    public var receiveSwitch: Bool { values[0] != 0 }
    /// 0-15.
    public var midiChannel: Int { values[1] }
    public var level: Int { values[5] }
    public var pan: Int { values[6] }
    /// 0-96, 48 = no shift.
    public var coarseTune: Int { values[7] }
    /// 0-100, 50 = no shift.
    public var fineTune: Int { values[8] }
    public var outputAssign: Int { values[9] }
    public var mixEFXSendLevel: Int { values[10] }
    public var chorusSendLevel: Int { values[11] }
    public var reverbSendLevel: Int { values[12] }
    public var keyRangeLower: Int { values[16] }
    public var keyRangeUpper: Int { values[17] }
    /// 0-6, 3 = no shift.
    public var octaveShift: Int { values[18] }

    /// Part 10 holds a Rhythm Set rather than a Patch.
    public var isRhythmPart: Bool { number == 10 }

    public var patch: XPPatchReference {
        XPPatchReference(groupType: values[2], groupID: values[3], number: values[4], isRhythmSet: isRhythmPart)
    }

    var sysExData: [UInt8] {
        var data: [UInt8] = []
        for (index, value) in values.enumerated() {
            if Self.nibblizedIndices.contains(index) {
                data.append(UInt8((value >> 4) & 0x0F))
                data.append(UInt8(value & 0x0F))
            } else {
                data.append(UInt8(value & 0x7F))
            }
        }
        return data
    }
}

// MARK: - Patch reference

/// Identifies a Patch (or Rhythm Set) the way the XP-80 stores it: group type, group ID, number.
public struct XPPatchReference: Equatable, Hashable, Sendable {
    /// 0 = internal (User/Preset/GM), 1 = PCM card, 2 = Wave Expansion board.
    public var groupType: Int
    /// For internal groups: 1 = USER, 3 = PR-A, 4 = PR-B, 5 = PR-C, 6 = GM.
    /// For expansion boards: the board's SR-JV80 number.
    public var groupID: Int
    /// 0-based patch number (0-254).
    public var number: Int
    public var isRhythmSet: Bool

    public init(groupType: Int, groupID: Int, number: Int, isRhythmSet: Bool = false) {
        self.groupType = groupType
        self.groupID = groupID
        self.number = number
        self.isRhythmSet = isRhythmSet
    }

    public var isExpansionBoard: Bool { groupType == 2 }

    /// For an expansion-board patch, the board's title (e.g. "Session"), when known.
    public var boardTitle: String? { isExpansionBoard ? SRJV80Boards.titles[groupID] : nil }

    /// Short group label as shown on the XP-80 ("USER", "PR-A", "GM", "SR-JV80-09", ...).
    public var groupLabel: String {
        switch (groupType, groupID) {
        case (0, 1): return "USER"
        case (0, 3): return "PR-A"
        case (0, 4): return "PR-B"
        case (0, 5): return "PR-C"
        case (0, 6): return "GM"
        case (1, _): return "PCM"
        case (2, let board): return String(format: "SR-JV80-%02d", board)
        default: return "Group \(groupType):\(groupID)"
        }
    }

    /// Patch name from the factory tables, when known (Preset, GM and SR-JV80 expansion-board groups).
    public var name: String? {
        let table: [String]?
        switch (groupType, groupID, isRhythmSet) {
        case (0, 3, false): table = XPPatchNames.presetA
        case (0, 4, false): table = XPPatchNames.presetB
        case (0, 5, false): table = XPPatchNames.presetC
        case (0, 6, false): table = XPPatchNames.gm
        case (0, 3, true): table = XPPatchNames.rhythmPresetA
        case (0, 4, true): table = XPPatchNames.rhythmPresetB
        case (0, 5, true): table = XPPatchNames.rhythmPresetC
        case (0, 6, true): table = XPPatchNames.rhythmGM
        case (2, let board, false): table = SRJV80Boards.boards[board]?.patches
        case (2, let board, true): table = SRJV80Boards.boards[board]?.rhythmSets
        default: table = nil
        }
        guard let table, table.indices.contains(number) else { return nil }
        return table[number]
    }

    /// e.g. "PR-A 001 64voicePiano", "USER 039", "SR-JV80-09 052".
    public var displayName: String {
        let base = "\(groupLabel) \(String(format: "%03d", number + 1))"
        if let name { return "\(base) \(name)" }
        return base
    }

    /// Bank Select MSB, LSB and the 0-based Program Change number that select this patch on an XP-80.
    ///
    /// - Parameter expansionSlot: 0-3 for slots A-D; required for expansion-board patches.
    public func bankSelect(expansionSlot: Int?) -> (msb: UInt8, lsb: UInt8, program: UInt8)? {
        let program = UInt8(number & 0x7F)
        switch (groupType, groupID) {
        case (0, 1): return (80, 0, program)
        case (0, 3): return (81, 0, program)
        case (0, 4): return (81, 1, program)
        case (0, 5): return (81, 2, program)
        case (0, 6): return (81, 3, program)
        case (1, _): return (83, UInt8(min(number >> 7, 1)), program) // PCM card (unverified on the XP-80)
        case (2, _):
            guard let slot = expansionSlot, (0 ... 3).contains(slot) else { return nil }
            return (84, UInt8(slot * 2 + min(number >> 7, 1)), program)
        default:
            return nil
        }
    }
}

// MARK: - Roland SysEx

enum Roland {
    static let manufacturerID: UInt8 = 0x41
    static let xpModelID: UInt8 = 0x6A

    static let fantomXModelID: [UInt8] = [0x00, 0x6B]
    /// The original Fantom (FA-76), per its MIDI Implementation.
    static let fa76ModelID: [UInt8] = [0x00, 0x10]

    static func dataSet1(deviceID: UInt8, modelID: [UInt8] = [xpModelID], address: [UInt8], data: [UInt8]) -> [UInt8] {
        let body = address + data
        let checksum = UInt8((128 - body.reduce(0) { ($0 + Int($1)) } % 128) % 128)
        return [0xF0, manufacturerID, deviceID & 0x7F] + modelID + [0x12] + body + [checksum, 0xF7]
    }
}
