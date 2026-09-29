import AppKit
import Domain
import Infrastructure
import IslandGeometry
import SwiftUI
import UniformTypeIdentifiers

struct IslandWorkspaceEditor: View {
    @Bindable var runtime: IslandRuntime
    @Binding var presentsGallery: Bool
    @Binding var catalogSourceID: String?
    let configureSource: (String) -> Void
    @State private var draggedComplicationID: UUID?
    @State private var dragOriginOrder: [UUID] = []
    @State private var dropTargetID: UUID?
    @State private var pendingUndo: WorkspaceUndo?

    var body: some View {
        HStack(spacing: 0) {
            canvas
                .frame(minWidth: 480, maxWidth: .infinity)
            divider
            inspector
                .frame(width: 360)
                .background(IslandChrome.sidebar)
        }
        .sheet(isPresented: $presentsGallery, onDismiss: { catalogSourceID = nil }) {
            ComplicationGallery(
                runtime: runtime,
                isPresented: $presentsGallery,
                sourceScopeID: catalogSourceID,
                configureSource: configureSource
            )
        }
        .overlay(alignment: .bottom) {
            undoToast
        }
    }

    private var divider: some View {
        Rectangle().fill(IslandChrome.hairline).frame(width: 1)
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            if let island = runtime.workspaceStore.selectedIsland {
                SettingsPageHeader(title: island.name, subtitle: canvasCaption(for: island)) {
                    QuietButton(
                        title: "Add widget",
                        symbol: "plus",
                        prominence: .primary
                    ) {
                        catalogSourceID = nil
                        presentsGallery = true
                    }
                }

                IslandCard(padding: 0) {
                    HStack(spacing: 0) {
                        placementPane(island)
                            .frame(width: 116)
                        divider
                        complicationOrderPane(island)
                            .frame(minWidth: 340, maxWidth: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: IslandChrome.cardRadius, style: .continuous))
                .frame(maxHeight: .infinity)
            } else {
                emptyIslandsCanvas
            }
        }
        .padding(.horizontal, IslandChrome.pageInset)
        .padding(.top, IslandChrome.pageTop)
        .padding(.bottom, IslandChrome.pageBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placementPane(_ island: IslandConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: "Preview")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            SettingsHairline()

            livePlacementPreview(island)
        }
        .background(IslandChrome.sidebar)
    }

