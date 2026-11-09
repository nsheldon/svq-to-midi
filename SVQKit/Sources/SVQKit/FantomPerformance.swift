import Foundation

/// A Fantom-X6/X7/X8 Performance as stored in the "PRFa" block of a Fantom-X SVQ file,
/// together with the names of the Patches and Rhythm Sets saved with it ("PATa", "RHYa").
///
/// Fantom-X data blocks start with a 16-byte header (record count, record size, header size,
/// zero) followed by the records. Parameters are bit-packed most-significant-bit first.
public struct FantomPerformance: Equatable, Sendable {
    public enum SoundMode: Int, Sendable {
        case patch = 0, performance, gm1, gm2, gs, piano
    }

    public var name: String
    public var parts: [FantomPart]
    /// The Sound Mode saved in the song's Setup ("STPa"); nil if the block is missing.
    public var soundMode: SoundMode?
    /// Patch mode's keyboard sound (patch record 17) and pad sound (rhythm record 18).
    public var keyboardPart: FantomPart?
    public var padPart: FantomPart?
    /// The saved Patch and Rhythm Set blocks: records 1-16 belong to the Performance Parts,
    /// 17 and 18 to Patch mode's keyboard and pad parts.
    let patchBlock: [UInt8]?
    let rhythmBlock: [UInt8]?
    /// The Performance record itself ("PRFa" record 1).
    let performanceRecord: [UInt8]
    /// The Setup record ("STPa"): 34 bytes from a Fantom-X, 32 from a Fantom-S.
    let setupRecord: [UInt8]?
    /// True for a song saved by a Fantom-S or S88, told apart by its 32-byte Setup record (the
    /// Fantom-X's is 34; checked on Roland's five Fantom-S demo songs and 13 Fantom-X songs). Its
    /// Setup and Performance Controller sections are shorter, and its factory sounds differ.
    public let isFantomS: Bool

    /// Bit position of Part 1 inside the Performance record, and the size of each Part.
    static let partsBitOffset = 3186
    static let partBits = 288

    public init?(performanceBlock: [UInt8], patchBlock: [UInt8]?, rhythmBlock: [UInt8]?, setupBlock: [UInt8]? = nil) {
        self.patchBlock = patchBlock
        self.rhythmBlock = rhythmBlock
        guard let record = Self.record(0, in: performanceBlock),
              record.count * 8 >= Self.partsBitOffset + 16 * Self.partBits else { return nil }
        performanceRecord = Array(record)
        let setupRecord = setupBlock.flatMap { Self.record(0, in: $0) }.map(Array.init)
        self.setupRecord = setupRecord
        let isFantomS = setupRecord.map { $0.count < 34 } ?? false
        self.isFantomS = isFantomS
        name = Self.name(at: 0, in: record) ?? ""

        var parts: [FantomPart] = []
        for index in 0 ..< 16 {
            var r = BitReader(record, msbFirst: true)
            r.position = Self.partsBitOffset + index * Self.partBits
            var part = FantomPart(number: index + 1, isFantomS: isFantomS)
            part.midiChannel = r.read(4)
            part.receiveSwitch = r.read(1) == 1
            part.bankMSB = r.read(7)
            part.bankLSB = r.read(7)
            part.program = r.read(7)
            part.level = r.read(7)
            part.pan = r.read(7)
            // Coarse/fine tune, mono/poly, legato, bend range, portamento, 4 tone offsets,
            // octave, velocity sense, 4 reserved, mute, dry send.
            r.position += 7 + 7 + 2 + 2 + 5 + 2 + 8 + 4 * 7 + 3 + 7 + 4 * 7 + 1 + 7
            part.chorusSendLevel = r.read(7)
            part.reverbSendLevel = r.read(7)

            let source = part.isRhythmSet ? rhythmBlock : patchBlock
            part.storedName = source.flatMap { Self.record(index, in: $0) }.flatMap { Self.name(at: 0, in: $0) }
            parts.append(part)
        }
        self.parts = parts

        // Setup: Sound Mode (3 bits), then Bank MSB/LSB/Program for the Performance,
        // the keyboard Patch and the pad Patch (7 bits each).
        if let setup = setupBlock.flatMap({ Self.record(0, in: $0) }), setup.count >= 9 {
            var r = BitReader(setup, msbFirst: true)
            soundMode = SoundMode(rawValue: r.read(3))
            _ = (r.read(7), r.read(7), r.read(7)) // Performance bank and program
            func patchModePart(_ number: Int, record: Int, channel: Int) -> FantomPart {
                var part = FantomPart(number: number, savedRecord: record, isFantomS: isFantomS)
                part.midiChannel = channel
                part.bankMSB = r.read(7)
                part.bankLSB = r.read(7)
                part.program = r.read(7)
                let source = part.isRhythmSet ? rhythmBlock : patchBlock
                part.storedName = source.flatMap { Self.record(record, in: $0) }.flatMap { Self.name(at: 0, in: $0) }
                return part
            }
            // The Patch-mode receive channels are system settings that aren't saved with the song;
            // these are the Fantom-X defaults.
            keyboardPart = patchModePart(1, record: 16, channel: 0)
            padPart = patchModePart(2, record: 17, channel: 9)
        }
    }

