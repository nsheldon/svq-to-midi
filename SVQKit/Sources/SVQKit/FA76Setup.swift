import Foundation

/// The sound setup the original Fantom (FA-76) saves with a song ("SV02" files, `SVD1` directory with
/// model "NEXY"): the Setup (`STPa`), the Performance (`PRFa`) and the Multitimbre (`MLTa`).
///
/// Like the Fantom-S/X's, the blocks start with a 16-byte header (record count, record size, header
/// size, zero) and pack the parameters of the MIDI Implementation's map most-significant-bit first.
/// Both the Performance and the Multitimbre begin with their 12-character name, and both hold their
/// 16 Parts at bit 3026, 288 bits each, with the map's Part parameters in order (receive channel,
/// receive switch, MIDI 1/2 switches, Bank Select MSB/LSB, program, level, pan, …). Found from the
/// Fantom 1.20 firmware's 16 preset Multitimbres and 64 preset Performances (stored in the same form)
/// and the one song available, all of which decode consistently; no Fantom MIDI export was available.
///
/// The Fantom saves no Patches with a song, so its Parts select sounds by Bank Select and Program
/// Change only, as the XP's do.
public struct FA76Setup: Equatable, Sendable {
    public enum SoundMode: Int, Sendable {
        case performance = 0, patch, multitimbre, gm1, gm2, gs
    }

    /// The Sound Mode the song was saved in; nil if the Setup block is missing.
    public var soundMode: SoundMode?
    public var performanceName: String
    public var performanceParts: [FA76Part]
    public var multitimbreName: String
    public var multitimbreParts: [FA76Part]
    /// The Patch selected for Patch mode (MSB, LSB, program from the Setup).
    public var patch: FA76Part?
    /// The saved records themselves, for regenerating their SysEx.
    let performanceRecord: [UInt8]?
    let multitimbreRecord: [UInt8]?
    let setupRecord: [UInt8]?

    static let partsBitOffset = 3026
    static let partBits = 288

    public init?(setupBlock: [UInt8]?, performanceBlock: [UInt8]?, multitimbreBlock: [UInt8]?) {
        func parts(of block: [UInt8]?) -> (String, [FA76Part])? {
            guard let record = block.flatMap({ FantomPerformance.record(0, in: $0) }),
                  // Up to the last Part's reverb send (the Multitimbre record ends 2 bits short of a whole Part 16).
                  record.count * 8 >= Self.partsBitOffset + 15 * Self.partBits + 163 else { return nil }
            let name = FantomPerformance.name(at: 0, in: record) ?? ""
            let parts = (0 ..< 16).map { index -> FA76Part in
                var r = BitReader(record, msbFirst: true)
                r.position = Self.partsBitOffset + index * Self.partBits
                var part = FA76Part(number: index + 1)
                part.midiChannel = r.read(4)
                part.receiveSwitch = r.read(1) == 1
                r.position += 2 // Receive MIDI 1 and 2
                part.bankMSB = r.read(7)
                part.bankLSB = r.read(7)
                part.program = r.read(7)
                part.level = r.read(7)
                part.pan = r.read(7)
                // Coarse/fine tune, mono/poly, legato, bend range, portamento switch and time, four
                // offsets, octave shift, velocity sense, key range and fade widths, mute, dry send.
                r.position += 7 + 7 + 2 + 2 + 5 + 2 + 8 + 4 * 7 + 3 + 7 + 4 * 7 + 1 + 7
                part.chorusSendLevel = r.read(7)
                part.reverbSendLevel = r.read(7)
                return part
            }
            return (name, parts)
        }
        let performance = parts(of: performanceBlock)
        let multitimbre = parts(of: multitimbreBlock)
        performanceRecord = performance == nil ? nil : performanceBlock.flatMap { FantomPerformance.record(0, in: $0) }.map(Array.init)
        multitimbreRecord = multitimbre == nil ? nil : multitimbreBlock.flatMap { FantomPerformance.record(0, in: $0) }.map(Array.init)
        guard performance != nil || multitimbre != nil else { return nil }
        setupRecord = setupBlock.flatMap { FantomPerformance.record(0, in: $0) }.map(Array.init)
        performanceName = performance?.0 ?? ""
        performanceParts = performance?.1 ?? []
        multitimbreName = multitimbre?.0 ?? ""
        multitimbreParts = multitimbre?.1 ?? []

        // Setup: Sound Mode (3 bits), then Bank Select MSB, LSB and program (7 bits each) for the
        // Multitimbre, the Performance and the Patch.
        if let setup = setupBlock.flatMap({ FantomPerformance.record(0, in: $0) }), setup.count >= 9 {
            var r = BitReader(setup, msbFirst: true)
            soundMode = SoundMode(rawValue: r.read(3))
            r.position += 6 * 7
            var part = FA76Part(number: 1)
            part.bankMSB = r.read(7)
            part.bankLSB = r.read(7)
            part.program = r.read(7)
            patch = part
        }
    }

