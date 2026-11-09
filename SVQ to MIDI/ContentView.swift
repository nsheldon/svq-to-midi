import SVQKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var showingOptions = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            FileListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            detail
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.showOpenPanel()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Add SVQ files or folders")

                Button {
                    showingOptions.toggle()
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .help("Conversion options")
                .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
                    OptionsView()
                        .environmentObject(model)
                        .padding(16)
                        .frame(width: 440)
                }

                Button {
                    model.convertWithPanel(model.convertibleItems)
                } label: {
                    Label("Convert All", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Convert every loaded song to a MIDI file")
                .disabled(model.convertibleItems.isEmpty)
            }
        }
        #if DEBUG
        .onAppear {
            // Lets screenshots be taken without menu clicks: open -a <app> --args -ShowAboutOnLaunch YES
            if UserDefaults.standard.bool(forKey: "ShowAboutOnLaunch") { openWindow(id: "about") }
        }
        #endif
        .alert("SVQ to MIDI", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        let selected = model.items.filter { model.selection.contains($0.id) }
        if model.items.isEmpty {
            EmptyStateView()
        } else if selected.count == 1, let item = selected.first {
            SongDetailView(item: item)
                .id(item.id)
        } else if selected.count > 1 {
            VStack(spacing: 12) {
                Text("\(selected.count) songs selected")
                    .font(.title2)
                Button("Convert \(selected.count) Songs…") {
                    model.convertWithPanel(model.selectedItems)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Select a song to see its details.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar

struct FileListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                FileRow(item: item)
                    .tag(item.id)
                    // Dragging a song to the Finder or a DAW converts it (each selected song becomes
                    // its own file). The file is made when the drag begins.
                    .midiDrag(isEnabled: item.svq != nil) { model.dragFile(.song, of: item) }
                    .contextMenu {
                        let targets = model.selection.contains(item.id) ? model.selectedItems : [item].filter { $0.svq != nil }
                        Button("Convert…") { model.convertWithPanel(targets) }
                            .disabled(targets.isEmpty)
                        if case .converted = item.status {
                            Button("Show MIDI File in Finder") { model.revealOutputs(of: item) }
                        }
                        Button("Show SVQ File in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        Divider()
                        Button("Remove from List") {
                            model.remove(model.selection.contains(item.id) ? model.selection : [item.id])
                        }
                    }
            }
        }
        .onDeleteCommand { model.remove(model.selection) }
        .safeAreaInset(edge: .bottom) {
            if !model.items.isEmpty {
                HStack {
                    Text("\(model.items.count) song\(model.items.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.removeAll() }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
}

struct FileRow: View {
    let item: SVQItem

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        // The whole row, not just its text, starts a drag: a press on the blank part of a row with a
        // short name would otherwise begin a selection sweep instead (found in V-Synth Patch Composer).
        .contentShape(Rectangle())
        .help(item.svq == nil ? "" : "Drag to the Finder or a DAW to convert this song to a MIDI file")
    }

    private var subtitle: String {
        guard let svq = item.svq else { return item.fileName }
        let duration = Int(svq.duration.rounded())
        return "\(item.fileName) · \(Int(svq.initialBPM.rounded())) BPM · \(duration / 60):\(String(format: "%02d", duration % 60))"
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .converted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .help("Converted")
        case .failed(let message):
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                .help(message)
        case .ready:
            if let error = item.loadError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .help(error)
            } else if let svq = item.svq, !svq.warnings.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help(svq.warnings.joined(separator: "\n"))
            } else {
                Image(systemName: "pianokeys").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pianokeys.inverse")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop SVQ files or folders here")
                .font(.title2)
            Text("Converts Roland XP-50, XP-60, XP-80, Fantom, Fantom-S, Fantom-X and MC-80 sequencer songs to Standard MIDI Files,\nincluding each Part's patch selection from the song's saved Performance.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose Files…") { model.showOpenPanel() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