    /// The complete saved sound (Patch or Rhythm Set) of a Part, or nil if none was saved
    /// (GM2 sounds aren't saved with the song).
    public func savedSound(of part: FantomPart) -> FantomPatch? {
        let record = part.savedRecord
        let block = part.isRhythmSet ? rhythmBlock : patchBlock
        guard let data = block.flatMap({ Self.record(record, in: $0) }) else { return nil }
        return FantomPatch(record: data, kind: part.isRhythmSet ? .rhythmSet : .patch)
    }

    // MARK: Performance SysEx

    /// Where each section of the Performance is stored: the third address byte of its SysEx
    /// section (temporary Performance = 10 00 xx 00), its parameters, its first bit in the record,
    /// and undocumented bits that precede it. The sections aren't stored in address order.
    static let performanceLayout: [(address: UInt8, parameters: [FantomParameter], startBit: Int, skippedBits: Int)] = {
        var layout: [(address: UInt8, parameters: [FantomParameter], startBit: Int, skippedBits: Int)] = [
            (0x00, FantomPerformanceLayout.common, 0, 0),
            (0x02, FantomPatchLayout.mfx, 384, 0), (0x08, FantomPatchLayout.mfx, 1008, 0),
            (0x0A, FantomPatchLayout.mfx, 1632, 0),
            (0x04, FantomPatchLayout.chorus, 2256, 0), (0x06, FantomPatchLayout.reverb, 2592, 0),
        ]
        for i in 0 ..< 16 { layout.append((UInt8(0x10 + i), FantomPerformanceLayout.midi, 2928 + 16 * i, 0)) }
        for i in 0 ..< 16 { layout.append((UInt8(0x20 + i), FantomPerformanceLayout.part, 3184 + 288 * i, 2)) }
        for i in 0 ..< 16 { layout.append((UInt8(0x50 + i), FantomPerformanceLayout.zone, 7792 + 88 * i, 0)) }
        layout.append((0x60, FantomPerformanceLayout.controller, 9200, 0))
        return layout
    }()

    /// Data Set 1 messages that load the whole Performance (Common, MFX 1-3, Chorus, Reverb, and
    /// the MIDI, Part and Zone settings of all 16 Parts, Controller) into the temporary Performance.
    ///
    /// **Unverified**: no Fantom-X Performance dump was available to check against. The layout
    /// (docs/SVQ-Format.md) is inferred from the manual's parameter map with the packing rules that
    /// were verified for Patches, and checked for plausibility across 87 saved Performances. The
    /// order of the three MFX blocks and the position of each Part's Decay Time Offset are inferred.
    /// - Parameter includeControllers: Also send the 16 Zones (keyboard ranges, external zones) and the
    ///   Controller (pads, D Beam, switches), which affect the instrument's own controls, not the song.
    public func performanceSysExMessages(deviceID: UInt8 = 0x10, includeControllers: Bool = true) -> [[UInt8]] {
        Self.performanceLayout.filter { includeControllers || $0.address < 0x50 }.map { section in
            let parameters = section.address == 0x60 && isFantomS
                ? Array(section.parameters.prefix(FantomPerformanceLayout.fantomSControllerCount)) : section.parameters
            var reader = BitReader(performanceRecord, msbFirst: true)
            reader.position = section.startBit + section.skippedBits
            var data: [UInt8] = []
            for (index, parameter) in parameters.enumerated() {
                var value = reader.read(parameter.bits)
                if parameter.centered { value += 64 - (1 << (parameter.bits - 1)) }
                if section.address >= 0x20, section.address < 0x30, index == FantomPerformanceLayout.partDecayTimeOffsetIndex {
                    // Its slot in map order holds a value that depends only on the Part number; the
                    // 7 bits at the end of the stored Part are taken to be the Decay Time Offset.
                    var end = BitReader(performanceRecord, msbFirst: true)
                    end.position = section.startBit + 281
                    value = end.read(7)
                }
                if parameter.sysExBytes == 1 {
                    data.append(UInt8(value & 0x7F))
                } else {
                    for nibble in (0 ..< parameter.sysExBytes).reversed() {
                        data.append(UInt8((value >> (nibble * 4)) & 0x0F))
                    }
                }
            }
            return Roland.dataSet1(deviceID: deviceID, modelID: Roland.fantomXModelID,
                                   address: [0x10, 0x00, section.address, 0x00], data: data)
        }
    }

