import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A MIDI file made when something is dragged out of the app: the Finder saves it, and a DAW such
/// as Logic Pro imports it as MIDI regions.
///
/// The recipe is the one V-Synth Patch Composer arrived at after testing with the Finder and Logic:
/// a per-row `.draggable` with a `FileRepresentation`, the file written into a folder of its own
/// so two drags with the same name never collide, and the name given through
/// `.suggestedFileName` without an extension (the receiver adds the type's own, ".midi"; a
/// FileRepresentation's own file name is ignored, and "….mid" arrived as "….mid.midi").
struct MIDIDragFile {
    /// The file name without an extension.
    let name: String
    let data: Data

    init(name: String, data: Data) {
        self.name = AppModel.safeFileName(name)
        self.data = data
    }

    /// Writes the file into a new folder in the temporary directory.
    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIDI Drag \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("mid")
        try data.write(to: url)
        return url
    }

    /// For macOS 13, where `.suggestedFileName` can't name a Transferable's file.
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: UTType.midi.identifier, fileOptions: [],
                                            visibility: .all) { completion in
            do { completion(try write(), false, nil) } catch { completion(nil, false, error) }
            return nil
        }
        return provider
    }
}

@available(macOS 14, *)
extension MIDIDragFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .midi) { file in
            SentTransferredFile(try file.write())
        }
        .suggestedFileName { $0.name }
    }
}

extension View {
    /// Lets the view be dragged to the Finder or a DAW as a MIDI file. `make` runs when a drag
    /// begins, not when the view is drawn.
    ///
    /// In a List, per-row `.draggable` leaves the list's own selection working; `.onDrag` and
    /// SwiftUI's drag containers took clicks away from it on macOS 26 (found in V-Synth Patch
    /// Composer), so `.onDrag` is only the macOS 13 fallback.
    @ViewBuilder
    func midiDrag(isEnabled: Bool = true, _ make: @escaping () -> MIDIDragFile) -> some View {
        if !isEnabled {
            self
        } else if #available(macOS 14, *) {
            draggable(make())
        } else {
            onDrag { make().itemProvider() }
        }
    }
}
