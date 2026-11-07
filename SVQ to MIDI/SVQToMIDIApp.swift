import SwiftUI

@main
struct SVQToMIDIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("SVQ to MIDI", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
            CommandGroup(replacing: .newItem) {
                Button("Add SVQ Files…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Convert All…") { model.convertWithPanel(model.convertibleItems) }
                    .keyboardShortcut("e")
                    .disabled(model.convertibleItems.isEmpty)
                Button("Convert Selected…") { model.convertWithPanel(model.selectedItems) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.selectedItems.isEmpty)
            }
        }

        Window("About SVQ to MIDI", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            OptionsView()
                .environmentObject(model)
                .padding(20)
                .frame(width: 460)
        }
    }
}

/// Receives files opened from the Finder or dropped on the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.add(urls: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
