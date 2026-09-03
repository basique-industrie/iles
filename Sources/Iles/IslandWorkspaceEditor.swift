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
            islandSidebar
                .frame(width: 184)
                .background(IslandChrome.sidebarFill)
            divider
            canvas
                .frame(minWidth: 480, maxWidth: .infinity)
            divider
            inspector
                .frame(width: 430)
                .background(Color.black.opacity(0.12))
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

    private var islandSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: "My Islands")
                Spacer()
                QuietIconButton(
                    symbol: "plus",
                    accessibilityName: "Add island",
                    helpText: "Add a new island"
                ) {
                    runtime.workspaceStore.addIsland()
                }
            }
            .padding(12)

            List {
                ForEach(runtime.workspaceStore.islands) { island in
                    islandRow(island)
                        // Plain macOS lists add their own eight-point gutter.
                        // A small negative cell inset leaves a visible six-point
                        // margin without changing the sidebar's fixed width.
                        .listRowInsets(EdgeInsets(top: 3, leading: -2, bottom: 3, trailing: -2))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .destructiveSwipeAction(
                            accessibilityName: "Delete \(island.name)",
                            actionWidth: 56,
                            actionHeight: 56
                        ) {
                            deleteIsland(island)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 1)

            Spacer(minLength: 0)
        }
    }

    private func islandRow(_ island: IslandConfiguration) -> some View {
        let selected = runtime.workspaceStore.selectedIslandID == island.id
        let complicationCount = "\(island.complications.count) complication\(island.complications.count == 1 ? "" : "s")"
        let edgeName = island.placement.edge == .leading ? "Left edge" : "Right edge"

        return Button {
            runtime.workspaceStore.selectIsland(island.id)
        } label: {
            HStack(spacing: 9) {
                IslandPlacementBadge(
                    edge: island.placement.edge,
                    mode: island.placement.mode,
                    isVisible: island.isVisible
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(island.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(island.isVisible ? Color.white : IslandChrome.secondaryText)
                        .lineLimit(1)
                    Text("\(complicationCount) · \(edgeName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandChrome.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                selected ? IslandChrome.selectedFill : Color.clear,
                in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(selected ? IslandChrome.selectionBorder : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                toggleIslandVisibility(island)
            } label: {
                Label(
                    island.isVisible ? "Hide Island" : "Show Island",
                    systemImage: island.isVisible ? "eye.slash" : "eye"
                )
            }
            Divider()
            Button("Duplicate") { runtime.workspaceStore.duplicateIsland(island.id) }
            Button("Delete", role: .destructive) { deleteIsland(island) }
        }
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            if let island = runtime.workspaceStore.selectedIsland {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        PageTitle(title: island.name)
                        SettingsCaption(
                            text: "\(island.placement.mode == .automatic ? "Automatic placement" : "Manual placement") · \(island.complications.count) complication\(island.complications.count == 1 ? "" : "s")"
                        )
                    }
                    Spacer()
                    QuietButton(
                        title: "Add Complication…",
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
        .padding(IslandChrome.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func placementPane(_ island: IslandConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: "Placement")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            SettingsHairline()

            livePlacementPreview(island)
        }
        .background(Color.black.opacity(0.08))
    }

    private func livePlacementPreview(_ island: IslandConfiguration) -> some View {
        let naturalHeight = IslandMetrics.height(forProviderCount: island.visibleComplications.count)

        return GeometryReader { proxy in
            let availableHeight = max(proxy.size.height - 44, 1)
            let scale = min(1, availableHeight / max(naturalHeight, 1))

            ZStack(alignment: island.placement.edge == .leading ? .leading : .trailing) {
                Color.white.opacity(0.015)

                IslandView(
                    runtime: runtime,
                    islandID: island.id,
                    maxHeight: naturalHeight,
                    interactive: false,
                    selectedComplicationID: runtime.workspaceStore.selectedComplicationID
                )
                .frame(width: IslandMetrics.width, height: naturalHeight)
                .scaleEffect(scale)
                .frame(width: IslandMetrics.width * scale, height: naturalHeight * scale)
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
        let automatic = island.placement.mode == .automatic
        return HStack(spacing: 6) {
            Image(systemName: automatic ? "wand.and.stars" : "command")
                .font(.system(size: 10, weight: .semibold))
            Text(automatic
                ? "Automatic"
                : "⌘-drag to move")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(IslandChrome.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func complicationOrderPane(_ island: IslandConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: "Complication Order")
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

            VStack(spacing: 2) {
                Label("Drag to reorder", systemImage: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                Text("Swipe left to delete · Right-click for actions")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(IslandChrome.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .frame(height: 44)
        }
    }

    private var emptyIslandsCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .medium))
            Text("No islands yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose a starter stack, or add an empty island.")
                .font(.system(size: 11, weight: .medium))
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
        .foregroundStyle(.white)
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
                Text("Add your first complication")
                    .font(.system(size: 12, weight: .semibold))
                Text("Choose usage, battery, time, or session data.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandChrome.secondaryText)
            }
            .foregroundStyle(.white)
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
            .frame(width: 42, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(descriptor?.name ?? complication.sourceID)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !complication.isVisible {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandChrome.secondaryText)
                    }
                }
                Text(
                    (complication.isVisible ? "" : "Hidden · ")
                        + complication.family.displayName
                        + (summary.isEmpty ? "" : " · \(summary)")
                )
                .font(.system(size: 10, weight: .medium))
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
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onDrag {
                    beginComplicationDrag(complication.id, in: island)
                    return NSItemProvider(object: complication.id.uuidString as NSString)
                } preview: {
                    complicationDragPreview(complication, descriptor: descriptor)
                }
                .help("Drag to reorder")
                .accessibilityLabel("Drag to reorder \(descriptor?.name ?? complication.sourceID)")
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
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 54)
        .background(IslandPalette.popover, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
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

    private func toggleIslandVisibility(_ island: IslandConfiguration) {
        withAnimation(.easeInOut(duration: 0.16)) {
            runtime.workspaceStore.updateIsland(island.id) { $0.isVisible.toggle() }
        }
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Button("Undo") {
                    performUndo(pendingUndo.action)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.58, green: 0.72, blue: 1))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
        complication.metricIDs.map { id in
            descriptor?.metricName(for: id) ?? ComplicationMetricDescriptor.fallbackName(for: id)
        }.joined(separator: " + ")
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
                .padding(IslandChrome.pageInset)
            }
            .scrollIndicators(.hidden)
        }
    }
}
