import AppKit
import SVQKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let svq = UTType(importedAs: "com.roland.svq")
}

/// One loaded SVQ file.
struct SVQItem: Identifiable {
    enum Status: Equatable {
        case ready
        case converted([URL])
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let svq: SVQFile?
    let loadError: String?
    var status: Status = .ready

    var fileName: String { url.lastPathComponent }

    var title: String {
        if let name = svq?.songName, !name.isEmpty { return name }
        return url.deletingPathExtension().lastPathComponent
    }
}

enum OutputNaming: String, CaseIterable, Identifiable, Codable {
    case songTitle, fileName
    var id: String { rawValue }
    var label: String {
        switch self {
        case .songTitle: return "Song title"
        case .fileName: return "SVQ file name"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var items: [SVQItem] = []
    @Published var selection: Set<SVQItem.ID> = []
    @Published var lastOutputFolder: URL?
    @Published var alertMessage: String?

    @Published var options: SVQConversionOptions { didSet { save() } }
    @Published var exportPatterns: Bool { didSet { save() } }
    @Published var naming: OutputNaming { didSet { save() } }

    private let defaults = UserDefaults.standard

    private init() {
        var loaded = SVQConversionOptions()
        if let data = defaults.data(forKey: "options"),
           let saved = try? JSONDecoder().decode(SVQConversionOptions.self, from: data) {
            loaded = saved
        }
        // Settings version 2: the SysEx option no longer needs a lead-in. Earlier versions set a
        // one-measure lead-in automatically when it was turned on, so remove that one.
        if defaults.integer(forKey: "settingsVersion") < 2 {
            if loaded.addPerformanceSysEx && loaded.leadInMeasures == 1 { loaded.leadInMeasures = 0 }
            defaults.set(2, forKey: "settingsVersion")
        }
        options = loaded
        exportPatterns = defaults.object(forKey: "exportPatterns") as? Bool ?? true
        naming = OutputNaming(rawValue: defaults.string(forKey: "naming") ?? "") ?? .songTitle
    }

    private func save() {
        if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: "options") }
        defaults.set(exportPatterns, forKey: "exportPatterns")
        defaults.set(naming.rawValue, forKey: "naming")
    }

    // MARK: Loading

    /// Adds files (or every .svq file inside folders). Already-loaded files are skipped.
    func add(urls: [URL]) {
        var added: [SVQItem] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            for file in Self.svqFiles(at: url) where !items.contains(where: { $0.url == file })
                && !added.contains(where: { $0.url == file }) {
                do {
                    added.append(SVQItem(url: file, svq: try SVQFile(contentsOf: file), loadError: nil))
                } catch {
                    added.append(SVQItem(url: file, svq: nil, loadError: error.localizedDescription))
                }
            }
        }
        if added.isEmpty, !urls.isEmpty, items.isEmpty {
            alertMessage = "No SVQ files were found."
        }
        items += added
        if selection.isEmpty, let first = added.first { selection = [first.id] }
    }

