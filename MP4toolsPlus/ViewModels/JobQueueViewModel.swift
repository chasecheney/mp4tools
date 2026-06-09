//
//  JobQueueViewModel.swift
//  MP4tools+
//
//  Coordinates queued jobs, runs them sequentially against FFmpegService,
//  and surfaces live progress + user-friendly error alerts to the UI.
//

import Foundation
import SwiftUI

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
                 externalSubtitle: URL? = nil) {
        let job = Job(source: source, operation: operation, outputURL: output)
        jobs.append(job)
        startIfIdle(job: job,
                    selectedTracks: selectedTracks,
                    externalSubtitle: externalSubtitle)
    }

    func cancelAll() {
        runningTask?.cancel()
        for job in jobs where !job.status.isTerminal {
            job.status = .cancelled
        }
    }

    private func startIfIdle(job: Job,
                             selectedTracks: [MediaTrack],
                             externalSubtitle: URL?) {
        // Simple sequential queue: only launch when nothing is running.
        guard runningTask == nil else { return }
        runNext(selectedTracks: selectedTracks, externalSubtitle: externalSubtitle)
    }

    private func runNext(selectedTracks: [MediaTrack], externalSubtitle: URL?) {
        guard let job = jobs.first(where: {
            if case .queued = $0.status { return true } else { return false }
        }) else {
            runningTask = nil
            return
        }

        job.status = .running(progress: 0)
        runningTask = Task {
            do {
                try await engine.execute(
                    source: job.source,
                    operation: job.operation,
                    selectedTracks: selectedTracks,
                    output: job.outputURL,
                    externalSubtitle: externalSubtitle
                ) { fraction in
                    Task { @MainActor in
                        if case .running = job.status {
                            job.status = .running(progress: fraction)
                        }
                    }
                }
                job.status = .completed(outputURL: job.outputURL)
            } catch is CancellationError {
                job.status = .cancelled
            } catch {
                job.status = .failed(message: error.localizedDescription)
                alertMessage = error.localizedDescription
            }
            runningTask = nil
            // Drain any remaining queued jobs.
            runNext(selectedTracks: selectedTracks, externalSubtitle: externalSubtitle)
        }
    }
}
