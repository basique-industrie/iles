import Domain
import IslandGeometry
import SwiftUI

struct ComplicationDetailView: View {
    @Bindable var runtime: IslandRuntime
    let complication: ComplicationConfiguration
    let pointerY: CGFloat
    let pointerOnTrailingEdge: Bool

    var body: some View {
        let descriptor = runtime.descriptor(sourceID: complication.sourceID)
        let snapshot = runtime.snapshot(sourceID: complication.sourceID)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                SourceMark(sourceID: complication.sourceID, descriptor: descriptor, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor?.name ?? "Unavailable Source")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(detailSubtitle(descriptor: descriptor))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandPalette.label)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    _ = runtime.refreshSource(complication.sourceID)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandPalette.label)
                        .frame(width: 24, height: 24)
                        .background(IslandChrome.fieldFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh \(descriptor?.name ?? "source")")
            }

            if let snapshot, !snapshot.values.isEmpty {
                metricRows(snapshot: snapshot, descriptor: descriptor)
            } else {
                Text(snapshot?.errorDescription ?? "No data yet. Refresh the source or finish its setup in Settings.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(pointerOnTrailingEdge ? .trailing : .leading, IslandMetrics.providerWindowPointerWidth)
        .frame(
            width: IslandMetrics.providerWindowWidth,
            height: IslandMetrics.providerWindowHeight - IslandMetrics.providerWindowBodyInset,
            alignment: .topLeading
        )
        .background {
            PopoverBubbleShape(
                pointerY: pointerY,
                pointerOnTrailingEdge: pointerOnTrailingEdge
            )
            .fill(IslandPalette.popover)
        }
        .overlay {
            PopoverBubbleShape(
                pointerY: pointerY,
                pointerOnTrailingEdge: pointerOnTrailingEdge
            )
            .stroke(IslandChrome.controlBorder, lineWidth: 1)
        }
        .frame(width: IslandMetrics.providerWindowWidth, height: IslandMetrics.providerWindowHeight)
        .onHover { runtime.setPointerOverPopover($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(descriptor?.name ?? "Complication") details")
    }

    private func metricRows(
        snapshot: SourceSnapshot,
        descriptor: ComplicationSourceDescriptor?
    ) -> some View {
        let ids = complication.metricIDs.isEmpty ? Array(snapshot.values.keys.prefix(2)) : complication.metricIDs
        let resolvedSlots = runtime.resolvedSlots(for: complication)
        let recipe = complication.recipeID.flatMap { recipeID in
            descriptor?.complications.first { $0.id == recipeID }
        }
        let missingMetricNames = ids.compactMap { metricID -> String? in
            guard resolvedSlots.first(where: { $0.metricID == metricID })?.value == nil,
                  snapshot.values[metricID] == nil
            else { return nil }
            return descriptor?.metricName(for: metricID)
                ?? ComplicationMetricDescriptor.fallbackName(for: metricID)
        }
        return VStack(spacing: 9) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, metricID in
                let metric = descriptor?.metrics.first { $0.id == metricID }
                let value = resolvedSlots.first { $0.metricID == metricID }?.value ?? snapshot.values[metricID]
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(index == 0
                            ? (recipe?.shortName
                                ?? metric?.name
                                ?? ComplicationMetricDescriptor.fallbackName(for: metricID))
                            : (metric?.name ?? ComplicationMetricDescriptor.fallbackName(for: metricID)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(IslandPalette.label)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(value?.displayText ?? missingValueLabel(snapshot: snapshot))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                    if let progress = value?.progress {
                        QuotaBar(percentUsed: progress * 100, color: sourceAccent)
                    }
                }
            }
            if !missingMetricNames.isEmpty, snapshot.errorDescription == nil {
                Label(
                    "\(descriptor?.name ?? "This source") isn't reporting \(missingMetricNames.joined(separator: " + ")) right now.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(IslandPalette.label)
                .lineLimit(2)
            }
            if let error = snapshot.errorDescription {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandPalette.label)
                    .lineLimit(2)
            }
            if runtime.quality(for: complication) == .stale {
                Label("Showing the last known value", systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandPalette.label)
            }
        }
    }

    private func missingValueLabel(snapshot: SourceSnapshot) -> String {
        snapshot.errorDescription == nil && snapshot.availability.state == .available
            ? "Not reported"
            : "Unavailable"
    }

    private func detailSubtitle(descriptor: ComplicationSourceDescriptor?) -> String {
        let recipeName = complication.recipeID.flatMap { recipeID in
            descriptor?.complications.first { $0.id == recipeID }?.shortName
        }
        let metricName = complication.metricIDs.first.map { metricID in
            descriptor?.metricName(for: metricID)
                ?? ComplicationMetricDescriptor.fallbackName(for: metricID)
        }
        let contentName = recipeName ?? metricName ?? "Complication"
        return "\(contentName) · \(complication.family.displayName)"
    }

    private var sourceAccent: Color {
        ComplicationSourceStyle.accent(
            sourceID: complication.sourceID,
            descriptor: runtime.descriptor(sourceID: complication.sourceID)
        )
    }
}

extension ComplicationFamily {
    var displayName: String {
        switch self {
        case .ring: "Ring"
        case .dualRing: "Dual Ring"
        case .value: "Value"
        case .status: "Status"
        case .activity: "Activity"
        case .countdown: "Countdown"
        case .trend: "Trend"
        case .summary: "Summary"
        case .cluster: "Trio Ring"
        }
    }
}

struct QuotaBar: View {
    let percentUsed: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandPalette.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(percentUsed / 100, 0), 1))))
            }
        }
        .frame(height: 4)
    }
}
