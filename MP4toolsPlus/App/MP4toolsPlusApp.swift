//
//  MP4toolsPlusApp.swift
//  MP4tools+
//
//  App entry point. Configures the main window and a dedicated Settings
//  scene (native macOS Settings window via ⌘,).
//

import SwiftUI

@main
struct MP4toolsPlusApp: App {
    // A single source of truth for app-wide state, injected into the
    // environment so any view can observe job progress / library changes.
    @StateObject private var library = LibraryViewModel()
    @StateObject private var presetStore = PresetStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(presetStore)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            // Replace the default "New" with an "Add Media…" command.
            CommandGroup(replacing: .newItem) {
                Button("Add Media…") { library.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        // Native macOS Settings window.
        Settings {
            SettingsView()
                .environmentObject(presetStore)
        }
    }
}
