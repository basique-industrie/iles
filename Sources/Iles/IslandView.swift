import AppKit
import Domain
import IslandGeometry
import SwiftUI

/// One configured island. The same renderer is used by the floating panel and
/// the live Settings preview so the editor cannot drift from the real result.
struct IslandView: View {
    @Bindable var runtime: IslandRuntime
    let islandID: UUID
    var maxHeight: CGFloat
    var interactive = true
    var selectedComplicationID: UUID? = nil

    var body: some View {
        if let island = runtime.workspaceStore.island(id: islandID) {
            content(island)
        }
    }

    private func content(_ island: IslandConfiguration) -> some View {
        let capacity = IslandMetrics.maxProviderCount(forHeight: maxHeight)
        let complications = Array(island.visibleComplications.prefix(capacity))
        let height = min(
            IslandMetrics.height(forProviderCount: complications.count),
            maxHeight
        )
        let mirrored = island.placement.edge == .leading

        return Group {
            if complications.isEmpty {
                emptyState
            } else {
                VStack(spacing: IslandMetrics.itemSpacing) {
                    ForEach(complications) { complication in
                        ComplicationSlotView(
                            complication: complication,
                            descriptor: runtime.descriptor(sourceID: complication.sourceID),
                            values: runtime.values(for: complication),
                            sourceError: runtime.snapshot(sourceID: complication.sourceID)?.errorDescription,
                            quality: runtime.quality(for: complication),
                            trendDirection: runtime.trendDirection(for: complication),
                            isSyncing: runtime.provider(id: complication.sourceID)?.isSyncing == true,
                            isSelected: selectedComplicationID == complication.id
                                || runtime.selection == ComplicationSelection(
                                    islandID: islandID,
                                    complicationID: complication.id
                                )
                        )
                        .onHover { hovering in
                            guard interactive, hovering else { return }
                            runtime.hoverSelect(islandID: islandID, complicationID: complication.id)
                        }
                        .onTapGesture {
                            guard interactive else { return }
                            runtime.handleTap(islandID: islandID, complication: complication)
                        }
                    }
                }
                .padding(.vertical, IslandMetrics.topPadding)
            }
        }
        .padding(.horizontal, IslandMetrics.leadingInset)
        .frame(width: IslandMetrics.width, height: height)
        .background {
            IslandShape(mirrored: mirrored)
                .fill(IslandPalette.surface)
        }
        .contentShape(IslandShape(mirrored: mirrored))
        .accessibilityElement(children: interactive ? .contain : .ignore)
        .accessibilityLabel(island.name)
        .onHover { hovering in
            guard interactive else { return }
            runtime.setPointerOverIsland(islandID, hovering)
        }
        .contextMenu {
            if interactive {
                Button("Refresh All Sources") { runtime.refreshNow() }
                Button("Edit \(island.name)…") {
                    runtime.workspaceStore.selectIsland(islandID)
                    NotificationCenter.default.post(name: .showIslandSettings, object: nil)
                }
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private var emptyState: some View {
        IslandPlusAffordance {
            runtime.workspaceStore.selectIsland(islandID)
            NotificationCenter.default.post(name: .showIslandSettings, object: nil)
        }
    }
}

/// Edge pill shown when the workspace has no islands.
struct EmptyWorkspaceIslandView: View {
    var edge: IslandEdge = .trailing

    var body: some View {
        let mirrored = edge == .leading
        IslandPlusAffordance {
            NotificationCenter.default.post(name: .showIslandSettings, object: nil)
        }
        .padding(.horizontal, IslandMetrics.leadingInset)
        .frame(width: IslandMetrics.width, height: IslandMetrics.height(forProviderCount: 0))
        .background {
            IslandShape(mirrored: mirrored)
                .fill(IslandPalette.surface)
        }
        .contentShape(IslandShape(mirrored: mirrored))
        .accessibilityLabel("Add an island")
        .accessibilityAddTraits(.isButton)
    }
}

private struct IslandPlusAffordance: View {
    let action: () -> Void

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(IslandPalette.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                guard !NSEvent.modifierFlags.contains(.command) else { return }
                action()
            }
    }
}

struct ComplicationSlotView: View {
    let complication: ComplicationConfiguration
    let descriptor: ComplicationSourceDescriptor?
    let values: [ComplicationValue]
    let sourceError: String?
    var quality: ComplicationSampleQuality = .live
    var trendDirection: ComplicationTrendDirection = .unknown
    var isSyncing = false
    var isSelected = false
    var renderScale: CGFloat = 1
    var reservesHiddenLabelSpace = true

    var body: some View {
        VStack(spacing: scaled(IslandMetrics.ringLabelSpacing)) {
            graphic
            if includesValueLabel {
                valueLabel
            }
        }
        .frame(height: scaled(includesValueLabel ? IslandMetrics.itemHeight : IslandMetrics.ringSize))
        .privacySensitive()
        .opacity(quality == .stale ? 0.78 : (sourceError == nil || !values.isEmpty ? 1 : 0.62))
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor?.name ?? "Unavailable complication")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            sourceError
                ?? (complication.tapAction == .none ? "" : "Click to perform the configured action")
        )
        .accessibilityAddTraits(complication.tapAction == .none ? [] : .isButton)
    }