    /// A Data Set 1 message for the song's Setup (01 00 00 00), sent before the Performance.
    ///
    /// It is the whole Setup section: Sound Mode, the selected Performance and keyboard and pad
    /// Patches, effect switches, transpose, octave, arpeggio, rhythm and chord settings. From a
    /// Fantom-X (34-byte record) that is 52 SysEx bytes from the 213 bits the map accounts for.
    /// The Fantom-S's Setup is the same section without the last five parameters (two reserved,
    /// Rolled Chord, Rolled Chord Type, Arpeggio Step): 47 bytes from the record's first 196 bits,
    /// all in range in Roland's five demo songs. Selecting a Performance or Patch loads the stored
    /// one, which the dumps sent after it replace.
    public func setupSysExMessages(deviceID: UInt8 = 0x10) -> [[UInt8]] {
        guard let setup = setupRecord, !setup.isEmpty else { return [] }
        let layout = isFantomS
            ? Array(FantomPerformanceLayout.setup.prefix(FantomPerformanceLayout.fantomSSetupCount))
            : FantomPerformanceLayout.setup
        let data: [UInt8]
        if setup.count * 8 >= layout.reduce(0) { $0 + $1.bits } {
            data = layout.sysExData(reading: setup, at: 0)
        } else {
            data = [setup[0] >> 5] // Sound Mode: the first 3 bits
        }
        return [Roland.dataSet1(deviceID: deviceID, modelID: Roland.fantomXModelID,
                                address: [0x01, 0x00, 0x00, 0x00], data: data)]
    }

    /// Record `index` of a Fantom-X data block, or nil if the block is too short.
    static func record(_ index: Int, in block: [UInt8]) -> ArraySlice<UInt8>? {
        guard block.count >= 16 else { return nil }
        func u32(_ o: Int) -> Int { Int(block[o]) << 24 | Int(block[o + 1]) << 16 | Int(block[o + 2]) << 8 | Int(block[o + 3]) }
        let count = u32(0), size = u32(4), header = u32(8)
        guard index < count, size > 0, header + (index + 1) * size <= block.count else { return nil }
        return block[(header + index * size) ..< (header + (index + 1) * size)]
    }

    /// A 12-character name stored as 7-bit characters, MSB first.
    static func name<C: Collection>(at bit: Int, in record: C) -> String? where C.Element == UInt8 {
        var r = BitReader(record, msbFirst: true)
        r.position = bit
        let chars = (0 ..< 12).map { _ in UInt8(r.read(7)) }
        guard chars.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else { return nil }
        let text = SVQFile.text(chars)
        return text.isEmpty ? nil : text
    }
}

public struct FantomPart: Equatable, Sendable {
    public var number: Int
    public var midiChannel = 0
    public var receiveSwitch = true
    public var bankMSB = 0
    public var bankLSB = 0
    /// 0-based Program Change number.
    public var program = 0
    public var level = 100
    public var pan = 64
    public var chorusSendLevel = 0
    public var reverbSendLevel = 0
    /// The Patch or Rhythm Set name saved with the song (absent for GM2 sounds).
    public var storedName: String?

    /// Index of this part's sound in the saved Patch / Rhythm Set blocks (0-15 for Performance
    /// Parts, 16 and 17 for Patch mode's keyboard and pad parts).
    public internal(set) var savedRecord: Int

    /// Saved by a Fantom-S or S88, whose factory sounds differ from the Fantom-X's.
    public internal(set) var isFantomS: Bool

    init(number: Int, savedRecord: Int? = nil, isFantomS: Bool = false) {
        self.number = number
        self.savedRecord = savedRecord ?? number - 1
        self.isFantomS = isFantomS
    }

    /// The instrument's factory sound list.
    private var soundList: FantomSoundList { isFantomS ? .fantomS : .fantomX }

