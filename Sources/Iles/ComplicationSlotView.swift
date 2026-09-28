import AppKit
import Domain
import IslandGeometry
import SwiftUI

struct ComplicationSlotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .frame(width: scaled(IslandMetrics.width - 12))
        .privacySensitive()
        .opacity(quality == .stale ? 0.78 : (sourceError == nil || !values.isEmpty ? 1 : 0.62))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glanceName)
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
    }

    @ViewBuilder
    private var sourceMark: some View {
        if complication.family != .cluster {
            SourceMark(
                sourceID: complication.sourceID,
                descriptor: descriptor,
                metricID: usesSourceIdentity ? nil : complication.metricIDs.first,
                metricIDs: complication.metricIDs,
                size: scaled(IslandMetrics.markSize),
                tint: NSColor(accent).blended(withFraction: 0.72, of: .white) ?? .white
            )
            .opacity(isSyncing ? 0.4 : (isSelected ? 1 : 0.88))
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
        if quality == .unavailable || quality == .failed {
            Image(systemName: "exclamationmark")
                .font(.system(size: scaled(7), weight: .bold))
                .foregroundStyle(quality == .failed ? Color.red : IslandPalette.label)
                .frame(width: scaled(11), height: scaled(11))
                .background(Color.black.opacity(0.82), in: Circle())
                .offset(x: scaled(14), y: scaled(-14))
        } else if quality == .stale {
            Image(systemName: "clock")
                .font(.system(size: scaled(7), weight: .bold))
                .foregroundStyle(IslandPalette.label)
                .frame(width: scaled(11), height: scaled(11))
                .background(Color.black.opacity(0.82), in: Circle())
                .offset(x: scaled(14), y: scaled(-14))
        }
    }

    private var accountLabel: String? {
        HarnaisGlance.accountLabel(sourceID: complication.sourceID, metricIDs: complication.metricIDs, descriptor: descriptor)
    }

    private func slotCaption(_ index: Int) -> String {
        guard let id = complication.metricIDs[safe: index] else { return "Usage" }
        return HarnaisGlance.slotCaption(sourceID: complication.sourceID, metricID: id, descriptor: descriptor)
    }

    @ViewBuilder
    private var valueLabel: some View {
        Group {
            if complication.labelStyle == .hidden {
                Color.clear
            } else if HarnaisGlance.applies(to: complication.sourceID), !values.isEmpty, !hasRemainingUsageSlot,
                      complication.labelStyle != .compact,
                      complication.family == .ring || complication.family == .dualRing {
                VStack(spacing: 0) {
                    ForEach(Array(values.prefix(complication.family.metricLimit).enumerated()), id: \.offset) { index, value in
                        Text(value.displayText)
                            .font(.system(size: scaled(values.count > 1 ? 9 : 11), weight: .semibold))
                            .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.68))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(height: scaled(values.count > 1 ? 10 : 20))
                    }
                }
            } else if let byteLabel = compactByteLabel {
                VStack(spacing: 0) {
                    Text(byteLabel.amount)
                        .font(.system(size: scaled(10), weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(byteLabel.unit)
                        .font(.system(size: scaled(8), weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            } else {
                Text(label)
                    .font(.system(size: scaled(10), weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(width: scaled(IslandMetrics.textWidth), height: scaled(IslandMetrics.ringLabelHeight))
    }

    private var compactByteLabel: CompactByteLabel? {
        guard values.count == 1,
              let metricID = complication.metricIDs.first,
              descriptor?.metrics.first(where: { $0.id == metricID })?.policy.format == .bytes
        else { return nil }
        return CompactByteLabel(value: values[0])
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
                    color: semanticColor(index: 1).opacity(usageStyle.intensity(at: 1)),
                    diameter: scaled(IslandMetrics.dualRingInnerSize),
                    trackWidth: scaled(IslandMetrics.dualRingInnerStroke),
                    strokeWidth: scaled(IslandMetrics.dualRingInnerAccentStroke),
                    secondary: true
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: activityArcEnd)
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
        strokeWidth: CGFloat = IslandMetrics.accentStroke,
        secondary: Bool = false
    ) -> some View {
        let fraction = ComplicationUsageStyle.clampedProgress(progress)
        return ZStack {
            Circle()
                .inset(by: trackWidth / 2)
                .stroke(Color.white.opacity(secondary ? (isSelected ? 0.18 : 0.14) : (isSelected ? 0.23 : 0.19)), lineWidth: trackWidth)
            Circle()
                .inset(by: trackWidth / 2)
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: fraction < 0.08 ? .butt : .round))
                .opacity(fraction > 0 ? 1 : 0)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: progress)
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
                .enumerated()
                .map { compactLabeled($0.element.displayText, index: $0.offset) }
                .joined(separator: " · ")
        }
        switch complication.labelStyle {
        case .percentage, .value, .compact:
            return compactLabeled(values[0].displayText, index: 0)
        case .hidden:
            return ""
        }
    }

    private var hasRemainingUsageSlot: Bool {
        complication.metricIDs.indices.contains { index in
            isUsagePercent(index) && complication.valueMode(at: index) == .remaining
        }
    }

    private func isUsagePercent(_ index: Int) -> Bool {
        guard let metricID = complication.metricIDs[safe: index] else { return false }
        if metricID.hasPrefix("quota") { return true }
        let metric = descriptor?.metrics.first { $0.id == metricID }
        return metric?.kind == .gauge && metric?.policy.format == .percentage
    }

    private func compactLabeled(_ text: String, index: Int) -> String {
        let compact = compactMultiValue(text)
        guard isUsagePercent(index) else { return compact }
        if complication.valueMode(at: index) == .remaining {
            return compact.lowercased().contains("left") ? compact : "\(compact) left"
        }
        if hasRemainingUsageSlot {
            return compact.lowercased().contains("used") ? compact : "\(compact) used"
        }
        return compact
    }

    private var usesSourceIdentity: Bool {
        complication.family == .dualRing
    }

    private var glanceName: String {
        HarnaisGlance.resolvedBrand(
            sourceID: complication.sourceID,
            metricIDs: complication.metricIDs,
            descriptor: descriptor
        ).map { brand in
            [brand.title, accountLabel].compactMap { $0 }.joined(separator: " · ")
        } ?? descriptor?.name ?? "Unavailable complication"
    }

    private var accessibilityValue: String {
        if let sourceError, values.isEmpty { return "Unavailable: \(sourceError)" }
        if values.isEmpty {
            return quality == .unavailable || quality == .failed ? "Not reported" : "No data"
        }
        let prefix = quality == .stale ? "Stale data, " : ""
        return prefix + values.enumerated().map { index, value in
            guard descriptor?.kind == .usage, isUsagePercent(index) else { return value.displayText }
            let mode = complication.valueMode(at: index) == .remaining ? "remaining" : "used"
            return "\(slotCaption(index)) \(value.displayText) \(mode)"
        }.joined(separator: ", ")
    }

    private var accent: Color { accent(for: 0) }

    private var usageStyle: ComplicationUsageStyle {
        ComplicationUsageStyle(complication: complication, descriptor: descriptor)
    }

    private func accent(for index: Int) -> Color { usageStyle.accent(at: index) }

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
            .replacingOccurrences(of: " USD", with: "")
            .replacingOccurrences(of: " ms", with: "ms")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if complication.labelStyle == .compact { value = value.replacingOccurrences(of: "%", with: "") }
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
        usageStyle.color(at: index, value: values[safe: index])
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