    // MARK: SysEx

    /// The sections of a saved Performance or Multitimbre: the third address byte of the SysEx
    /// section (temporary Performance 10 00 xx 00, temporary Multitimbre 19 00 xx 00), its parameters,
    /// its first bit in the record, and undocumented bits that precede it. Sections start on byte
    /// boundaries in this order; the Multitimbre has no Zones or Controller.
    static func sections(performance: Bool) -> [(address: UInt8, parameters: [FantomParameter], startBit: Int, skippedBits: Int)] {
        var result: [(address: UInt8, parameters: [FantomParameter], startBit: Int, skippedBits: Int)] = []
        var byte = 0
        func add(_ address: Int, _ parameters: [FantomParameter], skippedBits: Int = 0) {
            result.append((UInt8(address), parameters, byte * 8, skippedBits))
            byte += (skippedBits + parameters.reduce(0) { $0 + $1.bits } + 7) / 8
        }
        add(0x00, FA76Layout.common)
        add(0x02, FA76Layout.mfx); add(0x08, FA76Layout.mfx); add(0x0A, FA76Layout.mfx)
        add(0x04, FA76Layout.chorus); add(0x06, FA76Layout.reverb)
        for i in 0 ..< 16 { add(0x10 + i, FA76Layout.midi) }
        for i in 0 ..< 16 { add(0x20 + i, FA76Layout.part, skippedBits: 2) }
        if performance {
            for i in 0 ..< 16 { add(0x50 + i, FA76Layout.zone) }
            add(0x60, FA76Layout.controller)
        }
        return result
    }

    /// Data Set 1 messages that set the instrument up as the song was saved: the Setup (its Sound
    /// Mode first, as Roland's own Fantom demo song sends), then the saved Multitimbre or Performance into the
    /// temporary area, section by section. Nil for Patch and GM modes, which have nothing saved to send.
    ///
    /// **Unverified**: no Fantom dump was available. The layout fits the firmware's 80 preset
    /// records and the demo song exactly, with every value in range (see `FA76Setup`). Each Part's
    /// Decay Time Offset is sent as 64 (no offset): its slot in the saved Part holds something else.
    /// - Parameter includeControllers: For a Performance, also send its 16 Zones and Controller
    ///   (the keyboard's and controllers' setup).
    public func sysExMessages(deviceID: UInt8 = 0x10, includeControllers: Bool = true) -> [[UInt8]]? {
        let mode = soundMode ?? .multitimbre
        let usePerformance: Bool
        switch mode {
        case .performance: usePerformance = true
        case .multitimbre: usePerformance = false
        default: return nil
        }
        guard let record = usePerformance ? performanceRecord : multitimbreRecord else { return nil }
        let base: UInt8 = usePerformance ? 0x10 : 0x19
        // The whole Setup (Sound Mode, the selected Multitimbre, Performance and Patch, effect
        // switches, transpose, octave shift); just the Sound Mode if the Setup block is missing.
        let setupData = setupRecord.map { $0.count * 8 >= 76 ? FA76Layout.setup.sysExData(reading: $0, at: 0) : [UInt8(mode.rawValue)] }
            ?? [UInt8(mode.rawValue)]
        var messages = [Roland.dataSet1(deviceID: deviceID, modelID: Roland.fa76ModelID,
                                        address: [0x01, 0x00, 0x00, 0x00], data: setupData)]
        for section in Self.sections(performance: usePerformance) where includeControllers || section.address < 0x50 {
            var reader = BitReader(record, msbFirst: true)
            reader.position = section.startBit + section.skippedBits
            var data: [UInt8] = []
            let isPart = (0x20 ..< 0x30).contains(section.address)
            for (index, parameter) in section.parameters.enumerated() {
                var value = reader.read(parameter.bits)
                if parameter.centered { value += 64 - (1 << (parameter.bits - 1)) }
                if isPart, index == FA76Layout.partDecayTimeOffsetIndex { value = 64 }
                if parameter.sysExBytes == 1 {
                    data.append(UInt8(value & 0x7F))
                } else {
                    for nibble in (0 ..< parameter.sysExBytes).reversed() {
                        data.append(UInt8((value >> (nibble * 4)) & 0x0F))
                    }
                }
            }
            messages.append(Roland.dataSet1(deviceID: deviceID, modelID: Roland.fa76ModelID,
                                            address: [base, 0x00, section.address, 0x00], data: data))
        }
        return messages
    }