    /// Rhythm Sets: USER/CARD/PRST (MSB 86), SRX (92), GM2 (120).
    public var isRhythmSet: Bool { [86, 92, 120].contains(bankMSB) }

    /// Group label as shown on the Fantom-X ("USER", "PR-F", "GM2", ...).
    public var groupLabel: String {
        switch (bankMSB, bankLSB) {
        case (87, 0 ... 1), (86, 0): return "USER"
        case (87, 32 ... 33), (86, 32): return "CARD"
        case (87, 64 ... 72) where bankLSB - 64 < soundList.presets.count: // PR-I: Audio Track Expansion
            return "PR-" + String(UnicodeScalar(UInt8(65 + bankLSB - 64)))
        case (64, _): return "USAM"
        case (65, _): return "CSAM"
        case (86, 64): return "PRST"
        case (121, _), (120, _): return "GM2"
        case (93, _): return SRXBoards.patch(lsb: bankLSB, program: program).map { String(format: "SRX-%02d", $0.board) } ?? "SRX"
        case (92, _): return SRXBoards.rhythmSet(lsb: bankLSB, program: program).map { String(format: "SRX-%02d", $0.board) } ?? "SRX"
        default: return "Bank \(bankMSB)/\(bankLSB)"
        }
    }

    /// 1-based number within the group, as the Fantom-X shows it. USER and CARD have 256
    /// patches across two LSBs, large SRX boards up to four; GM2 sounds are numbered in Sound List order.
    public var numberInGroup: Int {
        switch (bankMSB, bankLSB) {
        case (87, 1), (87, 33): return program + 129
        case (64, _), (65, _): return bankLSB * 128 + program + 1
        case (93, _): return SRXBoards.patch(lsb: bankLSB, program: program)?.number ?? program + 1
        case (121, _):
            if let i = soundList.gm2.firstIndex(where: { $0.lsb == bankLSB && $0.program == program }) { return i + 1 }
            return program + 1
        case (120, _):
            if let i = soundList.gm2RhythmSets.firstIndex(where: { $0.program == program }) { return i + 1 }
            return program + 1
        default:
            return program + 1
        }
    }

    /// The saved name, or the factory name for preset and GM2 sounds.
    public var name: String? {
        if let storedName { return storedName }
        return factoryName
    }

    /// The factory name: from the Fantom-X's or Fantom-S's Sound List for preset and GM2 sounds, from the SRX
    /// board's owner's manual for SRX sounds.
    public var factoryName: String? {
        switch (bankMSB, bankLSB) {
        case (87, 64 ... 72):
            guard soundList.presets.indices.contains(bankLSB - 64) else { return nil }
            let group = soundList.presets[bankLSB - 64]
            return group.indices.contains(program) ? group[program] : nil
        case (86, 64):
            return soundList.presetRhythmSets.indices.contains(program) ? soundList.presetRhythmSets[program] : nil
        case (121, _):
            return soundList.gm2.first { $0.lsb == bankLSB && $0.program == program }?.name
        case (120, _):
            return soundList.gm2RhythmSets.first { $0.program == program }?.name
        case (93, _):
            return SRXBoards.patch(lsb: bankLSB, program: program)?.name
        case (92, _):
            return SRXBoards.rhythmSet(lsb: bankLSB, program: program)?.name
        default:
            return nil
        }
    }

    /// e.g. "PR-F 009 UltimatGrand".
    public var displayName: String {
        let base = "\(groupLabel) \(String(format: "%03d", numberInGroup))"
        if let name { return "\(base) \(name)" }
        return base
    }
}

/// A Fantom-series factory sound list (generated tables).
struct FantomSoundList {
    let presets: [[String]]
    let presetRhythmSets: [String]
    let gm2: [(lsb: Int, program: Int, name: String)]
    let gm2RhythmSets: [(program: Int, name: String)]

    static let fantomX = FantomSoundList(presets: FantomPatchNames.presets,
                                         presetRhythmSets: FantomPatchNames.presetRhythmSets,
                                         gm2: FantomPatchNames.gm2, gm2RhythmSets: FantomPatchNames.gm2RhythmSets)
    static let fantomS = FantomSoundList(presets: FantomSPatchNames.presets,
                                         presetRhythmSets: FantomSPatchNames.presetRhythmSets,
                                         gm2: FantomSPatchNames.gm2, gm2RhythmSets: FantomSPatchNames.gm2RhythmSets)
}
