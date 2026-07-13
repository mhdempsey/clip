import ClipCore
import SwiftUI

struct AlignmentJobView: View {
    @ObservedObject var job: AlignmentJob
    @ObservedObject var model: ClipMacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                StampCover(data: job.source.coverData, caption: nil, width: 62)
                VStack(alignment: .leading, spacing: 5) {
                    SmallCapsLabel(text: job.progressLabel, color: job.stage.isActive ? ClipDesign.terracotta : ClipDesign.inkSecondary)
                    Text(job.title)
                        .font(ClipFont.medium(21))
                        .foregroundStyle(ClipDesign.ink)
                    if !job.source.author.isEmpty {
                        Text(job.source.author)
                            .font(ClipFont.regular(16))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                }
                Spacer()
                if !job.stage.isActive, job.stage != .waiting {
                    Button { model.dismiss(job) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(PaperButtonStyle(role: .quiet))
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .accessibilityLabel("Dismiss \(job.title)")
                }
            }

            switch job.stage {
            case .done:
                doneContent
            case .failed:
                failedContent
            default:
                progressContent
            }
        }
        .clipCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alignment-job-\(job.id.uuidString)")
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClipProgressBar(
                value: job.stage == .downloadingModel ? (job.modelDownloadProgress ?? 0) : job.progress,
                active: job.stage.isActive
            )
            .accessibilityLabel(job.progressLabel)
            HStack(alignment: .firstTextBaseline) {
                Text(job.detail)
                    .font(ClipFont.italic(15))
                    .foregroundStyle(ClipDesign.inkSecondary)
                Spacer()
                if let remaining = job.estimatedRemaining, job.stage == .listening, remaining > 60 {
                    Text(ClipFormatting.remaining(remaining))
                        .font(ClipFont.regular(14))
                        .foregroundStyle(ClipDesign.inkSecondary)
                }
            }
            if job.stage == .downloadingModel {
                Text("This one-time download is about 1.5 GB. Everything runs privately on your Mac.")
                    .font(ClipFont.regular(14))
                    .foregroundStyle(ClipDesign.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var doneContent: some View {
        if let completed = job.completed {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aligned \(ClipFormatting.coverage(completed.coverage)) of the book")
                    .font(ClipFont.medium(23))
                    .foregroundStyle(ClipDesign.ink)
                    .accessibilityIdentifier("coverage-result")

                if completed.coverage < 0.9 {
                    Text("This audio doesn’t fully match this book (\(ClipFormatting.coverage(completed.coverage))) — abridged, or a different edition?")
                        .font(ClipFont.italic(16))
                        .foregroundStyle(ClipDesign.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClipDesign.terracotta.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
                        .accessibilityIdentifier("coverage-caution")
                }

                if !completed.unmatchedSpans.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { job.detailsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: job.detailsExpanded ? "chevron.down" : "chevron.right")
                            Text("Alignment details")
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .quiet))
                    .accessibilityIdentifier("alignment-details")

                    if job.detailsExpanded {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Longest passages without timing")
                                .font(ClipFont.semibold(14))
                                .foregroundStyle(ClipDesign.ink)
                            ForEach(completed.unmatchedSpans.prefix(6)) { span in
                                Text("\(ClipFormatting.timestamp.string(from: span.start) ?? "0:00")–\(ClipFormatting.timestamp.string(from: span.end) ?? "0:00") · \(ClipFormatting.duration.string(from: span.duration) ?? "under a minute")")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(ClipDesign.inkSecondary)
                            }
                        }
                        .padding(.leading, 12)
                    }
                }

                Divider().overlay(ClipDesign.hairline)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(completed.usedICloud
                             ? "In your iCloud — it’ll appear in Clip on your iPhone."
                             : "iCloud isn’t available, so Clip saved this in Documents/Clip.")
                            .font(ClipFont.regular(15))
                            .foregroundStyle(ClipDesign.inkSecondary)
                        Text(completed.bundleURL.lastPathComponent)
                            .font(ClipFont.italic(13))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                    Spacer()
                    Button("Reveal in Finder") { model.reveal(completed.bundleURL) }
                        .buttonStyle(PaperButtonStyle(role: .secondary))
                        .accessibilityIdentifier("reveal-aligned-book")
                }
                HStack {
                    Spacer()
                    Fleuron()
                    Spacer()
                }
            }
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.errorMessage ?? "Clip couldn’t align this pair.")
                .font(ClipFont.medium(18))
                .foregroundStyle(ClipDesign.ink)
            Text(job.detail)
                .font(ClipFont.italic(15))
                .foregroundStyle(ClipDesign.inkSecondary)
            Button("Choose another pair") { model.dismiss(job) }
                .buttonStyle(PaperButtonStyle(role: .secondary))
        }
        .accessibilityIdentifier("alignment-error")
    }
}

