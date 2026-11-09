import SVQKit
import SwiftUI

/// The detail pane's tabs.
enum DetailTab: String, CaseIterable, Identifiable {
    case setup = "Song Setup"
    case phrases = "Phrase Tracks"
    case patterns = "Pattern Tracks"
    var id: String { rawValue }
}

struct SongDetailView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("detailTab") private var tab: DetailTab = .setup
    let item: SVQItem

    var body: some View {
        if let svq = item.svq {
            VStack(alignment: .leading, spacing: 0) {
                header(svq)
                    .padding([.horizontal, .top], 20)
                    .padding(.bottom, 14)
                Picker("View", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
                Divider()
                switch tab {
                case .setup:
                    VStack(alignment: .leading, spacing: 0) {
                        stats(svq)
                            .padding(20)
                        Divider()
                        PartsTable(item: item, svq: svq)
                    }
                case .phrases:
                    PhraseTracksView(item: item, svq: svq)
                case .patterns:
                    PatternTracksView(item: item, svq: svq)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("\u{201C}\(item.fileName)\u{201D} can\u{2019}t be read.")
                    .font(.title3)
                Text(item.loadError ?? "")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ svq: SVQFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.largeTitle.weight(.semibold))
                        .textSelection(.enabled)
                    Text([item.fileName, svq.formatDescription].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !svq.comment.isEmpty {
                        // The comment line saved with the song on the instrument (Roland's demo
                        // songs carry a copyright notice here).
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Song comment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(svq.comment)
                                .textSelection(.enabled)
                        }
                        .help("The comment saved with the song on the instrument")
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Convert…") { model.convertWithPanel([item]) }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    conversionStatus
                }
            }
            ForEach(svq.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if let audio = item.audioTrackFile {
                Label("The song\u{2019}s Fantom-X audio tracks (\(audio.lastPathComponent)) aren\u{2019}t exported.",
                      systemImage: "waveform")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    /// The line under Convert. Its height is always reserved, so nothing moves when a conversion
    /// finishes and "Show in Finder" appears.
    private var conversionStatus: some View {
        ZStack(alignment: .trailing) {
            Button("Show in Finder") {}
                .buttonStyle(.link)
                .hidden()
            switch item.status {
            case .converted:
                Button("Show in Finder") { model.revealOutputs(of: item) }
                    .buttonStyle(.link)
            case .failed(let message):
                Label("Couldn\u{2019}t convert", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(message)
            case .ready:
                EmptyView()
            }
        }
    }

    private func stats(_ svq: SVQFile) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
            GridRow {
                stat("Tempo", tempoText(svq))
                stat("Meter", svq.initialTimeSignature.displayString)
                stat("Length", durationText(svq))
                stat("Notes", svq.noteCount.formatted())
            }
            GridRow {
                stat("Tracks", tracksText(svq))
                    .help("Tracks sent only to MIDI Out played an external instrument, so they get no Part setup.")
                stat("Resolution", "\(svq.resolution) ppq")
                stat("Patterns", patternText(svq))
                stat("SysEx in song", svq.containsSysEx ? "Yes" : "No")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "–" : value).monospacedDigit()
        }
    }

    private func tracksText(_ svq: SVQFile) -> String {
        svq.usedTracks.map { track in
            let output = svq.output(ofTrack: track)
            return output.playsInternally ? "\(track + 1)" : "\(track + 1) (\(output.displayName))"
        }.joined(separator: ", ")
    }

    private func patternText(_ svq: SVQFile) -> String {
        if svq.patterns.isEmpty { return "None" }
        if svq.patternCallCount > 0 { return "\(svq.patterns.count), played by the song" }
        return "\(svq.patterns.count)"
    }

    private func tempoText(_ svq: SVQFile) -> String {
        let text = bpmText(svq.initialBPM)
        return svq.hasTempoChanges ? text + " (changes)" : text
    }

    private func durationText(_ svq: SVQFile) -> String {
        let seconds = Int(svq.duration.rounded())
        let measures = svq.songLength / max(1, svq.initialTimeSignature.ticksPerMeasure(resolution: svq.resolution))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) (\(measures) bars)"
    }
}

/// "120 BPM", or "92.5 BPM" when the tempo isn't a whole number.
func bpmText(_ bpm: Double) -> String {
    abs(bpm - bpm.rounded()) < 0.05 ? "\(Int(bpm.rounded())) BPM" : String(format: "%.1f BPM", bpm)
}

// MARK: - Performance parts

struct PartRow: Identifiable {
    let part: SetupPart
    let isPlayed: Bool
    let bank: BankSelect?
    let slot: Int?
    var id: Int { part.number }
}

struct PartsTable: View {
    @EnvironmentObject private var model: AppModel
    let item: SVQItem
    let svq: SVQFile

    var body: some View {
        if let performance = svq.setup {
            let channels = svq.internallyPlayedChannels
            let rows = performance.parts.map { part in
                PartRow(part: part,
                        isPlayed: part.receiveSwitch && channels.contains(UInt8(part.midiChannel)),
                        bank: part.bankSelect(slotForBoard: { model.slot(forBoard: $0) }),
                        slot: part.expansionBoard.map { model.slot(forBoard: $0) })
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(headerText(performance))
                        .font(.headline)
                    Spacer()
                    Text("Bold parts are played by the song. Drag any Part to the Finder or a DAW for the song\u{2019}s setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(setupDragHelp)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, performance.note == nil ? 10 : 4)
                if let note = performance.note {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                partsTable(rows)
            }
        } else {
            Text("This song has no saved Performance, so the converted file will contain only the recorded song data.")
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private let setupDragHelp = "Drag any Part to the Finder or a DAW for a MIDI file of the song\u{2019}s setup alone: "
        + "the setup SysEx, then each channel\u{2019}s Bank Select, Program Change and mixer settings"

    /// Every row drags the same thing, the song's whole setup, so it doesn't matter which is picked.
    /// Table rows gained `.draggable` in macOS 14 (the method confirmed with the Finder and Logic);
    /// macOS 13 uses an item provider. An availability check can't go inside the rows builder.
    @ViewBuilder
    private func partsTable(_ rows: [PartRow]) -> some View {
        if #available(macOS 14, *) {
            Table(of: PartRow.self) {
                columns
            } rows: {
                ForEach(rows) { row in
                    TableRow(row).draggable(model.dragFile(.setup, of: item))
                }
            }
        } else {
            Table(of: PartRow.self) {
                columns
            } rows: {
                ForEach(rows) { row in
                    TableRow(row).itemProvider { model.dragFile(.setup, of: item).itemProvider() }
                }
            }
        }
    }

    @TableColumnBuilder<PartRow, Never>
    private var columns: some TableColumnContent<PartRow, Never> {
                TableColumn("Part") { row in
                    Text(row.part.label).fontWeight(row.isPlayed ? .bold : .regular)
                }
                .width(36)
                TableColumn("Ch") { row in
                    Text(row.part.receiveSwitch ? "\(row.part.midiChannel + 1)" : "off")
                        .foregroundStyle(row.part.receiveSwitch ? .primary : .secondary)
                }
                .width(32)
                TableColumn("Patch") { row in
                    Text(row.part.displayName)
                        .fontWeight(row.isPlayed ? .bold : .regular)
                        .help(row.part.isRhythmSet ? "Rhythm Set" : "Patch")
                }
                .width(min: 160, ideal: 210)
                TableColumn("Bank / Program") { row in
                    Text(bankText(row))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120)
                TableColumn("Level") { row in mixer(row, "\(row.part.level)") }
                    .width(40)
                TableColumn("Pan") { row in mixer(row, panText(row.part.pan)) }
                    .width(40)
                TableColumn("Reverb") { row in mixer(row, "\(row.part.reverbSendLevel)") }
                    .width(46)
                TableColumn("Chorus") { row in mixer(row, "\(row.part.chorusSendLevel)") }
                    .width(46)
    }

    private func headerText(_ setup: PerformanceSetup) -> String {
        if setup.instrument.contains("Patch mode") { return setup.instrument }
        if setup.name.isEmpty { return setup.instrument }
        return "\(setup.instrument) \(setup.kind) \u{201C}\(setup.name)\u{201D}"
    }

    private func mixer(_ row: PartRow, _ value: String) -> some View {
        Text(row.part.hasMixerSettings ? value : "–")
            .monospacedDigit()
            .foregroundStyle(row.part.hasMixerSettings ? .primary : .secondary)
    }

    private func bankText(_ row: PartRow) -> String {
        guard let bank = row.bank else { return "–" }
        var text = "\(bank.msb)/\(bank.lsb) · \(Int(bank.program) + 1)"
        if let slot = row.slot { text += " (\(["A", "B", "C", "D"][slot]))" }
        return text
    }

    private func panText(_ pan: Int) -> String {
        switch pan {
        case 64: return "C"
        case ..<64: return "L\(64 - pan)"
        default: return "R\(pan - 64)"
        }
    }
}