    /// The name of what `sysExMessages` sends, e.g. "Multitimbre \"FantomMedley\"".
    public var sysExDescription: String? {
        switch soundMode ?? .multitimbre {
        case .performance: return performanceRecord == nil ? nil : "Performance \"\(performanceName)\""
        case .multitimbre: return multitimbreRecord == nil ? nil : "Multitimbre \"\(multitimbreName)\""
        default: return nil
        }
    }

    /// The Parts that play the song: the Performance's in Performance mode, otherwise the
    /// Multitimbre's (the Fantom's mode for sequencing).
    public var activeParts: [FA76Part] {
        soundMode == .performance && !performanceParts.isEmpty ? performanceParts : multitimbreParts
    }
}

/// One Part of an original Fantom (FA-76) Performance or Multitimbre.
public struct FA76Part: Equatable, Sendable {
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

    /// Rhythm Sets: USER/PRST (MSB 86), SRX (92), GM2 (120).
    public var isRhythmSet: Bool { [86, 92, 120].contains(bankMSB) }

    /// Group label as the Fantom shows it ("USER", "PR-A" … "PR-E", "PRST", "GM2", "SRX-nn").
    public var groupLabel: String {
        switch (bankMSB, bankLSB) {
        case (87, 0), (86, 0): return "USER"
        case (87, 71 ... 75): return "PR-" + String(UnicodeScalar(UInt8(65 + bankLSB - 71)))
        case (86, 71): return "PRST"
        case (121, _), (120, _): return "GM2"
        case (93, _): return SRXBoards.patch(lsb: bankLSB, program: program).map { String(format: "SRX-%02d", $0.board) } ?? "SRX"
        case (92, _): return SRXBoards.rhythmSet(lsb: bankLSB, program: program).map { String(format: "SRX-%02d", $0.board) } ?? "SRX"
        default: return "Bank \(bankMSB)/\(bankLSB)"
        }
    }

    /// 1-based number within the group; GM2 sounds are numbered in the Patch List's order.
    public var numberInGroup: Int {
        switch (bankMSB, bankLSB) {
        case (93, _): return SRXBoards.patch(lsb: bankLSB, program: program)?.number ?? program + 1
        case (121, _):
            if let i = FA76Names.gm2.firstIndex(where: { $0.lsb == bankLSB && $0.program == program }) { return i + 1 }
            return program + 1
        case (120, _):
            if let i = FA76Names.gm2RhythmSets.firstIndex(where: { $0.program == program }) { return i + 1 }
            return program + 1
        default:
            return program + 1
        }
    }

    /// The factory name of a preset, GM2 or SRX sound. User sounds aren't saved with the song, so
    /// they have none.
    public var name: String? {
        switch (bankMSB, bankLSB) {
        case (87, 71 ... 75):
            let group = FA76Names.presets[bankLSB - 71]
            return group.indices.contains(program) ? group[program] : nil
        case (86, 71):
            return FA76Names.presetRhythmSets.indices.contains(program) ? FA76Names.presetRhythmSets[program] : nil
        case (121, _):
            return FA76Names.gm2.first { $0.lsb == bankLSB && $0.program == program }?.name
        case (120, _):
            return FA76Names.gm2RhythmSets.first { $0.program == program }?.name
        case (93, _):
            return SRXBoards.patch(lsb: bankLSB, program: program)?.name
        case (92, _):
            return SRXBoards.rhythmSet(lsb: bankLSB, program: program)?.name
        default:
            return nil
        }
    }

    /// e.g. "PR-B 043 Analog Brs1", or "USER 012".
    public var displayName: String {
        let base = "\(groupLabel) \(String(format: "%03d", numberInGroup))"
        return name.map { "\(base) \($0)" } ?? base
    }
}
