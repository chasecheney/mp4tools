//
//  JobQueueViewModel.swift
//  MP4tools+
//
//  Coordinates queued jobs, runs them sequentially against FFmpegService,
//  and surfaces live progress + user-friendly error alerts to the UI.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class JobQueueViewModel: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    @Published var alertMessage: String?

    private let engine = FFmpegService()
    private var runningTask: Task<Void, Never>?

    /// Enqueue a job and start the queue if idle.
    func enqueue(source: MediaFile,
                 operation: Operation,
                 selectedTracks: [MediaTrack],
                 output: URL,
                 externalSubtitles: [ExternalSubtitle] = []) {
        let job = Job(source: source, operation: operation, outputURL: output)
        jobs.append(job)
        startIfIdle(job: job,
                    selectedTracks: selectedTracks,
                    externalSubtitles: externalSubtitles)
    }

    func cancelAll() {
        runningTask?.cancel()
        for job in jobs where !job.status.isTerminal {
            job.status = .cancelled
        }
    }

    private func startIfIdle(job: Job,
                             selectedTracks: [MediaTrack],
                             externalSubtitles: [ExternalSubtitle]) {
        // Simple sequential queue: only launch when nothing is running.
        guard runningTask == nil else { return }
        runNext(selectedTracks: selectedTracks, externalSubtitles: externalSubtitles)
    }

    private func runNext(selectedTracks: [MediaTrack], externalSubtitles: [ExternalSubtitle]) {
        guard let job = jobs.first(where: {
            if case .queued = $0.status { return true } else { return false }
        }) else {
            runningTask = nil
            return
        }

        job.status = .running(progress: 0)
        runningTask = Task {
            do {
                let finalURL = try await engine.execute(
                    source: job.source,
                    operation: job.operation,
                    selectedTracks: selectedTracks,
                    output: job.outputURL,
                    externalSubtitles: externalSubtitles
                ) { fraction in
                    Task { @MainActor in
                        if case .running = job.status {
                            job.status = .running(progress: fraction)
                        }
                    }
                }
                // Reflect the path actually written (may carry a -2/-3 suffix).
                job.status = .completed(outputURL: finalURL)
            } catch is CancellationError {
                job.status = .cancelled
            } catch {
                job.status = .failed(message: error.localizedDescription)
                alertMessage = error.localizedDescription
            }
            runningTask = nil
            // Drain any remaining queued jobs.
            runNext(selectedTracks: selectedTracks, externalSubtitles: externalSubtitles)
        }
    }
}
