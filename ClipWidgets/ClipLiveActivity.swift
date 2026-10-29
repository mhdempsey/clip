import ActivityKit
import AppIntents
import ClipCore
import SwiftUI
import UIKit
import WidgetKit

struct ClipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClipActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(ClipDesign.surface)
                .activitySystemActionForegroundColor(ClipDesign.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "scissors")
                        .foregroundStyle(ClipDesign.terracotta)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Text(context.attributes.author).font(.caption).foregroundStyle(ClipDesign.inkSecondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            playPauseButton(context.state.isPlaying)
                            clipButton(context.state.windowSeconds)
                        }
                        if let feedback = context.state.clipFeedback { feedbackLabel(feedback) }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.clipFeedback?.outcome == .saved ? "checkmark.circle.fill" : "scissors").foregroundStyle(ClipDesign.terracotta)
            } compactTrailing: {
                Text("\(context.state.windowSeconds)s")
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(ClipDesign.ink)
            } minimal: {
                Image(systemName: context.state.clipFeedback?.outcome == .saved ? "checkmark.circle.fill" : "scissors").foregroundStyle(ClipDesign.terracotta)
            }
            .keylineTint(ClipDesign.terracotta)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<ClipActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                WidgetCover(bookID: context.attributes.bookId)
                    .frame(width: 48, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.attributes.title)
                        .font(ClipDesign.mediumFont(size: 17))
                        .foregroundStyle(ClipDesign.ink)
                        .lineLimit(1)
                    Text(context.attributes.author)
                        .font(ClipDesign.bodyFont(size: 14))
                        .foregroundStyle(ClipDesign.inkSecondary)
                        .lineLimit(1)
                    ProgressView(value: context.state.elapsedS, total: max(1, context.state.durationS))
                        .tint(ClipDesign.terracotta)
                }
                playPauseButton(context.state.isPlaying)
                clipButton(context.state.windowSeconds)
            }
            if let feedback = context.state.clipFeedback { feedbackLabel(feedback) }
        }
        .padding(12)
    }

    private func playPauseButton(_ isPlaying: Bool) -> some View {
        Button(intent: PlayPauseIntent()) {
            Image(systemName: isPlaying ? "pause" : "play")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(ClipDesign.ink)
                .overlay { Circle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private func clipButton(_ window: Int) -> some View {
        Button(intent: ClipIntent()) {
            Label("Clip \(window)s", systemImage: "scissors")
                .font(ClipDesign.semiboldFont(size: 14))
                .padding(.horizontal, 11)
                .frame(height: 44)
                .foregroundStyle(ClipDesign.paper)
                .background(ClipDesign.terracotta)
                .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clip \(window) seconds")
        .accessibilityIdentifier("lockscreen.clip")
    }

    private func feedbackLabel(_ feedback: ClipActivityFeedback) -> some View {
        HStack(spacing: 4) {
            Image(systemName: feedback.outcome == .saved ? "checkmark.circle.fill" : "exclamationmark.circle")
            Text(feedback.message).fixedSize(horizontal: true, vertical: false)
            if feedback.outcome == .saved { Text(feedback.date, style: .relative).monospacedDigit() }
        }
        .font(.caption2)
        .foregroundStyle(feedback.outcome == .saved ? ClipDesign.accent : ClipDesign.terracotta)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lockscreen.clip-feedback")
    }
}

private struct WidgetCover: View {
    let bookID: String

    var body: some View {
        Group {
            if let path = WidgetClipStore().coverImagePath(bookID: bookID),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    ClipDesign.paper
                    Image(systemName: "book.closed").foregroundStyle(ClipDesign.inkSecondary)
                }
            }
        }
        .clipped()
        .overlay { Rectangle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth) }
    }
}