    private func livePlacementPreview(_ island: IslandConfiguration) -> some View {
        let screenMax = IslandMetrics.maximumHeight(
            visibleFrameHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
        let naturalHeight = IslandMetrics.height(forProviderCount: runtime.visibleComplications(on: island).count)
        let previewMaxHeight = min(naturalHeight, screenMax)

        return GeometryReader { proxy in
            let availableHeight = max(proxy.size.height - 44, 1)
            let scale = min(1, availableHeight / max(previewMaxHeight, 1))

            ZStack(alignment: island.placement.edge == .leading ? .leading : .trailing) {
                Color.clear

                IslandView(
                    runtime: runtime,
                    islandID: island.id,
                    maxHeight: previewMaxHeight,
                    interactive: false,
                    selectedComplicationID: runtime.workspaceStore.selectedComplicationID
                )
                .frame(width: IslandMetrics.width, height: previewMaxHeight)
                .scaleEffect(scale)
                .frame(width: IslandMetrics.width * scale, height: previewMaxHeight * scale)
                .padding(.horizontal, 10)

                VStack {
                    Spacer()
                    placementHint(for: island)
                        .padding(10)
                }
            }
            .clipped()
        }
        .accessibilityLabel("Live preview of \(island.name)")
    }

    private func placementHint(for island: IslandConfiguration) -> some View {
        Text(overflowCaption(for: island) ?? (island.placement.edge == .leading ? "Left edge" : "Right edge"))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(IslandChrome.secondaryText)
            .padding(8)
    }

    private func canvasCaption(for island: IslandConfiguration) -> String {
        let placement = island.placement.mode == .automatic ? "Automatic placement" : "Manual placement"
        if let overflow = overflowCaption(for: island) {
            return "\(placement) · \(overflow)"
        }
        return "\(placement) · \(island.complications.count) widget\(island.complications.count == 1 ? "" : "s")"
    }

    private func overflowCaption(for island: IslandConfiguration) -> String? {
        let maxHeight = IslandMetrics.maximumHeight(
            visibleFrameHeight: NSScreen.main?.visibleFrame.height ?? 900
        )
        let capacity = IslandMetrics.maxProviderCount(forHeight: maxHeight)
        let shown = min(runtime.visibleComplications(on: island).count, capacity)
        let hidden = max(0, runtime.visibleComplications(on: island).count - shown)
        guard hidden > 0 else { return nil }
        return "\(shown) shown · \(hidden) off-screen"
    }

    private func complicationOrderPane(_ island: IslandConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: "Widgets")
                Spacer()
                StatusChip(text: "\(island.complications.count)")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            SettingsHairline()

            if island.complications.isEmpty {
                emptyComplications
            } else {
                List {
                    ForEach(Array(island.complications.enumerated()), id: \.element.id) { index, complication in
                        complicationRow(complication, index: index, island: island)
                            // Plain macOS lists reserve eight points before each
                            // cell, and a hidden scroller reserves the same at the
                            // trailing edge. Cancel both so the row chrome is flush.
                            .listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .destructiveSwipeAction(
                                accessibilityName: "Delete \(runtime.descriptor(sourceID: complication.sourceID)?.name ?? "complication")",
                                showsSeparator: true,
                                actionHeight: 60
                            ) {
                                deleteComplication(complication, from: island)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ComplicationDropDelegate(
                                    targetID: complication.id,
                                    draggedID: draggedComplicationID,
                                    setTargeted: { targeted in
                                        dropTargetID = targeted ? complication.id : nil
                                    },
                                    move: { draggedID, targetID in
                                        moveComplication(draggedID, over: targetID, in: island.id)
                                    },
                                    finish: finishComplicationDrag
                                )
                            )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, 1)
            }

            SettingsHairline()

            Text("Drag to reorder · Select a widget to edit")
                .font(.system(size: 11))
                .foregroundStyle(IslandChrome.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)

        }
    }

