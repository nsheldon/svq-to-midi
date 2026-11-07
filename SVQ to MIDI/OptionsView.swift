import SVQKit
import SwiftUI

struct OptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Select each Part\u{2019}s patch (Bank Select + Program Change)", isOn: $model.options.addPatchSelection)
                Toggle("Set each Part\u{2019}s level, pan, reverb and chorus", isOn: $model.options.addMixerSettings)
                Toggle("Include the instrument\u{2019}s setup as SysEx on a separate setup track", isOn: $model.options.addPerformanceSysEx)
                Text("XP songs: the Performance, for an XP-50, XP-60 or XP-80. Fantom-X songs: every Part\u{2019}s saved Patch or Rhythm Set plus the Patch-mode sounds, an exact replica of the song\u{2019}s setup (Rhythm Set data is unverified). The song keeps its original timing: solo the setup track and play it through once (a full Fantom-X setup takes about 25 seconds), then mute it and play the song. Fantom-X Parts whose sound is sent this way get no Program Change, which would replace it. Other instruments ignore this data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $model.options.leadInMeasures, in: 0 ... 8) {
                    Text("Lead-in: \(model.options.leadInMeasures) empty measure\(model.options.leadInMeasures == 1 ? "" : "s")")
                }
                .help("Empty measures before the song give the instrument time to select each Part\u{2019}s patch before the first notes.")
            } header: {
                Text("Setup data added at the start")
            }

            Section {
                Picker("Name MIDI files by", selection: $model.naming) {
                    ForEach(OutputNaming.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Also save patterns as separate files", isOn: $model.exportPatterns)
                Toggle("Include tracks whose Output is set to Off", isOn: $model.options.includeOffTracks)
                    .help("Off tracks weren\u{2019}t played by the instrument, but they may hold useful data, such as a SysEx setup dump.")
            } header: {
                Text("Output")
            }

            if !model.boardsInUse.isEmpty {
                Section {
                    ForEach(model.boardsInUse, id: \.self) { board in
                        Picker(String(format: "SR-JV80-%02d", board) + (SRJV80Boards.titles[board].map { " \($0)" } ?? ""), selection: Binding(
                            get: { model.slot(forBoard: board) },
                            set: { model.setSlot($0, forBoard: board) })) {
                            ForEach(0 ..< 4) { Text("Slot \(["A", "B", "C", "D"][$0])").tag($0) }
                        }
                    }
                } header: {
                    Text("XP Wave Expansion board slots")
                } footer: {
                    Text("Bank Select for expansion patches depends on which slot the board was installed in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
