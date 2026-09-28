import AppKit
import Domain
import IslandGeometry
import SwiftUI

struct ComplicationDetailView: View {
    @Bindable var runtime: IslandRuntime
    let complication: ComplicationConfiguration
    let pointerY: CGFloat
    let pointerOnTrailingEdge: Bool

    static func preferredHeight(runtime: IslandRuntime, complication: ComplicationConfiguration) -> CGFloat {
        preferredHeight(snapshot: runtime.snapshot(sourceID: complication.sourceID), metricIDs: complication.metricIDs)
    }

    static func preferredHeight(snapshot: SourceSnapshot?, metricIDs: [String]) -> CGFloat {
        guard let snapshot else { return 160 }
        let groups = snapshot.focusedQuotaGroups(matching: metricIDs)
        // Generic details render the selected metrics, not the source's whole
        // catalog. Mac Health can expose ten metrics behind a one-value widget.
        let count = groups.isEmpty
            ? (metricIDs.isEmpty ? min(snapshot.values.count, 2) : metricIDs.count)
            : Set(groups.flatMap(\.metricIDs) + metricIDs).count
        return count <= 1 ? 160 : (count == 2 ? 204 : IslandMetrics.providerWindowHeight)
    }

    private var panelHeight: CGFloat { Self.preferredHeight(runtime: runtime, complication: complication) }

