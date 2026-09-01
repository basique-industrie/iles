import AppKit
import Domain
import SwiftUI

struct ComplicationDataEditor: View {
    @Bindable var runtime: IslandRuntime
    let island: IslandConfiguration
    let complication: ComplicationConfiguration
    let descriptor: ComplicationSourceDescriptor?
    let values: [ComplicationValue]
    @State private var colorEditorIndex: Int?
    private let chooserHeight: CGFloat = 36

    var body: some View {
        SettingsGroup(
            title: dataSlotCount > 1 ? "Rings" : "Content",
            subtitle: dataSlotCount > 1
                ? "Choose what each ring shows and how it is colored."
                : "Choose the value and its appearance."
        ) {
            VStack(spacing: 0) {
                ForEach(0..<dataSlotCount, id: \.self) { index in
                    dataSlotEditor(index: index)
                    if index < dataSlotCount - 1 {
                        SettingsHairline()
                            .padding(.leading, 50)
                    }
                }
            }
            .background(IslandChrome.cardFill, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(IslandChrome.hairline.opacity(0.72), lineWidth: 1)
            }

            if complication.family == .dualRing {
                HStack {
                    Spacer()
                    QuietButton(title: "Swap Rings", symbol: "arrow.up.arrow.down") {
                        swapMetricSlots()
                    }
                }
            }
        }
    }

    private var recipe: ComplicationRecipe? {
        complication.recipeID.flatMap { id in
            descriptor?.complications.first { $0.id == id }
        }
    }

    private var dataSlotCount: Int {
        complication.family.metricLimit
    }