    private var includesValueLabel: Bool {
        complication.labelStyle != .hidden || reservesHiddenLabelSpace
    }

    private var graphic: some View {
        ZStack {
            familyGraphic
            sourceMark
            syncIndicator
            qualityIndicator
        }
        .frame(width: scaled(IslandMetrics.ringSize), height: scaled(IslandMetrics.ringSize))
        .brightness(isSelected ? 0.12 : 0)
    }

    @ViewBuilder
    private var sourceMark: some View {
        if complication.family != .cluster {
            SourceMark(
                sourceID: complication.sourceID,
                descriptor: descriptor,
                metricID: usesSourceIdentity ? nil : complication.metricIDs.first,
                size: scaled(IslandMetrics.markSize)
            )
            .opacity(isSyncing ? 0.4 : 1)
        }
    }

    @ViewBuilder
    private var syncIndicator: some View {
        if isSyncing {
            ProgressView()
                .controlSize(renderScale >= 1.5 ? .small : .mini)
                .tint(.white)
        }
    }

    @ViewBuilder
    private var qualityIndicator: some View {
        if quality == .stale {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: scaled(7), weight: .bold))
                .foregroundStyle(IslandPalette.label)
                .offset(x: scaled(14), y: scaled(-14))
        } else if quality == .unavailable || quality == .failed {
            Image(systemName: "exclamationmark")
                .font(.system(size: scaled(7), weight: .bold))
                .foregroundStyle(quality == .failed ? Color.red : IslandPalette.label)
                .frame(width: scaled(11), height: scaled(11))
                .background(Color.black.opacity(0.82), in: Circle())
                .offset(x: scaled(14), y: scaled(-14))
        }
    }

    @ViewBuilder
    private var valueLabel: some View {
        if complication.labelStyle != .hidden {
            Text(label)
                .font(.system(size: scaled(9), weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(
                    width: scaled(IslandMetrics.width - 4),
                    height: scaled(IslandMetrics.ringLabelHeight)
                )
        } else {
            Color.clear.frame(height: scaled(IslandMetrics.ringLabelHeight))
        }
    }

    @ViewBuilder
    private var familyGraphic: some View {
        switch complication.family {
        case .ring:
            ring(
                progress: values.first?.progress ?? 0,
                color: semanticColor(index: 0),
                diameter: scaled(IslandMetrics.ringSize),
                trackWidth: scaled(IslandMetrics.ringStroke),
                strokeWidth: scaled(IslandMetrics.accentStroke)
            )
        case .dualRing:
            ZStack {
                ring(
                    progress: values.first?.progress ?? 0,
                    color: semanticColor(index: 0),
                    diameter: scaled(IslandMetrics.ringSize),
                    trackWidth: scaled(IslandMetrics.ringStroke),
                    strokeWidth: scaled(IslandMetrics.accentStroke)
                )
                ring(
                    progress: values.dropFirst().first?.progress ?? 0,
                    color: semanticColor(index: 1).opacity(complication.slotTints.indices.contains(1) ? 1 : 0.72),
                    diameter: scaled(IslandMetrics.dualRingInnerSize),
                    trackWidth: scaled(IslandMetrics.dualRingInnerStroke),
                    strokeWidth: scaled(IslandMetrics.dualRingInnerAccentStroke)
                )
            }
        case .value:
            RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                .fill(IslandPalette.iconWell)
                .overlay {
                    RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                        .strokeBorder(IslandChrome.controlBorder, lineWidth: scaled(1))
                }
        case .status:
            Circle()
                .fill(IslandPalette.iconWell)
                .overlay {
                    Circle()
                        .strokeBorder(statusColor, lineWidth: scaled(2))
                }
        case .activity:
            Circle()
                .stroke(IslandPalette.track, lineWidth: scaled(IslandMetrics.ringStroke))
                .overlay {
                    Circle()
                        .trim(from: 0.08, to: activityArcEnd)
                        .stroke(
                            statusColor,
                            style: StrokeStyle(lineWidth: scaled(IslandMetrics.accentStroke), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .animation(.easeInOut(duration: 0.2), value: activityArcEnd)
        case .countdown:
            Circle()
                .stroke(IslandPalette.track, lineWidth: scaled(IslandMetrics.ringStroke))
                .overlay {
                    Circle()
                        .trim(from: 0.08, to: 0.82)
                        .stroke(
                            accent,
                            style: StrokeStyle(lineWidth: scaled(IslandMetrics.accentStroke), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(accent)
                        .frame(width: scaled(2), height: scaled(5))
                        .offset(y: scaled(2))
                }
        case .trend:
            RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                .fill(IslandPalette.iconWell)
                .overlay {
                    Image(systemName: trendSymbol)
                        .font(.system(size: scaled(8), weight: .bold))
                        .foregroundStyle(semanticColor(index: 0))
                        .offset(x: scaled(9), y: scaled(-9))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                        .strokeBorder(IslandChrome.controlBorder, lineWidth: scaled(1))
                }
        case .summary:
            RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                .fill(IslandPalette.iconWell)
                .overlay(alignment: .bottom) {
                    HStack(spacing: scaled(2.5)) {
                        ForEach(0..<min(values.count, complication.family.metricLimit), id: \.self) { index in
                            Circle()
                                .fill(summaryColor(index: index))
                                .frame(width: scaled(3), height: scaled(3))
                        }
                    }
                    .offset(y: scaled(-3))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: scaled(7), style: .continuous)
                        .strokeBorder(IslandChrome.controlBorder, lineWidth: scaled(1))
                }
        case .cluster:
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    ring(
                        progress: clusterRingProgress(index: index),
                        color: clusterRingColor(index: index),
                        diameter: scaled([
                            IslandMetrics.ringSize,
                            IslandMetrics.clusterMiddleSize,
                            IslandMetrics.clusterInnerSize
                        ][index]),
                        trackWidth: scaled(IslandMetrics.clusterRingStroke),
                        strokeWidth: scaled(IslandMetrics.clusterAccentStroke)
                    )
                }
            }
        }
    }

    private func ring(
        progress: Double,
        color: Color,
        diameter: CGFloat,
        trackWidth: CGFloat = IslandMetrics.ringStroke,
        strokeWidth: CGFloat = IslandMetrics.accentStroke
    ) -> some View {
        ZStack {
            Circle()
                .inset(by: trackWidth / 2)
                .stroke(IslandPalette.track, lineWidth: trackWidth)
            Circle()
                .inset(by: trackWidth / 2)
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
        }
        .frame(width: diameter, height: diameter)
    }

    private var label: String {
        guard complication.labelStyle != .hidden else { return "" }
        guard !values.isEmpty else { return sourceError == nil ? "—" : "!" }
        if (complication.family == .dualRing
            || complication.family == .summary
            || complication.family == .cluster), values.count > 1 {
            return values
                .prefix(complication.family.metricLimit)
                .map { compactMultiValue($0.displayText) }
                .joined(separator: "·")
        }
        switch complication.labelStyle {
        case .percentage:
            return values[0].displayText
        case .value:
            return values[0].displayText
        case .compact:
            return values[0].displayText
        case .hidden:
            return ""
        }
    }

    private var usesSourceIdentity: Bool {
        complication.family == .dualRing
    }

    private var accessibilityValue: String {
        if let sourceError, values.isEmpty { return "Unavailable: \(sourceError)" }
        if values.isEmpty {
            return quality == .unavailable || quality == .failed ? "Not reported" : "No data"
        }
        let prefix = quality == .stale ? "Stale data, " : ""
        return prefix + values.map(\.displayText).joined(separator: ", ")
    }

    private var accent: Color { accent(for: 0) }

    private func accent(for index: Int) -> Color {
        let tint = complication.slotTints[safe: index] ?? complication.tint
        switch tint.style {
        case .monochrome:
            return .white.opacity(0.82)
        case .custom:
            return Color(hex: tint.hex) ?? .white
        case .source:
            return ComplicationSourceStyle.accent(
                sourceID: complication.sourceID,
                descriptor: descriptor
            )
        }
    }

    private var statusColor: Color {
        guard case .status(_, let level) = values.first else { return sourceError == nil ? accent : .red }
        switch level {
        case .healthy: return accent
        case .warning: return Color.orange
        case .critical: return Color.red
        case .inactive: return IslandPalette.label
        }
    }

    private var activityArcEnd: CGFloat {
        guard case .status(_, let level) = values.first else {
            return values.first == nil ? 0.08 : 0.72
        }
        switch level {
        case .healthy: return 0.82
        case .warning: return 0.62
        case .critical: return 0.44
        case .inactive: return 0.25
        }
    }

    private var trendSymbol: String {
        switch trendDirection {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        case .unknown: break
        }
        if values.count > 1,
           let first = numericValue(values[0]),
           let second = numericValue(values[1]) {
            if first > second { return "arrow.up.right" }
            if first < second { return "arrow.down.right" }
            return "arrow.right"
        }

        guard let metricID = complication.metricIDs.first,
              let metric = descriptor?.metrics.first(where: { $0.id == metricID }),
              let value = values.first.flatMap(numericValue),
              let warning = metric.policy.thresholds?.warning
        else { return "arrow.right" }
        switch metric.policy.direction {
        case .lowerIsBetter where value > warning: return "arrow.up.right"
        case .higherIsBetter where value < warning: return "arrow.down.right"
        default: break
        }
        return "arrow.right"
    }

    private func numericValue(_ value: ComplicationValue) -> Double? {
        switch value {
        case .gauge(let number, _, _): return number
        case .value(let string, _): return Double(string.replacingOccurrences(of: ",", with: "."))
        case .duration(let interval, _): return interval
        case .date(let date, _): return date.timeIntervalSince1970
        case .status: return nil
        }
    }

    private func clusterColor(index: Int, value: ComplicationValue) -> Color {
        if case .status(_, let level) = value {
            switch level {
            case .healthy: return accent(for: index)
            case .warning: return .orange
            case .critical: return .red
            case .inactive: return IslandPalette.label
            }
        }
        return semanticColor(index: index)
    }

    private func clusterRingProgress(index: Int) -> Double {
        guard let value = values[safe: index] else { return 0 }
        if case .status(_, let level) = value {
            return switch level {
            case .healthy: 0.86
            case .warning: 0.62
            case .critical: 0.38
            case .inactive: 0.12
            }
        }
        if let progress = value.progress { return progress }
        guard let number = numericValue(value),
              let metricID = complication.metricIDs[safe: index],
              let range = descriptor?.metrics.first(where: { $0.id == metricID })?.policy.range
        else { return 0.72 }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((number - range.lowerBound) / span, 0), 1)
    }

    private func clusterRingColor(index: Int) -> Color {
        guard let value = values[safe: index] else { return accent(for: index) }
        return clusterColor(index: index, value: value)
    }

    private func summaryColor(index: Int) -> Color {
        guard let value = values[safe: index] else { return accent(for: index) }
        return clusterColor(index: index, value: value)
    }

    private func compactMultiValue(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: " USD", with: "")
            .replacingOccurrences(of: " ms", with: "ms")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard complication.family == .summary else { return value }
        if text.hasSuffix(" USD") { value = "$" + value }
        let lower = value.lowercased()
        if lower.contains("critical") || lower.contains("overdue") { return "!" }
        if lower.contains("warning") || lower.hasSuffix(" low") { return "Low" }
        if ["healthy", "all healthy", "online", "on track", "nominal"].contains(lower) { return "OK" }
        if lower == "up to date" { return "Sync" }
        if lower == "charging" { return "Chg" }
        if lower == "on battery" { return "Batt" }
        guard value.count > 5 else { return value }
        return String(value.prefix(4)) + "…"
    }

    /// Applies the metric's direction and thresholds to gauge/value visuals.
    /// Remaining/inverse recipe transforms also invert the direction, so a
    /// fuller "available" ring remains healthy rather than looking critical.
    private func semanticColor(index: Int) -> Color {
        guard values.indices.contains(index),
              let number = numericValue(values[index]),
              let metricID = complication.metricIDs[safe: index],
              let metric = descriptor?.metrics.first(where: { $0.id == metricID }),
              let rawThresholds = metric.policy.thresholds
        else { return accent(for: index) }

        var transforms = recipe?.slots[safe: index]?.transforms ?? []
        if complication.valueMode(at: index) == .remaining {
            transforms.append(.remaining)
        }
        let direction = metric.policy.direction.transformed(by: transforms)
        let thresholds = rawThresholds.transformed(by: transforms, in: metric.policy.range)
        switch direction {
        case .higherIsBetter:
            if let critical = thresholds.critical, number <= critical { return .red }
            if let warning = thresholds.warning, number <= warning { return .orange }
        case .lowerIsBetter, .neutral:
            if let critical = thresholds.critical, number >= critical { return .red }
            if let warning = thresholds.warning, number >= warning { return .orange }
        }
        return accent(for: index)
    }

    private var recipe: ComplicationRecipe? {
        complication.recipeID.flatMap { recipeID in
            descriptor?.complications.first { $0.id == recipeID }
        }
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * max(renderScale, 0.5)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SourceMark: View {
    let sourceID: String
    let descriptor: ComplicationSourceDescriptor?
    var metricID: String? = nil
    var size: CGFloat

    var body: some View {
        Group {
            if let metricSymbol {
                Image(systemName: metricSymbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.82, weight: .semibold))
                    .foregroundStyle(.white)
            } else if let brand = ProviderBrand(rawValue: sourceID) {
                ProviderMark(brand: brand, size: size)
            } else if descriptor?.sourceKindID == ConfigurableSourceKind.githubRepository.sourceKindID {
                VectorTemplateMark(resource: ("GitHubIcon", "svg"))
                    .frame(width: size * 0.82, height: size * 0.82)
            } else {
                Image(systemName: descriptor?.symbol ?? "questionmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var metricSymbol: String? {
        guard descriptor?.kind != .usage, let metricID else { return nil }
        return descriptor?.metrics.first { $0.id == metricID }?.symbol
    }
}

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