    var body: some View {
        let descriptor = runtime.descriptor(sourceID: complication.sourceID)
        let snapshot = runtime.snapshot(sourceID: complication.sourceID)
        let glanceBrand = HarnaisGlance.resolvedBrand(
            sourceID: complication.sourceID,
            metricIDs: complication.metricIDs,
            descriptor: descriptor
        )
        let focusedGroups = snapshot.map {
            $0.focusedQuotaGroups(matching: complication.metricIDs)
        } ?? []

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                SourceMark(
                    sourceID: complication.sourceID,
                    descriptor: descriptor,
                    metricIDs: complication.metricIDs,
                    size: 18,
                    tint: NSColor(sourceAccent).blended(withFraction: 0.5, of: .white) ?? .white
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(glanceBrand?.title ?? descriptor?.name ?? "Unavailable Source")
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
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(runtime.provider(id: complication.sourceID)?.isSyncing == true)
                .accessibilityLabel("Refresh source")
                .help("Refresh usage")
                Button {
                    runtime.dismissWindow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandPalette.label)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close details")
                .help("Close details · Escape")
            }

            if let snapshot, !focusedGroups.isEmpty {
                groupedQuotaRows(
                    groups: focusedGroups,
                    snapshot: snapshot,
                    descriptor: descriptor
                )
            } else if let snapshot, !snapshot.values.isEmpty {
                ScrollView {
                    metricRows(snapshot: snapshot, descriptor: descriptor)
                }
            } else {
                Text(snapshot?.errorDescription ?? "No data yet. Refresh the source or finish its setup in Settings.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            HStack {
                freshnessLabel(snapshot: snapshot)
                Spacer()
                Button {
                    runtime.editSelectedWidget()
                } label: {
                    Label("Edit widget", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(pointerOnTrailingEdge ? .trailing : .leading, IslandMetrics.providerWindowPointerWidth)
        .frame(
            width: IslandMetrics.providerWindowWidth,
            height: panelHeight - IslandMetrics.providerWindowBodyInset,
            alignment: .topLeading
        )
        .background {
            PopoverBubbleShape(
                pointerY: pointerY,
                pointerOnTrailingEdge: pointerOnTrailingEdge
            )
            .fill(IslandPalette.popover)
        }
        .frame(width: IslandMetrics.providerWindowWidth, height: panelHeight)
        .onHover { runtime.setPointerOverPopover($0) }
        .onExitCommand { runtime.dismissWindow() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(glanceBrand?.title ?? descriptor?.name ?? "Complication") details")
    }

    @ViewBuilder
    private func freshnessLabel(snapshot: SourceSnapshot?) -> some View {
        if runtime.provider(id: complication.sourceID)?.isSyncing == true {
            Text("Refreshing…")
                .font(.system(size: 10))
                .foregroundStyle(IslandPalette.label)
        } else if let snapshot, !snapshot.values.isEmpty {
            HStack(spacing: 4) {
                if runtime.quality(for: complication) == .stale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                Text("Updated \(snapshot.capturedAt, style: .time)")
            }
            .font(.system(size: 10))
            .foregroundStyle(IslandPalette.label)
            .help("Usage timestamp: \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
        } else {
            Text("No usage data")
                .font(.system(size: 10))
                .foregroundStyle(IslandPalette.label)
        }
    }

    private func groupedQuotaRows(
        groups: [SourceQuotaGroup],
        snapshot: SourceSnapshot,
        descriptor: ComplicationSourceDescriptor?
    ) -> some View {
        let resolvedSlots = runtime.resolvedSlots(for: complication)
        let selectedIDs = complication.metricIDs
        let selectedSet = Set(selectedIDs)
        let extraGroups = groups.compactMap { group -> SourceQuotaGroup? in
            let extraIDs = group.metricIDs.filter { !selectedSet.contains($0) }
            guard !extraIDs.isEmpty else { return nil }
            return SourceQuotaGroup(title: group.title, metricIDs: extraIDs)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedIDs, id: \.self) { metricID in
                    groupedQuotaRow(
                        metricID: metricID,
                        snapshot: snapshot,
                        descriptor: descriptor,
                        accent: sourceAccent,
                        resolvedSlots: resolvedSlots
                    )
                }
                if !selectedIDs.isEmpty, !extraGroups.isEmpty {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    Text("More usage")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandPalette.label)
                }
                ForEach(extraGroups, id: \.title) { group in
                    let groupAccent = ComplicationSourceStyle.accent(
                        sourceID: complication.sourceID,
                        descriptor: descriptor,
                        metricIDs: group.metricIDs
                    )
                    if extraGroups.count > 1, let title = UsageQuota.privacySafeTitle(group.title) {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IslandPalette.label)
                    }
                    ForEach(group.metricIDs, id: \.self) { metricID in
                        groupedQuotaRow(
                            metricID: metricID,
                            snapshot: snapshot,
                            descriptor: descriptor,
                            accent: groupAccent,
                            resolvedSlots: resolvedSlots
                        )
                    }
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
    }

    private func groupedQuotaRow(
        metricID: String,
        snapshot: SourceSnapshot,
        descriptor: ComplicationSourceDescriptor?,
        accent: Color,
        resolvedSlots: [(metricID: String, value: ComplicationValue)]
    ) -> some View {
        let metric = descriptor?.metrics.first { $0.id == metricID }
        let slotIndex = complication.metricIDs.firstIndex(of: metricID)
        let mode = slotIndex.map { complication.valueMode(at: $0) } ?? .used
        let value = resolvedSlots.first { $0.metricID == metricID }?.value
            ?? snapshot.values[metricID].map { ComplicationTransformEngine.present($0, as: mode) }
        let name = metric?.name ?? ComplicationMetricDescriptor.fallbackName(for: metricID)
        let caption = HarnaisGlance.rowLabel(
            sourceID: complication.sourceID,
            metricID: metricID,
            metricName: name
        )
        let isUsage = metric?.kind == .gauge && metric?.policy.format == .percentage
        let modeCaption = isUsage ? (mode == .remaining ? " · Remaining" : " · Used") : ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(caption)\(modeCaption)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(value?.displayText ?? "—")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            if let progress = value?.progress {
                QuotaBar(percentUsed: progress * 100, color: slotIndex.map { usageStyle.color(at: $0, value: value).opacity(usageStyle.intensity(at: $0)) } ?? accent)
            }
        }
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
                        Text(rowCaption(
                            index: index,
                            metricID: metricID,
                            metric: metric,
                            recipe: recipe
                        ))
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
                        QuotaBar(percentUsed: progress * 100, color: usageStyle.color(at: index, value: value).opacity(usageStyle.intensity(at: index)))
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

    private func rowCaption(
        index: Int,
        metricID: String,
        metric: ComplicationMetricDescriptor?,
        recipe: ComplicationRecipe?
    ) -> String {
        let name = metric?.name ?? ComplicationMetricDescriptor.fallbackName(for: metricID)
        if HarnaisGlance.applies(to: complication.sourceID) {
            return HarnaisGlance.rowLabel(
                sourceID: complication.sourceID,
                metricID: metricID,
                metricName: name
            )
        }
        if index == 0 {
            return recipe?.shortName ?? name
        }
        return name
    }

    private func missingValueLabel(snapshot: SourceSnapshot) -> String {
        snapshot.errorDescription == nil && snapshot.availability.state == .available
            ? "Not reported"
            : "Unavailable"
    }

    private func detailSubtitle(descriptor: ComplicationSourceDescriptor?) -> String {
        if let account = HarnaisGlance.accountLabel(
            sourceID: complication.sourceID,
            metricIDs: complication.metricIDs,
            descriptor: descriptor
        ) {
            return account
        }
        let metricID = complication.metricIDs.first
        let metricName = metricID.map { id in
            descriptor?.metricName(for: id)
                ?? ComplicationMetricDescriptor.fallbackName(for: id)
        }
        if let harnaisSubtitle = HarnaisGlance.detailSubtitle(
            sourceID: complication.sourceID,
            metricIDs: complication.metricIDs,
            metricName: metricName,
            descriptor: descriptor
        ) {
            return harnaisSubtitle
        }
        let recipeName = complication.recipeID.flatMap { recipeID in
            descriptor?.complications.first { $0.id == recipeID }?.shortName
        }
        let contentName = recipeName ?? metricName ?? "Complication"
        return "\(contentName) · \(complication.family.displayName)"
    }

    private var usageStyle: ComplicationUsageStyle {
        ComplicationUsageStyle(complication: complication, descriptor: runtime.descriptor(sourceID: complication.sourceID))
    }

    private var sourceAccent: Color {
        ComplicationSourceStyle.accent(
            sourceID: complication.sourceID,
            descriptor: runtime.descriptor(sourceID: complication.sourceID),
            metricIDs: complication.metricIDs
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let percentUsed: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(ComplicationUsageStyle.clampedProgress(percentUsed / 100)))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percentUsed)
    }
}