    private func dataSlotEditor(index: Int) -> some View {
        HStack(spacing: 6) {
            metricSlotGlyph(index: index)
                .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortMetricSlotName(index: index))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                if let preview = metricPreviewValue(index: index) {
                    Text(preview)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandChrome.tertiaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 44, alignment: .leading)
            .help(metricSlotExplanation(index: index))

            metricPicker(index: index)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            if supportsValueMode(index: index) {
                valueModePicker(index: index)
            }

            colorPickerButton(index: index)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func valueModePicker(index: Int) -> some View {
        let selected = complication.valueMode(at: index)
        return Menu {
            ForEach(ComplicationValueMode.allCases, id: \.self) { mode in
                Button {
                    valueMode(index: index).wrappedValue = mode
                } label: {
                    Label(
                        mode == .used ? "Used" : "Remaining",
                        systemImage: mode == selected ? "checkmark" : "circle"
                    )
                }
            }
        } label: {
            Text(selected == .used ? "Used" : "Remaining")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 104, height: chooserHeight)
        .settingsPopupChrome(compact: true)
        .accessibilityLabel("Value presentation")
        .help("Show quota used or quota remaining")
    }

    private func colorPickerButton(index: Int) -> some View {
        Button {
            colorEditorIndex = index
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(slotDisplayColor(index: index))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(IslandChrome.secondaryText)
            }
            .frame(width: 38, height: chooserHeight)
            .background(IslandChrome.selectedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(IslandChrome.selectionBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metricSlotName(index: index)) color")
        .help("Choose \(metricSlotName(index: index).lowercased()) color")
        .popover(isPresented: colorEditorPresented(index: index), arrowEdge: .leading) {
            colorEditor(index: index)
        }
    }

    private func colorEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(metricSlotName(index: index)) Color")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            colorPresetButton(
                index: index,
                style: .source,
                title: "Source Accent",
                color: sourceAccent
            )
            colorPresetButton(
                index: index,
                style: .monochrome,
                title: "Monochrome",
                color: Color.white.opacity(0.82)
            )

            ColorPicker(
                selection: slotCustomColor(index: index),
                supportsOpacity: false
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                    Text("Custom Color")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 8)
                    if resolvedTint(index: index).style == .custom {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(
                resolvedTint(index: index).style == .custom ? IslandChrome.selectedFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .padding(10)
        .frame(width: 210)
    }

    private func colorPresetButton(
        index: Int,
        style: ComplicationTintStyle,
        title: String,
        color: Color
    ) -> some View {
        let selected = resolvedTint(index: index).style == style
        return Button {
            setTint(ComplicationTint(style: style), for: index)
            colorEditorIndex = nil
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1) }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(selected ? IslandChrome.selectedFill : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func colorEditorPresented(index: Int) -> Binding<Bool> {
        Binding(
            get: { colorEditorIndex == index },
            set: { presented in
                if !presented, colorEditorIndex == index { colorEditorIndex = nil }
            }
        )
    }

    private func metricPicker(index: Int) -> some View {
        let candidates = compatibleMetrics(for: complication.family)
        let selectedID = complication.metricIDs.indices.contains(index) ? complication.metricIDs[index] : nil
        let selectedMetric = candidates.first { $0.id == selectedID }

        return Menu {
            ForEach(candidates, id: \.id) { candidate in
                let assignedElsewhere = isMetricAssigned(candidate.id, excluding: index)
                Button {
                    metric(index: index).wrappedValue = candidate.id
                } label: {
                    Label(
                        assignedElsewhere ? "\(candidate.name) — In Use" : candidate.name,
                        systemImage: candidate.id == selectedID
                            ? "checkmark"
                            : candidate.symbol ?? candidate.kind.inspectorSymbol
                    )
                }
                .disabled(assignedElsewhere)
            }
        } label: {
            SettingsMenuLabel(
                symbol: selectedMetric?.symbol ?? selectedMetric?.kind.inspectorSymbol ?? "questionmark",
                title: selectedMetric?.name ?? "Choose Data",
                compact: true,
                controlHeight: chooserHeight
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
        .settingsPopupChrome(compact: true)
        .disabled(candidates.isEmpty)
        .help(selectedMetric.map { metricDesignDescription($0, index: index) } ?? "Choose a metric")
    }

    @ViewBuilder
    private func metricSlotGlyph(index: Int) -> some View {
        switch complication.family {
        case .ring:
            dataRingGlyph(
                diameter: 29,
                color: slotDisplayColor(index: index)
            )
        case .dualRing:
            ZStack {
                dataRingGlyph(
                    diameter: 29,
                    color: index == 0 ? slotDisplayColor(index: index) : Color.white.opacity(0.16)
                )
                dataRingGlyph(
                    diameter: 19,
                    color: index == 1 ? slotDisplayColor(index: index) : Color.white.opacity(0.16)
                )
            }
        case .summary:
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { item in
                    Circle()
                        .fill(item == index ? slotDisplayColor(index: index) : Color.white.opacity(0.14))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 30, height: 30)
            .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .cluster:
            ZStack {
                dataRingGlyph(
                    diameter: 29,
                    color: index == 0 ? slotDisplayColor(index: index) : Color.white.opacity(0.14)
                )
                dataRingGlyph(
                    diameter: 21,
                    color: index == 1 ? slotDisplayColor(index: index) : Color.white.opacity(0.14)
                )
                dataRingGlyph(
                    diameter: 13,
                    color: index == 2 ? slotDisplayColor(index: index) : Color.white.opacity(0.14)
                )
            }
        default:
            Image(systemName: complication.family.inspectorSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(slotDisplayColor(index: index).opacity(0.16), in: Circle())
        }
    }

    private func dataRingGlyph(diameter: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: diameter, height: diameter)
    }

    private func metricSlotName(index: Int) -> String {
        switch complication.family {
        case .dualRing: index == 0 ? "Outer Ring" : "Inner Ring"
        case .summary:
            switch index {
            case 0: "Primary"
            case 1: "Supporting"
            default: "Third"
            }
        case .cluster:
            switch index {
            case 0: "Outer Ring"
            case 1: "Middle Ring"
            default: "Inner Ring"
            }
        default: "Content"
        }
    }

    private func shortMetricSlotName(index: Int) -> String {
        switch complication.family {
        case .dualRing: index == 0 ? "Outer" : "Inner"
        case .cluster:
            switch index {
            case 0: "Outer"
            case 1: "Middle"
            default: "Inner"
            }
        default: metricSlotName(index: index)
        }
    }

    private func metricSlotExplanation(index: Int) -> String {
        switch complication.family {
        case .dualRing:
            index == 0
                ? "Primary progress around the outside."
                : "Supporting progress closest to the source."
        case .summary:
            switch index {
            case 0: "The first value in the compact summary."
            case 1: "The second related value."
            default: "The final supporting value."
            }
        case .cluster:
            switch index {
            case 0: "Primary progress on the largest ring."
            case 1: "Supporting progress on the middle ring."
            default: "Third progress signal at the center."
            }
        default:
            "The value represented by this complication."
        }
    }

    private func metricPreviewValue(index: Int) -> String? {
        guard values.indices.contains(index) else { return nil }
        return String(values[index].displayText.prefix(12))
    }

    private func isMetricAssigned(_ metricID: String, excluding index: Int) -> Bool {
        complication.metricIDs.enumerated().contains { offset, id in
            offset != index && id == metricID
        }
    }

    private func swapMetricSlots() {
        guard complication.metricIDs.count >= 2 else { return }
        runtime.workspaceStore.updateComplication(complication.id, in: island.id) { config in
            config.metricIDs.swapAt(0, 1)
            let firstMode = config.valueMode(at: 0)
            let secondMode = config.valueMode(at: 1)
            config.setValueMode(secondMode, at: 0)
            config.setValueMode(firstMode, at: 1)
            config.recipeID = nil
        }
    }

    private func resolvedTint(index: Int) -> ComplicationTint {
        complication.slotTints.indices.contains(index)
            ? complication.slotTints[index]
            : complication.tint
    }

    private func slotDisplayColor(index: Int) -> Color {
        let tint = resolvedTint(index: index)
        return switch tint.style {
        case .source: sourceAccent
        case .monochrome: Color.white.opacity(0.82)
        case .custom: Color(hex: tint.hex) ?? .white
        }
    }

    private func setTint(_ tint: ComplicationTint, for index: Int) {
        runtime.workspaceStore.updateComplication(complication.id, in: island.id) { config in
            if config.family.metricLimit == 1 {
                config.tint = tint
                return
            }
            while config.slotTints.count < config.family.metricLimit {
                config.slotTints.append(config.tint)
            }
            config.slotTints[index] = tint
        }
    }

    private func slotCustomColor(index: Int) -> Binding<Color> {
        Binding(
            get: { slotDisplayColor(index: index) },
            set: { value in
                let color = NSColor(value).usingColorSpace(.sRGB) ?? NSColor.white
                let hex = String(
                    format: "%02X%02X%02X",
                    Int((color.redComponent * 255).rounded()),
                    Int((color.greenComponent * 255).rounded()),
                    Int((color.blueComponent * 255).rounded())
                )
                setTint(ComplicationTint(style: .custom, hex: hex), for: index)
            }
        )
    }

    private func metric(index: Int) -> Binding<String> {
        Binding(
            get: { complication.metricIDs.indices.contains(index) ? complication.metricIDs[index] : (effectiveMetrics.first?.id ?? "") },
            set: { value in
                runtime.workspaceStore.updateComplication(complication.id, in: island.id) { config in
                    while config.metricIDs.count <= index { config.metricIDs.append(value) }
                    config.metricIDs[index] = value
                    config.recipeID = nil
                }
            }
        )
    }

    private func valueMode(index: Int) -> Binding<ComplicationValueMode> {
        Binding(
            get: { complication.valueMode(at: index) },
            set: { mode in
                runtime.workspaceStore.updateComplication(complication.id, in: island.id) {
                    $0.setValueMode(mode, at: index)
                }
            }
        )
    }

    private func supportsValueMode(index: Int) -> Bool {
        guard descriptor?.kind == .usage,
              complication.metricIDs.indices.contains(index),
              let metric = effectiveMetrics.first(where: { $0.id == complication.metricIDs[index] })
        else { return false }
        return metric.kind == .gauge && metric.policy.format == .percentage
    }

    private func compatibleMetrics(for family: ComplicationFamily) -> [ComplicationMetricDescriptor] {
        effectiveMetrics.filter {
            ComplicationRecipeValidator.family(family, supports: $0.kind, metric: $0)
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

    private func metricDesignDescription(
        _ metric: ComplicationMetricDescriptor,
        index: Int
    ) -> String {
        let transforms = recipe?.slots.indices.contains(index) == true
            ? recipe?.slots[index].transforms ?? []
            : []
        let outputKind = ComplicationRecipeValidator.resolvedKind(
            inputKind: metric.kind,
            transforms: transforms
        )
        let recommendedFamily = recipe?.family ?? metric.recommendedFamily(for: outputKind)
        return [
            transforms.last?.designName,
            metric.policy.format.designName,
            metric.policy.direction.transformed(by: transforms).designName,
            "Recommended: \(recommendedFamily.displayName)",
            complication.family.fitDescription(for: outputKind),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var sourceAccent: Color {
        ComplicationSourceStyle.accent(
            sourceID: complication.sourceID,
            descriptor: descriptor
        )
    }
}
