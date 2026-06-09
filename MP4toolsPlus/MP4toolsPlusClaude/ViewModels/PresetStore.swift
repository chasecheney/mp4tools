//
//  PresetStore.swift
//  MP4tools+
//
//  Owns the user's presets and persists them to UserDefaults. Built-in
//  presets are merged in on first launch.
//

import Foundation
import Combine

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []

    private let defaultsKey = "mp4tools.presets.v1"

    init() { load() }

    func add(_ preset: Preset) {
        presets.append(preset)
        save()
    }

    func update(_ preset: Preset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        save()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data),
           !decoded.isEmpty {
            presets = decoded
        } else {
            presets = Preset.builtIns   // seed on first launch
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