    private var emptyIslandsCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .medium))
            Text("No islands yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Choose a starter stack, or add an empty island.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IslandChrome.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                QuietButton(title: "Browse collections", symbol: "square.grid.2x2", prominence: .primary) {
                    runtime.workspaceStore.addIsland()
                    catalogSourceID = nil
                    presentsGallery = true
                }
                QuietButton(title: "Add Island", symbol: "plus") {
                    runtime.workspaceStore.addIsland()
                }
            }
        }
        .foregroundStyle(IslandChrome.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyComplications: some View {
        Button {
            catalogSourceID = nil
            presentsGallery = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .medium))
                Text("Add your first widget")
                    .font(.system(size: 14, weight: .semibold))
                Text("Choose usage, system information or a clock.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandChrome.secondaryText)
            }
            .foregroundStyle(IslandChrome.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .buttonStyle(.plain)
    }

    private func complicationRow(
        _ complication: ComplicationConfiguration,
        index: Int,
        island: IslandConfiguration
    ) -> some View {
        let descriptor = runtime.descriptor(sourceID: complication.sourceID)
        let selected = runtime.workspaceStore.selectedComplicationID == complication.id
        let summary = metricSummary(complication, descriptor: descriptor)

        return configuredComplicationRow(
            complicationRowContent(
                complication,
                descriptor: descriptor,
                summary: summary,
                island: island
            ),
            complication: complication,
            index: index,
            island: island,
            selected: selected
        )
    }

    private func complicationRowContent(
        _ complication: ComplicationConfiguration,
        descriptor: ComplicationSourceDescriptor?,
        summary: String,
        island: IslandConfiguration
    ) -> some View {
        HStack(spacing: 9) {
            ComplicationSlotView(
                complication: complication,
                descriptor: descriptor,
                values: runtime.values(for: complication),
                sourceError: runtime.snapshot(sourceID: complication.sourceID)?.errorDescription,
                quality: runtime.quality(for: complication),
                trendDirection: runtime.trendDirection(for: complication)
            )
            .frame(width: 44, height: 56)
            .background(IslandPalette.surface, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(complication.sourceID == HarnaisWeeklyStarter.sourceID && !summary.isEmpty ? summary : (descriptor?.name ?? complication.sourceID))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(IslandChrome.text)
                        .lineLimit(1)
                    if !complication.isVisible || runtime.isHiddenBySource(complication) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IslandChrome.secondaryText)
                    }
                }
                Text(
                    (runtime.isHiddenBySource(complication) ? "Hidden in Harnais · " : (complication.isVisible ? "" : "Hidden · "))
                        + complication.family.displayName
                        + (complication.sourceID == HarnaisWeeklyStarter.sourceID ? " · Harnais" : (summary.isEmpty ? "" : " · \(summary)"))
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandChrome.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                complicationActions(complication, island: island)
            } label: {
                RowActionGlyph(symbol: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More actions")

            RowActionGlyph(symbol: "line.3.horizontal")
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onDrag {
                    beginComplicationDrag(complication.id, in: island)
                    return NSItemProvider(object: complication.id.uuidString as NSString)
                } preview: {
                    complicationDragPreview(complication, descriptor: descriptor)
                }
                .help("Drag to reorder")
                .accessibilityLabel("Drag to reorder \(summary.isEmpty ? (descriptor?.name ?? complication.sourceID) : summary)")
        }
    }

    private func configuredComplicationRow<Content: View>(
        _ content: Content,
        complication: ComplicationConfiguration,
        index: Int,
        island: IslandConfiguration,
        selected: Bool
    ) -> some View {
        content
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(selected ? IslandChrome.selectedFill : Color.clear)
        .overlay(alignment: .top) {
            if dropTargetID == complication.id {
                Rectangle().fill(IslandChrome.insertMark).frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(IslandChrome.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .opacity(complication.isVisible ? 1 : 0.64)
        .onTapGesture {
            runtime.workspaceStore.selectedComplicationID = complication.id
        }
        .contextMenu {
            complicationActions(complication, island: island)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Move Up") {
            moveComplication(at: index, by: -1, in: island)
        }
        .accessibilityAction(named: "Move Down") {
            moveComplication(at: index, by: 1, in: island)
        }
    }

    @ViewBuilder
    private func complicationActions(
        _ complication: ComplicationConfiguration,
        island: IslandConfiguration
    ) -> some View {
        Button {
            runtime.workspaceStore.selectedComplicationID = complication.id
        } label: {
            Label("Configure…", systemImage: "slider.horizontal.3")
        }
        Button {
            runtime.workspaceStore.duplicateComplication(complication.id, in: island.id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            runtime.workspaceStore.updateComplication(complication.id, in: island.id) {
                $0.isVisible.toggle()
            }
        } label: {
            Label(
                complication.isVisible ? "Hide from Island" : "Show on Island",
                systemImage: complication.isVisible ? "eye.slash" : "eye"
            )
        }
        Divider()
        Button(role: .destructive) {
            deleteComplication(complication, from: island)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func complicationDragPreview(
        _ complication: ComplicationConfiguration,
        descriptor: ComplicationSourceDescriptor?
    ) -> some View {
        HStack(spacing: 9) {
            ComplicationSlotView(
                complication: complication,
                descriptor: descriptor,
                values: runtime.values(for: complication),
                sourceError: runtime.snapshot(sourceID: complication.sourceID)?.errorDescription,
                quality: runtime.quality(for: complication),
                trendDirection: runtime.trendDirection(for: complication)
            )
            .frame(width: 38, height: 44)
            .accessibilityHidden(true)
            Text(descriptor?.name ?? complication.sourceID)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IslandChrome.text)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 54)
        .background(IslandChrome.surface, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                .strokeBorder(IslandChrome.selectionBorder, lineWidth: 1)
        }
    }

    private func beginComplicationDrag(_ id: UUID, in island: IslandConfiguration) {
        draggedComplicationID = id
        dragOriginOrder = island.complications.map(\.id)
        dropTargetID = nil
        runtime.workspaceStore.selectedComplicationID = id
    }

    private func moveComplication(_ draggedID: UUID, over targetID: UUID, in islandID: UUID) {
        guard let island = runtime.workspaceStore.island(id: islandID),
              let sourceIndex = island.complications.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = island.complications.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex
        else { return }
        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        runtime.workspaceStore.moveComplications(
            from: IndexSet(integer: sourceIndex),
            to: destination,
            in: islandID
        )
    }

    private func finishComplicationDrag() {
        defer {
            draggedComplicationID = nil
            dragOriginOrder = []
            dropTargetID = nil
        }
        guard let island = runtime.workspaceStore.selectedIsland,
              !dragOriginOrder.isEmpty,
              dragOriginOrder != island.complications.map(\.id)
        else { return }
        presentUndo(
            message: "Complication order changed",
            action: .order(islandID: island.id, ids: dragOriginOrder)
        )
    }

    private func moveComplication(at index: Int, by offset: Int, in island: IslandConfiguration) {
        let target = index + offset
        guard island.complications.indices.contains(index), island.complications.indices.contains(target) else { return }
        let before = island.complications.map(\.id)
        runtime.workspaceStore.moveComplications(
            from: IndexSet(integer: index),
            to: offset < 0 ? target : target + 1,
            in: island.id
        )
        presentUndo(message: "Complication order changed", action: .order(islandID: island.id, ids: before))
    }

    private func deleteComplication(
        _ complication: ComplicationConfiguration,
        from island: IslandConfiguration
    ) {
        guard let removal = runtime.workspaceStore.removeComplication(complication.id, from: island.id) else { return }
        let name = runtime.descriptor(sourceID: complication.sourceID)?.name ?? complication.sourceID
        presentUndo(message: "\(name) removed", action: .removal(removal))
    }

    private func deleteIsland(_ island: IslandConfiguration) {
        guard let removal = runtime.workspaceStore.removeIsland(island.id) else { return }
        presentUndo(message: "\(island.name) removed", action: .islandRemoval(removal))
    }


    private func presentUndo(message: String, action: WorkspaceUndoAction) {
        withAnimation(.easeOut(duration: 0.16)) {
            pendingUndo = WorkspaceUndo(message: message, action: action)
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let pendingUndo {
            HStack(spacing: 10) {
                Text(pendingUndo.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Button("Undo") {
                    performUndo(pendingUndo.action)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.58, green: 0.72, blue: 1))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: pendingUndo.id) {
                try? await Task.sleep(for: .seconds(6))
                guard self.pendingUndo?.id == pendingUndo.id else { return }
                withAnimation(.easeIn(duration: 0.14)) { self.pendingUndo = nil }
            }
        }
    }

    private func performUndo(_ action: WorkspaceUndoAction) {
        switch action {
        case .removal(let removal):
            runtime.workspaceStore.restoreComplication(removal)
        case .islandRemoval(let removal):
            runtime.workspaceStore.restoreIsland(removal)
        case .order(let islandID, let ids):
            runtime.workspaceStore.setComplicationOrder(ids, in: islandID)
        }
        withAnimation(.easeInOut(duration: 0.14)) { pendingUndo = nil }
    }

    private func metricSummary(
        _ complication: ComplicationConfiguration,
        descriptor: ComplicationSourceDescriptor?
    ) -> String {
        HarnaisGlance.metricSummary(
            sourceID: complication.sourceID,
            metricIDs: complication.metricIDs,
            descriptor: descriptor
        )
    }

    @ViewBuilder
    private var inspector: some View {
        if let island = runtime.workspaceStore.selectedIsland {
            ScrollView {
                VStack(alignment: .leading, spacing: IslandChrome.stackSpacing) {
                    if let complication = runtime.workspaceStore.selectedComplication,
                       island.complications.contains(where: { $0.id == complication.id }) {
                        ComplicationInspector(
                            runtime: runtime,
                            island: island,
                            complication: complication,
                            configureSource: configureSource,
                            delete: { deleteComplication(complication, from: island) }
                        )
                        .id(complication.id)
                    } else {
                        IslandInspector(
                            runtime: runtime,
                            island: island,
                            delete: { deleteIsland(island) }
                        )
                    }
                }
                .padding(.horizontal, IslandChrome.pageInset)
                .padding(.top, IslandChrome.pageTop)
                .padding(.bottom, IslandChrome.pageBottom)
            }
            .scrollIndicators(.hidden)
        }
    }
}