    private static func svqFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue { return isSVQ(url) ? [url] : [] }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension.lowercased() == "svq" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// An .svq file, or another file that starts like one. Anything else dropped on the window (such
    /// as a MIDI file dragged out of the app itself) is ignored.
    private static func isSVQ(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "svq" { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 4)) ?? Data())
        return head.count == 4 && head[2] == 0x53 && head[3] == 0x56 // "SV"
    }

    func remove(_ ids: Set<SVQItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func removeAll() {
        items.removeAll()
        selection.removeAll()
    }

    // MARK: Expansion boards

    /// SR-JV80 board numbers used by any loaded song.
    var boardsInUse: [Int] {
        Array(Set(items.flatMap { $0.svq?.performance?.expansionBoards ?? [] })).sorted()
    }

    func slot(forBoard board: Int) -> Int {
        options.slot(forBoard: board, boardsInUse: boardsInUse)
    }

    func setSlot(_ slot: Int, forBoard board: Int) {
        // Pin every visible board so changing one doesn't silently move the others.
        for b in boardsInUse where options.expansionSlots[b] == nil {
            options.expansionSlots[b] = self.slot(forBoard: b)
        }
        options.expansionSlots[board] = slot
    }

    /// Options with every board in use pinned to its displayed slot.
    var effectiveOptions: SVQConversionOptions {
        var result = options
        for board in boardsInUse where result.expansionSlots[board] == nil {
            result.expansionSlots[board] = slot(forBoard: board)
        }
        return result
    }

    // MARK: Converting

    var convertibleItems: [SVQItem] { items.filter { $0.svq != nil } }

    var selectedItems: [SVQItem] { items.filter { selection.contains($0.id) && $0.svq != nil } }

    /// Asks for a destination folder, then converts `targets`.
    func convertWithPanel(_ targets: [SVQItem]) {
        guard !targets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Convert"
        panel.message = targets.count == 1
            ? "Choose where to save \u{201C}\(targets[0].title)\u{201D} as a MIDI file."
            : "Choose where to save \(targets.count) MIDI files."
        panel.directoryURL = lastOutputFolder ?? targets.first?.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let planned = targets.flatMap { plannedOutputs(for: $0, in: folder) }
        let existing = planned.filter { FileManager.default.fileExists(atPath: $0.path) }
        var replace = true
        if !existing.isEmpty {
            let alert = NSAlert()
            alert.messageText = existing.count == 1
                ? "\u{201C}\(existing[0].lastPathComponent)\u{201D} already exists."
                : "\(existing.count) files already exist in this folder."
            alert.informativeText = "Do you want to replace them, or keep both by saving with new names?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Keep Both")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: replace = true
            case .alertSecondButtonReturn: replace = false
            default: return
            }
        }
        convert(targets, to: folder, replaceExisting: replace)
    }

    func convert(_ targets: [SVQItem], to folder: URL, replaceExisting: Bool) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let options = effectiveOptions
        var failures: [String] = []
        for target in targets {
            guard let index = items.firstIndex(where: { $0.id == target.id }), let svq = target.svq else { continue }
            do {
                var written: [URL] = []
                let outputs = plannedOutputs(for: target, in: folder)
                let song = replaceExisting ? outputs[0] : uniqueURL(outputs[0])
                try SVQConverter.midiData(for: svq, title: target.title, options: options).write(to: song, options: .atomic)
                written.append(song)
                if exportPatterns {
                    for (pattern, planned) in zip(svq.patterns, outputs.dropFirst()) {
                        let url = replaceExisting ? planned : uniqueURL(planned)
                        try SVQConverter.midiData(for: svq, pattern: pattern, options: options).write(to: url, options: .atomic)
                        written.append(url)
                    }
                }
                items[index].status = .converted(written)
            } catch {
                items[index].status = .failed(error.localizedDescription)
                failures.append("\(target.fileName): \(error.localizedDescription)")
            }
        }
        lastOutputFolder = folder
        if !failures.isEmpty {
            alertMessage = "Some files could not be converted:\n\n" + failures.joined(separator: "\n")
        }
    }

    private func baseName(for item: SVQItem) -> String {
        Self.safeFileName(naming == .songTitle ? item.title : item.url.deletingPathExtension().lastPathComponent)
    }

    /// `name` with the characters a file name can't hold replaced.
    nonisolated static func safeFileName(_ name: String) -> String {
        let cleaned = String(name.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    // MARK: Dragging out

    /// What can be dragged out of a song: all of it, its setup, one phrase track, the Tempo or Beat
    /// track, or one pattern. Each becomes a MIDI file named as Convert names its files.
    enum DragContent {
        case song, setup, track(Int), conductor(SVQConverter.ConductorTrack), pattern(SVQPattern)
    }

    /// The MIDI file for dragging `content` of `item` out, using the current options.
    func dragFile(_ content: DragContent, of item: SVQItem) -> MIDIDragFile {
        guard let svq = item.svq else { return MIDIDragFile(name: baseName(for: item), data: Data()) }
        let base = baseName(for: item)
        let options = effectiveOptions
        switch content {
        case .song:
            return MIDIDragFile(name: base, data: SVQConverter.midiData(for: svq, title: item.title, options: options))
        case .setup:
            return MIDIDragFile(name: "\(base) - Song Setup",
                                data: SVQConverter.setupMIDIData(for: svq, title: "\(item.title) - Song Setup", options: options) ?? Data())
        case .track(let track):
            let suffix = "Track \(String(format: "%02d", track + 1))"
            return MIDIDragFile(name: "\(base) - \(suffix)",
                                data: SVQConverter.midiData(for: svq, track: track, title: "\(item.title) - \(suffix)", options: options))
        case .conductor(let kind):
            let suffix = kind == .tempo ? "Tempo Track" : "Beat Track"
            return MIDIDragFile(name: "\(base) - \(suffix)",
                                data: SVQConverter.midiData(for: svq, conductorTrack: kind, title: "\(item.title) - \(suffix)", options: options))
        case .pattern(let pattern):
            let suffix = pattern.fileLabel
            return MIDIDragFile(name: "\(base) - \(suffix)",
                                data: SVQConverter.midiData(for: svq, pattern: pattern, title: "\(item.title) - \(suffix)", options: options))
        }
    }

    /// The song file first, then one file per pattern (when pattern export is on).
    private func plannedOutputs(for item: SVQItem, in folder: URL) -> [URL] {
        let base = baseName(for: item)
        var urls = [folder.appendingPathComponent(base).appendingPathExtension("mid")]
        if exportPatterns, let patterns = item.svq?.patterns {
            urls += patterns.map {
                folder.appendingPathComponent(Self.safeFileName("\(base) - \($0.fileLabel)"))
                    .appendingPathExtension("mid")
            }
        }
        return urls
    }

    private func uniqueURL(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let stem = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(stem) \(n)").appendingPathExtension("mid")
            n += 1
        }
        return candidate
    }

    func revealOutputs(of item: SVQItem) {
        if case .converted(let urls) = item.status {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: Opening

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.svq, .folder]
        panel.message = "Choose SVQ files, or folders containing them."
        panel.prompt = "Add"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }
}
