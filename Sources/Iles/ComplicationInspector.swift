import AppKit
import Domain
import IslandGeometry
import SwiftUI

private enum ComplicationEditorStep: String, CaseIterable {
    case style
    case data
    case finish

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .style: "square.grid.2x2"
        case .data: "circle.hexagongrid"
        case .finish: "checkmark"
        }
    }
}

struct ComplicationInspector: View {
    @Bindable var runtime: IslandRuntime
    let island: IslandConfiguration
    let complication: ComplicationConfiguration
    let configureSource: (String) -> Void
    let delete: () -> Void
    @State private var editorStep: ComplicationEditorStep = .style

    private var descriptor: ComplicationSourceDescriptor? {
        runtime.descriptor(sourceID: complication.sourceID)
    }

    private var snapshot: SourceSnapshot? {
        runtime.snapshot(sourceID: complication.sourceID)
    }

    private var recipe: ComplicationRecipe? {
        complication.recipeID.flatMap { id in
            descriptor?.complications.first { $0.id == id }
        }
    }

    private var liveValues: [ComplicationValue] {
        runtime.values(for: complication)
    }

    private var fixtureValues: [ComplicationValue] {
        recipe.map {
            ComplicationPreviewFixture.values(for: $0, sourceID: complication.sourceID)
                .enumerated()
                .map { index, value in
                    ComplicationTransformEngine.present(value, as: complication.valueMode(at: index))
                }
        } ?? []
    }

    private var usesFixture: Bool {
        liveValues.isEmpty && !fixtureValues.isEmpty
    }

    private var values: [ComplicationValue] {
        usesFixture ? fixtureValues : liveValues
    }

