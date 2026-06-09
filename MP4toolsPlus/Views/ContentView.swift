//
//  ContentView.swift
//  MP4tools+
//
//  Top-level NavigationSplitView: a sidebar of imported files, a detail pane
//  with track selection + actions, and a bottom job tray.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var presetStore: PresetStore
    @StateObject private var jobQueue = JobQueueViewModel()

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                if let file = library.selectedFile {
                    DetailView(file: file)
                        .environmentObject(jobQueue)
                } else {
                    DropZoneView()
                }
                Divider()
                JobTrayView()
                    .environmentObject(jobQueue)
                    .frame(height: 150)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    library.presentOpenPanel()
                } label: {
                    Label("Add Media", systemImage: "plus")
                }
                .help("Add a video file")

                Button {
                    jobQueue.cancelAll()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .help("Cancel all running jobs")
            }
        }
        // Accept drops anywhere in the window.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { jobQueue.alertMessage != nil },
                                    set: { if !$0 { jobQueue.alertMessage = nil } })) {
            Button("OK", role: .cancel) { jobQueue.alertMessage = nil }
        } message: {
            Text(jobQueue.alertMessage ?? "")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { library.importFiles(urls) }
        }
        return true
    }
}
