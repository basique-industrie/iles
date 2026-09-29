import Domain
import IslandGeometry
import SwiftUI

/// Shared recipe presentation for Sources and the add-widget gallery.
struct ComplicationRecipeCard: View {
    @Bindable var runtime: IslandRuntime
    let source: ComplicationSourceDescriptor
    let preset: ComplicationDescriptor
    let configureSource: () -> Void
    let add: () -> Void

    var body: some View {
        let preview = ComplicationConfiguration(
            recipeID: preset.id,
            sourceID: source.id,
            metricIDs: preset.metricIDs,
            family: preset.family,
            labelStyle: .hidden,
            tint: preset.tint,
            slotValueModes: ComplicationValueMode.remainingDefaults(
                sourceID: source.id,
                metricIDs: preset.metricIDs,
                family: preset.family
            ),
            tapAction: preset.tapAction
        )
        let livePreviewValues = runtime.values(for: preview)
        let fixtureModes = preview.slotValueModes
        let fixtureValues = ComplicationPreviewFixture.values(for: preset, sourceID: source.id)
            .enumerated()
            .map { index, value in
                let mode = fixtureModes.indices.contains(index) ? fixtureModes[index] : .used
                return ComplicationTransformEngine.present(value, as: mode)
            }
        let usesFixture = livePreviewValues.isEmpty && !fixtureValues.isEmpty
        let previewValues = usesFixture ? fixtureValues : livePreviewValues
        let account = HarnaisGlance.accountLabel(sourceID: source.id, metricIDs: preset.metricIDs, descriptor: source)
        let brand = HarnaisGlance.resolvedBrand(sourceID: source.id, metricIDs: preset.metricIDs, descriptor: source)
        let cardTitle = account.map { "\(brand?.title ?? source.name) · \($0)" } ?? preset.name
        let reading = previewValues.enumerated().map { index, value in
            let metric = preset.metricIDs.indices.contains(index) ? source.metrics.first { $0.id == preset.metricIDs[index] } : nil
            guard source.kind == .usage, metric?.policy.format == .percentage else { return value.displayText }
            let mode = fixtureModes.indices.contains(index) ? fixtureModes[index] : .used
            return "\(value.displayText) \(mode == .remaining ? "remaining" : "used")"
        }.joined(separator: " · ")
        let sourceError = runtime.snapshot(sourceID: source.id)?.errorDescription
        let glance = previewValues.first?.displayText ?? (sourceError == nil ? "No data" : "Needs setup")
        let availability = runtime.snapshot(sourceID: source.id)?.availability ?? .available
        let needsSetup = availability.state == .setupRequired
            || availability.state == .permissionRequired
            || availability.recoveryAction == .configure
            || availability.recoveryAction == .requestPermission
            || availability.recoveryAction == .openSettings
        let unavailable = availability.state == .unsupported
            || (availability.state == .failed && !needsSetup)
            || (sourceError != nil && source.kind == .system && !needsSetup)
        return Button {
            if needsSetup { configureSource() }
            else { add() }
        } label: {
            HStack(spacing: 9) {
                ComplicationSlotView(
                    complication: preview,
                    descriptor: source,
                    values: previewValues,
                    sourceError: usesFixture ? nil : sourceError,
                    quality: usesFixture ? .cached : runtime.quality(for: preview),
                    trendDirection: usesFixture ? .unknown : runtime.trendDirection(for: preview),
                    renderScale: 0.9,
                    reservesHiddenLabelSpace: false
                )
                .frame(width: 44, height: 50)
                .background(IslandPalette.surface, in: RoundedRectangle(cornerRadius: 9))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(cardTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IslandChrome.text)
                            .lineLimit(2)
                        if preset.isNew {
                            Text("NEW")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(IslandChrome.accent)
                        }
                    }
                    Text(galleryCardSubtitle(source: source, preset: preset, glance: glance))
                        .font(.system(size: 12))
                        .foregroundStyle(IslandChrome.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !reading.isEmpty {
                        Text(reading)
                            .font(.system(size: 11))
                            .foregroundStyle(IslandChrome.secondaryText)
                            .monospacedDigit()
                            .lineLimit(2)
                    }
                    if needsSetup || usesFixture || unavailable {
                        Text(unavailable ? "Unavailable" : (needsSetup ? "Set up source · Preview" : "Sample data"))
                            .font(.system(size: 11))
                            .foregroundStyle(IslandChrome.tertiaryText)
                    }
                }
                Spacer(minLength: 5)
                Image(systemName: unavailable ? "xmark" : (needsSetup ? "slider.horizontal.3" : "plus"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(IslandChrome.text)
                    .frame(width: 24, height: 24)
                    .background(IslandChrome.track, in: Circle())
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(SettingsActionButtonStyle())
        .disabled(unavailable)
        .accessibilityLabel(unavailable
            ? "\(source.name), \(preset.name), unavailable"
            : (needsSetup
                ? "Configure \(source.name) to use \(preset.name)"
                : "Add \(source.name), \(preset.name), \(glance)"))
        .help(unavailable
            ? "This complication is currently unavailable"
            : (needsSetup ? "Configure \(source.name)" : "Add \(preset.name) from \(source.name)"))
    }

    private func galleryCardSubtitle(
        source: ComplicationSourceDescriptor,
        preset: ComplicationDescriptor,
        glance: String
    ) -> String {
        if HarnaisGlance.accountLabel(sourceID: source.id, metricIDs: preset.metricIDs, descriptor: source) != nil {
            let windows = preset.metricIDs.map { id in
                HarnaisGlance.rowLabel(sourceID: source.id, metricID: id, metricName: source.metricName(for: id))
            }.joined(separator: " + ")
            return "\(preset.family.displayName) · \(windows)"
        }
        let metricNames = preset.metricIDs.compactMap { source.metricName(for: $0) }
        let detail: String
        switch metricNames.count {
        case 0:
            detail = glance
        case 1:
            detail = metricNames[0]
        default:
            detail = "\(metricNames.count) values"
        }
        return "\(preset.family.displayName) · \(detail)"
    }

}
