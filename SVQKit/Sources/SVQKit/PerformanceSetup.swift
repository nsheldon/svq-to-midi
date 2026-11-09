import Foundation

public struct BankSelect: Equatable, Hashable, Sendable {
    public var msb: UInt8
    public var lsb: UInt8
    /// 0-based Program Change number.
    public var program: UInt8
}

/// One Part of the saved Performance, independent of the instrument that wrote the file.
public struct SetupPart: Identifiable, Equatable, Sendable {
    public var id: Int { number }
    public var number: Int
    /// What to show in a "Part" column ("1"-"16", or "Kbd"/"Pad" for Fantom-X Patch mode).
    public var label: String
    public var receiveSwitch: Bool
    /// 0-15.
    public var midiChannel: Int
    public var level: Int
    public var pan: Int
    public var reverbSendLevel: Int
    public var chorusSendLevel: Int
    public var isRhythmSet: Bool
    /// False when the instrument has no part mixer for this sound (Fantom-X Patch mode).
    public var hasMixerSettings: Bool
    public var displayName: String
    /// XP only: the patch reference (expansion-board patches need a slot to form a Bank Select).
    public var xpPatch: XPPatchReference?
    /// Fantom-X: the Bank Select stored in the Performance.
    var storedBank: BankSelect?
    /// Fantom-X: the song saved this Part's complete sound, which the SysEx option sends to the
    /// Part's temporary area (a Program Change would replace it with the stored sound).
    public var hasSavedSound = false

    /// The XP expansion board this Part's patch comes from, if any.
    public var expansionBoard: Int? {
        guard let patch = xpPatch, patch.isExpansionBoard else { return nil }
        return patch.groupID
    }

    /// Bank Select and Program Change that choose this Part's sound.
    /// - Parameter slotForBoard: XP only; returns the slot (0-3) an expansion board was installed in.
    public func bankSelect(slotForBoard: (Int) -> Int) -> BankSelect? {
        if let storedBank { return storedBank }
        guard let patch = xpPatch else { return nil }
        let slot = patch.isExpansionBoard ? slotForBoard(patch.groupID) : nil
        return patch.bankSelect(expansionSlot: slot).map { BankSelect(msb: $0.msb, lsb: $0.lsb, program: $0.program) }
    }
}

/// The saved Performance in a form shared by XP and Fantom-X files.
public struct PerformanceSetup: Equatable, Sendable {
    public var name: String
    public var instrument: String
    public var parts: [SetupPart]
    /// An explanation shown with the parts, e.g. for songs saved in Patch mode.
    public var note: String?
    /// What the setup is called on the instrument: "Performance", or "Multitimbre" on the original Fantom.
    public var kind = "Performance"
}