    var body: some View {
        HStack {
            PageTitle(title: "Complication")
            Spacer()
            Menu {
                Button {
                    runtime.workspaceStore.duplicateComplication(complication.id, in: island.id)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    visibility.wrappedValue.toggle()
                } label: {
                    Label(
                        complication.isVisible ? "Hide from Island" : "Show on Island",
                        systemImage: complication.isVisible ? "eye.slash" : "eye"
                    )
                }
                if recipe != nil {
                    Button {
                        detachRecipe()
                    } label: {
                        Label("Convert to Custom", systemImage: "slider.horizontal.3")
                    }
                }
                Divider()
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                RowActionGlyph(symbol: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Complication actions")
            QuietIconButton(
                symbol: "xmark",
                accessibilityName: "Close inspector",
                helpText: "Show island settings"
            ) {
                runtime.workspaceStore.selectedComplicationID = nil
            }
        }

        livePreview

        IslandSegmentBar(
            items: ComplicationEditorStep.allCases,
            selection: $editorStep,
            title: \.title,
            symbol: \.symbol
        )

        Group {
            switch editorStep {
            case .style: styleStep
            case .data: dataStep
            case .finish: finishStep
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var styleStep: some View {
        SettingsGroup(
            title: "Style",
            subtitle: "Choose how this complication reads at a glance."
        ) {
            LazyVGrid(columns: styleColumns, spacing: 7) {
                ForEach(supportedFamilies, id: \.self) { item in
                    familyButton(item)
                }
            }
        }
    }

    private var dataStep: some View {
        ComplicationDataEditor(
            runtime: runtime,
            island: island,
            complication: complication,
            descriptor: descriptor,
            values: values
        )
    }

    private var finishStep: some View {
        SettingsGroup(
            title: "Label & Interaction",
            subtitle: "Choose the supporting label and click behavior."
        ) {
            valueLabelControl
            FieldLabel(title: "On Click")
            LazyVGrid(columns: optionColumns, spacing: 7) {
                ForEach(availableActions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    private var valueLabelControl: some View {
        HStack(spacing: 9) {
            Image(systemName: "textformat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(IslandChrome.selectedFill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Show Value Label")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Display the glance value below the complication.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(IslandChrome.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            IslandToggle(isOn: labelVisibility)
                .accessibilityLabel("Show Value Label")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(
            IslandChrome.cardFill,
            in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                .strokeBorder(IslandChrome.hairline.opacity(0.72), lineWidth: 1)
        }
    }

    private var livePreview: some View {
        IslandCard(padding: 0) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous)
                        .fill(Color.black.opacity(0.34))

                    ComplicationSlotView(
                        complication: complication,
                        descriptor: descriptor,
                        values: values,
                        sourceError: usesFixture ? nil : snapshot?.errorDescription,
                        quality: usesFixture ? .cached : runtime.quality(for: complication),
                        trendDirection: usesFixture ? .unknown : runtime.trendDirection(for: complication),
                        isSyncing: runtime.provider(id: complication.sourceID)?.isSyncing == true,
                        renderScale: 1.8
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    VStack {
                        HStack {
                            SectionLabel(title: usesFixture ? "Sample Preview" : "Live Preview")
                            Spacer()
                            Text(glanceValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(IslandChrome.secondaryText)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .padding(11)
                }
                .frame(height: 126)
                .clipped()

                if let error = snapshot?.errorDescription {
                    SettingsHairline()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 10, weight: .semibold))
                            Text(error)
                                .font(.system(size: 10, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        QuietButton(
                            title: "Configure Source",
                            symbol: "slider.horizontal.3",
                            prominence: .primary
                        ) {
                            configureSource(complication.sourceID)
                        }
                    }
                    .foregroundStyle(IslandChrome.secondaryText)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 11)
                }
            }
        }
    }

    private func familyButton(_ item: ComplicationFamily) -> some View {
        let selected = complication.family == item
        let preview = stylePreviewConfiguration(for: item)
        let previewValues = runtime.values(for: preview)
        let usesSample = previewValues.isEmpty && values.isEmpty
        let displayedValues = usesSample
            ? sampleStyleValues(for: item)
            : (previewValues.isEmpty ? Array(values.prefix(item.metricLimit)) : previewValues)
        return Button {
            family.wrappedValue = item
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    ComplicationSlotView(
                        complication: preview,
                        descriptor: descriptor,
                        values: displayedValues,
                        sourceError: usesSample ? nil : snapshot?.errorDescription,
                        quality: usesFixture || usesSample ? .cached : runtime.quality(for: preview),
                        trendDirection: usesFixture ? .unknown : runtime.trendDirection(for: preview),
                        renderScale: 1.05,
                        reservesHiddenLabelSpace: false
                    )
                    .frame(width: 58, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    Text(item.displayName)
                        .font(.system(size: 10, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : IslandChrome.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 70)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                } else if item == recommendedStyleFamily {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(IslandChrome.secondaryText)
                        .padding(8)
                }
            }
            .background(
                selected ? IslandChrome.selectedFill : IslandChrome.fieldFill,
                in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                    .strokeBorder(selected ? IslandChrome.selectionBorder : IslandChrome.controlBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayName) family")
        .accessibilityHint(item.designDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(item.designDescription)
    }

    private func actionButton(_ item: ComplicationAction) -> some View {
        let selected = complication.tapAction == item
        return Button {
            tapAction.wrappedValue = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.inspectorSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(IslandChrome.selectedFill, in: Circle())
                Text(item.displayName)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : IslandChrome.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                selected ? IslandChrome.selectedFill : IslandChrome.fieldFill,
                in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                    .strokeBorder(selected ? IslandChrome.selectionBorder : IslandChrome.controlBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("On click: \(item.displayName)")
        .accessibilityHint(item.explanation)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(item.explanation)
    }

    private var styleColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 2)
    }

    private var optionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: 2)
    }

    private var family: Binding<ComplicationFamily> {
        Binding(get: { complication.family }, set: { value in
            runtime.workspaceStore.updateComplication(complication.id, in: island.id) { config in
                let previousFamily = config.family
                let candidates = compatibleMetrics(for: value)
                let candidateIDs = Set(candidates.map(\.id))
                config.metricIDs = config.metricIDs.filter { candidateIDs.contains($0) }
                if config.metricIDs.isEmpty, let first = candidates.first?.id {
                    config.metricIDs = [first]
                }
                let targetCount = value.metricLimit
                while config.metricIDs.count < targetCount,
                      let next = candidates.first(where: { !config.metricIDs.contains($0.id) })?.id {
                    config.metricIDs.append(next)
                }
                if config.labelStyle == Self.preferredLabel(for: previousFamily) {
                    config.labelStyle = Self.preferredLabel(for: value)
                }
                config.setFamily(value)
            }
        })
    }
    private var visibility: Binding<Bool> {
        Binding(
            get: { complication.isVisible },
            set: { value in
                runtime.workspaceStore.updateComplication(complication.id, in: island.id) {
                    $0.isVisible = value
                }
            }
        )
    }

    private var labelVisibility: Binding<Bool> {
        Binding(
            get: { complication.labelStyle != .hidden },
            set: { value in
                runtime.workspaceStore.updateComplication(complication.id, in: island.id) {
                    $0.labelStyle = value ? Self.preferredLabel(for: $0.family) : .hidden
                }
            }
        )
    }

    private var tapAction: Binding<ComplicationAction> {
        Binding(get: { complication.tapAction }, set: { value in
            runtime.workspaceStore.updateComplication(complication.id, in: island.id) { $0.tapAction = value }
        })
    }


    private func compatibleMetrics(for family: ComplicationFamily) -> [ComplicationMetricDescriptor] {
        effectiveMetrics.filter {
            ComplicationRecipeValidator.family(family, supports: $0.kind, metric: $0)
        }
    }

    private var supportedFamilies: [ComplicationFamily] {
        let recipeFamilies = recipe?.compatibleFamilies ?? []
        let sourceFamilies = descriptor?.supportedFamilies ?? []
        let declared = !recipeFamilies.isEmpty
            ? recipeFamilies
            : (!sourceFamilies.isEmpty ? sourceFamilies : ComplicationFamily.allCases)
        return declared.filter { family in
            let count = compatibleMetrics(for: family).count
            return switch family {
            case .dualRing: count >= 2
            case .summary: count >= 2
            case .cluster: count >= 3
            default: count >= 1
            }
        }
    }

    private var effectiveMetrics: [ComplicationMetricDescriptor] {
        let advertised = descriptor?.metrics ?? []
        return advertised.isEmpty
            ? ComplicationMetricFallback.descriptors(
                metricIDs: complication.metricIDs,
                family: complication.family
            )
            : advertised
    }

    private func sampleStyleValues(for family: ComplicationFamily) -> [ComplicationValue] {
        compatibleMetrics(for: family)
            .prefix(family.metricLimit)
            .enumerated()
            .map { ComplicationMetricFallback.previewValue(for: $0.element, index: $0.offset) }
    }

    private func detachRecipe() {
        runtime.workspaceStore.updateComplication(complication.id, in: island.id) {
            $0.recipeID = nil
        }
    }

    private var recommendedStyleFamily: ComplicationFamily {
        guard let metricID = complication.metricIDs.first,
              let metric = descriptor?.metrics.first(where: { $0.id == metricID })
        else { return complication.family }
        return metric.recommendedFamily()
    }

    private func stylePreviewConfiguration(for family: ComplicationFamily) -> ComplicationConfiguration {
        let candidates = compatibleMetrics(for: family)
        let candidateIDs = Set(candidates.map(\.id))
        var metricIDs = complication.metricIDs.filter { candidateIDs.contains($0) }
        while metricIDs.count < family.metricLimit,
              let next = candidates.first(where: { !metricIDs.contains($0.id) })?.id {
            metricIDs.append(next)
        }
        if metricIDs.isEmpty, let first = candidates.first?.id {
            metricIDs = [first]
        }
        return ComplicationConfiguration(
            id: complication.id,
            isVisible: complication.isVisible,
            recipeID: nil,
            sourceID: complication.sourceID,
            metricIDs: Array(metricIDs.prefix(family.metricLimit)),
            family: family,
            // The style name below the preview already explains the family.
            // Hiding its value label keeps this chooser visual and scannable.
            labelStyle: .hidden,
            tint: complication.tint,
            slotTints: complication.slotTints,
            slotValueModes: complication.slotValueModes,
            tapAction: complication.tapAction
        )
    }

    private var availableActions: [ComplicationAction] {
        ComplicationAction.allCases.filter { action in
            action != .openDashboard
                || runtime.provider(id: complication.sourceID)?.dashboardURL != nil
                || descriptor?.actionURL != nil
        }
    }

    private var glanceValue: String {
        let value = values.first?.displayText ?? (snapshot?.errorDescription == nil ? "No data" : "Needs setup")
        return String(value.prefix(14))
    }

    private static func preferredLabel(for family: ComplicationFamily) -> ComplicationLabelStyle {
        switch family {
        case .ring, .dualRing: .percentage
        case .value: .value
        case .status, .activity, .countdown, .summary, .cluster: .compact
        case .trend: .value
        }
    }
}
