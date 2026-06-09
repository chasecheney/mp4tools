//
//  JobTrayView.swift
//  MP4tools+
//
//  A persistent bottom tray showing queued / running / finished jobs with
//  live progress bars and a reveal-in-Finder action on completion.
//

import SwiftUI
import AppKit

struct JobTrayView: View {
    @EnvironmentObject private var jobQueue: JobQueueViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jobs").font(.headline)
                Spacer()
                if jobQueue.jobs.contains(where: { !$0.status.isTerminal }) {
                    Button("Cancel All") { jobQueue.cancelAll() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if jobQueue.jobs.isEmpty {
                Text("No jobs yet. Convert a file to get started.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(jobQueue.jobs) { job in
                    JobRow(job: job)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct JobRow: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(job.source.displayName)
                    .lineLimit(1).truncationMode(.middle)
                Text(job.operation.label)
                    .font(.caption).foregroundStyle(.secondary)
                if case .running(let p) = job.status {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                }
                if case .failed(let m) = job.status {
                    Text(m).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            if case .completed(let url) = job.status {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