extension SVQFile {
    /// The Performance saved with the song, from either an XP or a Fantom-X file.
    public var setup: PerformanceSetup? {
        if let xp = performance {
            return PerformanceSetup(name: xp.name, instrument: "XP-80", parts: xp.parts.map { part in
                SetupPart(number: part.number, label: "\(part.number)", receiveSwitch: part.receiveSwitch,
                          midiChannel: part.midiChannel, level: part.level, pan: part.pan,
                          reverbSendLevel: part.reverbSendLevel, chorusSendLevel: part.chorusSendLevel,
                          isRhythmSet: part.isRhythmPart, hasMixerSettings: true,
                          displayName: part.patch.displayName, xpPatch: part.patch, storedBank: nil)
            })
        }
        if let fa76 = fa76Setup { return fa76PerformanceSetup(fa76) }
        guard let fantom = fantomPerformance else { return nil }
        func setupPart(_ part: FantomPart, label: String, mixer: Bool) -> SetupPart {
            var setup = SetupPart(number: part.number, label: label, receiveSwitch: part.receiveSwitch, midiChannel: part.midiChannel,
                      level: part.level, pan: part.pan, reverbSendLevel: part.reverbSendLevel,
                      chorusSendLevel: part.chorusSendLevel, isRhythmSet: part.isRhythmSet, hasMixerSettings: mixer,
                      displayName: part.displayName, xpPatch: nil,
                      storedBank: BankSelect(msb: UInt8(part.bankMSB & 0x7F), lsb: UInt8(part.bankLSB & 0x7F),
                                             program: UInt8(part.program & 0x7F)))
            setup.hasSavedSound = fantom.savedSound(of: part) != nil
            return setup
        }
        let model = fantom.isFantomS ? "Fantom-S" : "Fantom-X"
        switch fantom.soundMode {
        case .patch? where fantom.keyboardPart != nil && fantom.padPart != nil:
            let keyboard = fantom.keyboardPart!, pad = fantom.padPart!
            return PerformanceSetup(
                name: keyboard.name ?? "", instrument: "\(model) Patch mode",
                parts: [setupPart(keyboard, label: "Kbd", mixer: false), setupPart(pad, label: "Pad", mixer: false)],
                note: "This song was saved in Patch mode, so it plays the keyboard Patch and the pad sound rather than the Performance. "
                    + "Their receive channels aren't saved with the song, so the Fantom-X\u{2019}s defaults (1 and 10) are used.")
        case .gm1?, .gm2?, .gs?:
            return PerformanceSetup(name: "", instrument: "\(model) GM/GS mode", parts: [],
                                    note: "This song was saved in GM/GS mode, so it relies on its own program changes.")
        default:
            return PerformanceSetup(name: fantom.name, instrument: model,
                                    parts: fantom.parts.map { setupPart($0, label: "\($0.number)", mixer: true) })
        }
    }

    /// The original Fantom's (FA-76) setup: the Multitimbre (its mode for sequencing), the
    /// Performance, or the Patch, depending on the Sound Mode the song was saved in.
    private func fa76PerformanceSetup(_ fa76: FA76Setup) -> PerformanceSetup {
        func setupPart(_ part: FA76Part, label: String, channel: Int? = nil, mixer: Bool = true) -> SetupPart {
            SetupPart(number: part.number, label: label, receiveSwitch: part.receiveSwitch,
                      midiChannel: channel ?? part.midiChannel, level: part.level, pan: part.pan,
                      reverbSendLevel: part.reverbSendLevel, chorusSendLevel: part.chorusSendLevel,
                      isRhythmSet: part.isRhythmSet, hasMixerSettings: mixer, displayName: part.displayName,
                      xpPatch: nil,
                      storedBank: BankSelect(msb: UInt8(part.bankMSB & 0x7F), lsb: UInt8(part.bankLSB & 0x7F),
                                             program: UInt8(part.program & 0x7F)))
        }
        switch fa76.soundMode {
        case .patch?:
            guard let patch = fa76.patch else { fallthrough }
            return PerformanceSetup(
                name: patch.displayName, instrument: "Fantom Patch mode",
                parts: [setupPart(patch, label: "Patch", channel: 0, mixer: false)],
                note: "This song was saved in Patch mode, so it plays one Patch. Its receive channel is a system "
                    + "setting that isn't saved with the song, so channel 1 (the Fantom's default) is used.")
        case .gm1?, .gm2?, .gs?:
            return PerformanceSetup(name: "", instrument: "Fantom GM/GS mode", parts: [],
                                    note: "This song was saved in GM/GS mode, so it relies on its own program changes.")
        case .performance? where !fa76.performanceParts.isEmpty:
            return PerformanceSetup(name: fa76.performanceName, instrument: "Fantom",
                                    parts: fa76.performanceParts.map { setupPart($0, label: "\($0.number)") })
        default:
            return PerformanceSetup(name: fa76.multitimbreName, instrument: "Fantom",
                                    parts: fa76.multitimbreParts.map { setupPart($0, label: "\($0.number)") },
                                    kind: "Multitimbre")
        }
    }
}
