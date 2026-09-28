import AppKit
import Domain
import IslandGeometry
import Observation
import SwiftUI

/// Owns one panel per configured island and one shared detail panel.
@MainActor
final class IslandWindowCoordinator {
    private let runtime: IslandRuntime
    private var panels: [UUID: FloatingPanel] = [:]
    private var hosts: [UUID: ScaleAwareHostingView<IslandView>] = [:]
    private var hostMaxHeights: [UUID: CGFloat] = [:]
    private let detailPanel: FloatingPanel
    private var detailWasPinned = false
    private var detailTransitionTask: Task<Void, Never>?
    private var detailTargetFrame: NSRect?
    private var detailHost: ScaleAwareHostingView<ComplicationDetailView>?
    private var frames: [UUID: NSRect] = [:]
    private var screenObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var moveMonitor: Any?
    private var syncTask: Task<Void, Never>?
    private var placementSyncTask: Task<Void, Never>?
    private var previewTopGaps: [UUID: CGFloat] = [:]
    private var observationStarted = false

    private var draggingIslandID: UUID?
    private var isDraggingEmptyWorkspace = false
    private var dragStartGap: CGFloat = 0
    private var dragCurrentGap: CGFloat?
    private var dragStartMouseY: CGFloat = 0
    private var emptyWorkspacePanel: FloatingPanel?
    private var emptyHintPanel: FloatingPanel?
    private var hintObserver: NSObjectProtocol?

    init(runtime: IslandRuntime) {
        self.runtime = runtime
        detailPanel = FloatingPanel(
            size: NSSize(width: IslandMetrics.providerWindowWidth, height: IslandMetrics.providerWindowHeight)
        )
        detailPanel.hasShadow = false
        detailPanel.ignoresMouseEvents = false

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile(animated: false) }
        }
        runtime.islandTopGapPreviewHandler = { [weak self] islandID, value in
            self?.previewTopGap(for: islandID, value: value)
        }
        hintObserver = NotificationCenter.default.addObserver(
            forName: .emptyWorkspaceHintDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileEmptyWorkspace(self?.runtime.workspaceStore.visibleIslands.isEmpty == true)
            }
        }
        startObservation()
        installMoveMonitor()
    }

    func show() {
        reconcile(animated: false)
        for panel in panels.values { panel.orderFrontRegardless() }
        syncDetail()
    }

    func tearDown() {
        syncTask?.cancel()
        placementSyncTask?.cancel()
        runtime.islandTopGapPreviewHandler = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        removeClickMonitor()
        removeMoveMonitor()
        hideDetail()
        if let hintObserver {
            NotificationCenter.default.removeObserver(hintObserver)
            self.hintObserver = nil
        }
        emptyHintPanel?.orderOut(nil)
        emptyHintPanel = nil
        emptyWorkspacePanel?.orderOut(nil)
        emptyWorkspacePanel = nil
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        hosts.removeAll()
        hostMaxHeights.removeAll()
        previewTopGaps.removeAll()
    }

    private func startObservation() {
        guard !observationStarted else { return }
        observationStarted = true
        trackRuntime()
    }

    private func trackRuntime() {
        Observation.withObservationTracking { [runtime] in
            // SwiftUI hosts observe snapshot/provider data themselves. The
            // coordinator only needs state that can change panel geometry or
            // which detail panel is shown.
            _ = runtime.workspaceStore.workspace
            _ = runtime.selection
            _ = runtime.isWindowPinned
            _ = runtime.provider(id: HarnaisWeeklyStarter.sourceID)?.snapshot?.hiddenQuotaTypes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSync()
                self.trackRuntime()
            }
        }
    }

    private func scheduleSync() {
        // Pull the latest observable state once per display cadence. Debouncing
        // continuous controls makes the island trail the pointer until dragging
        // pauses, while throttling keeps motion live without redundant layouts.
        guard syncTask == nil else { return }
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else {
                self.syncTask = nil
                return
            }
            self.syncTask = nil
            self.reconcile(animated: true)
            self.syncDetail()
        }
    }

    private func previewTopGap(for islandID: UUID, value: Double?) {
        if let value {
            previewTopGaps[islandID] = CGFloat(value)
        } else {
            previewTopGaps[islandID] = nil
        }
        guard placementSyncTask == nil else { return }
        placementSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(8))
            guard !Task.isCancelled else {
                self.placementSyncTask = nil
                return
            }
            self.placementSyncTask = nil
            self.syncPlacementFrames()
        }
    }

    /// Placement-only synchronization avoids rebuilding SwiftUI hosts or
    /// redrawing panel contents while a slider is moving.
    private func syncPlacementFrames() {
        let visible = runtime.workspaceStore.visibleIslands
        let nextFrames = layoutFrames(for: visible)
        for island in visible {
            guard let frame = nextFrames[island.id], let panel = panels[island.id] else { continue }
            frames[island.id] = frame
            if draggingIslandID != island.id, panel.frame.origin != frame.origin {
                panel.setFrameOrigin(frame.origin)
            }
        }
    }

    private func reconcile(animated: Bool) {
        let visible = runtime.workspaceStore.visibleIslands
        reconcileEmptyWorkspace(visible.isEmpty)
        let visibleIDs = Set(visible.map(\.id))

        for id in panels.keys where !visibleIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels[id] = nil
            hosts[id] = nil
            hostMaxHeights[id] = nil
            frames[id] = nil
        }

        let nextFrames = layoutFrames(for: visible)
        for island in visible {
            guard let frame = nextFrames[island.id] else { continue }
            let maxHeight = maximumHeight(for: screen(for: island.placement.display))
            let panel = panel(for: island, maxHeight: maxHeight)
            if let previousMaxHeight = hostMaxHeights[island.id],
               abs(previousMaxHeight - maxHeight) > 0.5 {
                hosts[island.id]?.rootView = IslandView(
                    runtime: runtime,
                    islandID: island.id,
                    maxHeight: maxHeight
                )
                hostMaxHeights[island.id] = maxHeight
            }
            let previous = frames[island.id]
            frames[island.id] = frame
            let frameChanged = previous != frame
            let heightChanged = previous.map { abs($0.height - frame.height) > 0.5 } ?? false
            if frameChanged, animated, heightChanged, panel.isVisible, draggingIslandID != island.id {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            } else if frameChanged, draggingIslandID != island.id {
                panel.setFrame(frame, display: true)
            }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func panel(for island: IslandConfiguration, maxHeight: CGFloat) -> FloatingPanel {
        if let panel = panels[island.id] { return panel }
        let height = min(
            IslandMetrics.height(forProviderCount: runtime.visibleComplications(on: island).count),
            maxHeight
        )
        let panel = FloatingPanel(size: NSSize(width: IslandMetrics.width, height: height))
        let host = ScaleAwareHostingView(rootView: IslandView(runtime: runtime, islandID: island.id, maxHeight: maxHeight))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        panels[island.id] = panel
        hosts[island.id] = host
        hostMaxHeights[island.id] = maxHeight
        return panel
    }

    private func reconcileEmptyWorkspace(_ isEmpty: Bool) {
        guard isEmpty else {
            EmptyWorkspaceHint.dismiss()
            emptyHintPanel?.orderOut(nil)
            emptyWorkspacePanel?.orderOut(nil)
            return
        }
        let placement = runtime.workspaceStore.workspace.emptyIslandPlacement
        let screen = screen(for: placement.display)
        let maxHeight = maximumHeight(for: screen)
        let height = min(IslandMetrics.height(forProviderCount: 0), maxHeight)
        let panel = emptyWorkspacePanel ?? makeEmptyWorkspacePanel(edge: placement.edge, height: height)
        emptyWorkspacePanel = panel
        if let host = panel.contentView as? ScaleAwareHostingView<EmptyWorkspaceIslandView> {
            host.rootView = EmptyWorkspaceIslandView(edge: placement.edge)
        }
        guard let screen else {
            panel.orderFrontRegardless()
            reconcileEmptyHint(relativeTo: panel.frame, edge: placement.edge)
            return
        }
        let gap = IslandPlacement.clampedTopGap(
            CGFloat(placement.topGap),
            islandHeight: height,
            visibleHeight: screen.visibleFrame.height
        )
        if !isDraggingEmptyWorkspace {
            panel.setFrame(
                NSRect(
                    x: originX(for: placement.edge, on: screen),
                    y: IslandPlacement.originY(
                        topGap: gap,
                        islandHeight: height,
                        visibleMaxY: screen.visibleFrame.maxY
                    ),
                    width: IslandMetrics.width,
                    height: height
                ),
                display: true
            )
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        reconcileEmptyHint(relativeTo: panel.frame, edge: placement.edge)
    }

    private func reconcileEmptyHint(relativeTo plus: NSRect, edge: IslandEdge) {
        guard EmptyWorkspaceHint.isVisible else {
            emptyHintPanel?.orderOut(nil)
            return
        }
        let panel = emptyHintPanel ?? makeEmptyHintPanel()
        emptyHintPanel = panel
        panel.setFrame(EmptyWorkspaceHint.frame(relativeTo: plus, edge: edge), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makeEmptyHintPanel() -> FloatingPanel {
        let panel = FloatingPanel(
            size: NSSize(width: EmptyWorkspaceHintMetrics.width, height: EmptyWorkspaceHintMetrics.height)
        )
        let host = ScaleAwareHostingView(
            rootView: EmptyWorkspaceHintView(
                onOpen: {
                    EmptyWorkspaceHint.dismiss()
                    NotificationCenter.default.post(name: .showIslandSettings, object: nil)
                },
                onDismiss: {
                    EmptyWorkspaceHint.dismiss()
                }
            )
        )
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        return panel
    }

    private func makeEmptyWorkspacePanel(edge: IslandEdge, height: CGFloat) -> FloatingPanel {
        let panel = FloatingPanel(size: NSSize(width: IslandMetrics.width, height: height))
        let host = ScaleAwareHostingView(rootView: EmptyWorkspaceIslandView(edge: edge))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        return panel
    }

    private struct LayoutKey: Hashable {
        let screenNumber: String
        let edge: IslandEdge
    }

    private func layoutFrames(for islands: [IslandConfiguration]) -> [UUID: NSRect] {
        var result: [UUID: NSRect] = [:]
        var cursors: [LayoutKey: CGFloat] = [:]

        for island in islands {
            guard let screen = screen(for: island.placement.display) else { continue }
            let maxHeight = maximumHeight(for: screen)
            let capacity = IslandMetrics.maxProviderCount(forHeight: maxHeight)
            let height = min(
                IslandMetrics.height(forProviderCount: min(runtime.visibleComplications(on: island).count, capacity)),
                maxHeight
            )
            let key = LayoutKey(screenNumber: screenIdentifier(screen), edge: island.placement.edge)
            let desired = previewTopGaps[island.id] ?? CGFloat(island.placement.topGap)
            let current = cursors[key] ?? IslandMetrics.topGap
            let rawGap = island.placement.mode == .automatic ? max(current, desired) : desired
            let gap = IslandPlacement.clampedTopGap(
                rawGap,
                islandHeight: height,
                visibleHeight: screen.visibleFrame.height
            )
            cursors[key] = max(current, gap + height + 12)
            result[island.id] = NSRect(
                x: originX(for: island.placement.edge, on: screen),
                y: IslandPlacement.originY(
                    topGap: gap,
                    islandHeight: height,
                    visibleMaxY: screen.visibleFrame.maxY
                ),
                width: IslandMetrics.width,
                height: height
            )
        }
        return result
    }

    private func originX(for edge: IslandEdge, on screen: NSScreen) -> CGFloat {
        switch edge {
        case .trailing:
            let dockOnRight = screen.frame.maxX - screen.visibleFrame.maxX > 12
            let maxX = dockOnRight ? screen.visibleFrame.maxX : screen.frame.maxX
            return maxX - IslandMetrics.width
        case .leading:
            let dockOnLeft = screen.visibleFrame.minX - screen.frame.minX > 12
            return dockOnLeft ? screen.visibleFrame.minX : screen.frame.minX
        }
    }

    private func maximumHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 900 }
        return IslandMetrics.maximumHeight(visibleFrameHeight: screen.visibleFrame.height)
    }

    private func syncDetail() {
        guard let selection = runtime.selection,
              let complication = runtime.selectedComplication,
              !runtime.isHiddenBySource(complication),
              let island = runtime.selectedIsland,
              let islandFrame = frames[selection.islandID]
        else {
            hideDetail()
            return
        }

        let detailFrame = popoverFrame(island: island, islandFrame: islandFrame, complicationID: complication.id,
                                       height: ComplicationDetailView.preferredHeight(runtime: runtime, complication: complication))
        let pointerY = pointerY(
            island: island,
            islandFrame: islandFrame,
            popoverFrame: detailFrame,
            complicationID: complication.id
        )
        let pointerTrailing = island.placement.edge == .trailing
        let view = ComplicationDetailView(
            runtime: runtime,
            complication: complication,
            pointerY: pointerY,
            pointerOnTrailingEdge: pointerTrailing
        )
        if let detailHost {
            detailHost.rootView = view
        } else {
            let host = ScaleAwareHostingView(rootView: view)
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            detailPanel.contentView = host
            detailHost = host
        }
        positionDetail(at: detailFrame, edge: island.placement.edge)
        if runtime.isWindowPinned && !detailWasPinned {
            detailPanel.makeKeyAndOrderFront(nil)
        } else {
            detailPanel.orderFrontRegardless()
        }
        detailWasPinned = runtime.isWindowPinned
        installClickMonitor()
    }

    /// A short, cancellable transition keeps the card attached to the hovered
    /// row. Each new target starts at the currently displayed position, never
    /// at an obsolete destination from an earlier hover.
    private func positionDetail(at target: NSRect, edge: IslandEdge) {
        let entering = !detailPanel.isVisible
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard entering || detailTargetFrame != target || reduceMotion else { return }
        detailTransitionTask?.cancel()
        detailTransitionTask = nil
        detailTargetFrame = target

        guard !reduceMotion else {
            detailPanel.alphaValue = 1
            detailPanel.setFrame(target, display: true)
            return
        }

        var start = detailPanel.frame
        // Resize immediately so the text reflows once, rather than on every
        // animation frame. Only the card's position and entrance opacity move.
        start.size = target.size
        if entering {
            start.origin = target.origin
            start.origin.x += edge == .trailing ? 4 : -4
            detailPanel.alphaValue = 0
        }
        detailPanel.setFrame(start, display: true)
        let initialAlpha = detailPanel.alphaValue
        let duration = entering ? 0.14 : 0.12
        let startedAt = ProcessInfo.processInfo.systemUptime
        detailTransitionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                let fraction = min(elapsed / duration, 1)
                let eased = CGFloat(1 - pow(1 - fraction, 3))
                let noMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                if fraction >= 1 || noMotion {
                    self.detailPanel.setFrame(target, display: true)
                    self.detailPanel.alphaValue = 1
                    self.detailTransitionTask = nil
                    return
                }
                self.detailPanel.setFrameOrigin(NSPoint(
                    x: start.minX + (target.minX - start.minX) * eased,
                    y: start.minY + (target.minY - start.minY) * eased
                ))
                self.detailPanel.alphaValue = initialAlpha + (1 - initialAlpha) * eased
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
            }
        }
    }

    private func hideDetail() {
        detailTransitionTask?.cancel()
        detailTransitionTask = nil
        detailTargetFrame = nil
        detailPanel.orderOut(nil)
        detailPanel.alphaValue = 1
        detailWasPinned = false
        removeClickMonitor()
    }

    private func selectedSlotCenterY(
        island: IslandConfiguration,
        islandFrame: NSRect,
        complicationID: UUID
    ) -> CGFloat {
        guard let index = runtime.visibleComplications(on: island).firstIndex(where: { $0.id == complicationID }) else {
            return islandFrame.midY
        }
        let islandY = IslandMetrics.ringCenterY(index: index)
        return islandFrame.minY + (islandFrame.height - islandY)
    }

    private func popoverFrame(
        island: IslandConfiguration,
        islandFrame: NSRect,
        complicationID: UUID,
        height: CGFloat
    ) -> NSRect {
        let center = selectedSlotCenterY(island: island, islandFrame: islandFrame, complicationID: complicationID)
        var y = center - height / 2
        if let screen = panels[island.id]?.screen ?? screen(for: island.placement.display) {
            let minY = screen.visibleFrame.minY + 12
            let maxY = screen.visibleFrame.maxY - height - 12
            y = min(max(y, minY), max(minY, maxY))
        }
        let x: CGFloat
        switch island.placement.edge {
        case .trailing:
            x = islandFrame.minX - IslandMetrics.providerWindowGap - IslandMetrics.providerWindowWidth
        case .leading:
            x = islandFrame.maxX + IslandMetrics.providerWindowGap
        }
        return NSRect(x: x, y: y, width: IslandMetrics.providerWindowWidth, height: height)
    }

    private func pointerY(
        island: IslandConfiguration,
        islandFrame: NSRect,
        popoverFrame: NSRect,
        complicationID: UUID
    ) -> CGFloat {
        let fromBottom = selectedSlotCenterY(
            island: island,
            islandFrame: islandFrame,
            complicationID: complicationID
        ) - popoverFrame.minY
        return popoverFrame.height - fromBottom
    }

    private func screen(for target: IslandDisplayTarget) -> NSScreen? {
        switch target {
        case .main:
            return NSScreen.main ?? NSScreen.screens.first
        case .display(let id):
            return NSScreen.screens.first { screenIdentifier($0) == id }
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissIfClickOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissIfClickOutside()
            return event
        }
    }

    private func removeClickMonitor() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func dismissIfClickOutside() {
        guard runtime.selection != nil else { return }
        let mouse = NSEvent.mouseLocation
        if panels.values.contains(where: { $0.frame.contains(mouse) }) || detailPanel.frame.contains(mouse) {
            return
        }
        runtime.dismissWindow()
        hideDetail()
    }

    private func installMoveMonitor() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            let consumed = self.handleMoveEvent(event)
            return consumed ? nil : event
        }
    }

    private func removeMoveMonitor() {
        if let moveMonitor {
            NSEvent.removeMonitor(moveMonitor)
            self.moveMonitor = nil
        }
        if draggingIslandID != nil || isDraggingEmptyWorkspace { NSCursor.pop() }
        draggingIslandID = nil
        isDraggingEmptyWorkspace = false
        dragCurrentGap = nil
    }

    private func handleMoveEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard event.modifierFlags.contains(.command) else { return false }
            if beginEmptyWorkspaceDrag(event) { return true }
            guard let id = panels.first(where: { $0.value.windowNumber == event.windowNumber })?.key,
                  let island = runtime.workspaceStore.island(id: id),
                  let frame = frames[id],
                  let screen = panels[id]?.screen ?? screen(for: island.placement.display)
            else { return false }
            draggingIslandID = id
            runtime.dismissWindow()
            hideDetail()
            dragStartMouseY = NSEvent.mouseLocation.y
            dragStartGap = screen.visibleFrame.maxY - frame.maxY
            dragCurrentGap = dragStartGap
            NSCursor.resizeUpDown.push()
            return true
        case .leftMouseDragged:
            if isDraggingEmptyWorkspace { return moveEmptyWorkspace() }
            guard let id = draggingIslandID,
                  let island = runtime.workspaceStore.island(id: id),
                  let screen = panels[id]?.screen ?? screen(for: island.placement.display),
                  let frame = frames[id]
            else { return false }
            let gap = IslandPlacement.topGap(
                movingFrom: dragStartGap,
                mouseDeltaY: NSEvent.mouseLocation.y - dragStartMouseY,
                islandHeight: frame.height,
                visibleHeight: screen.visibleFrame.height
            )
            dragCurrentGap = gap
            var moved = frame
            moved.origin.y = IslandPlacement.originY(
                topGap: gap,
                islandHeight: frame.height,
                visibleMaxY: screen.visibleFrame.maxY
            )
            frames[id] = moved
            panels[id]?.setFrame(moved, display: true)
            return true
        case .leftMouseUp:
            if isDraggingEmptyWorkspace {
                if let gap = dragCurrentGap {
                    runtime.workspaceStore.updateEmptyIslandPlacement {
                        $0.mode = .manual
                        $0.topGap = Double(gap)
                    }
                }
                isDraggingEmptyWorkspace = false
                dragCurrentGap = nil
                NSCursor.pop()
                reconcile(animated: false)
                return true
            }
            guard let id = draggingIslandID else { return false }
            if let gap = dragCurrentGap {
                runtime.workspaceStore.updateIsland(id) {
                    $0.placement.mode = .manual
                    $0.placement.topGap = Double(gap)
                }
            }
            draggingIslandID = nil
            dragCurrentGap = nil
            NSCursor.pop()
            reconcile(animated: false)
            return true
        default:
            return false
        }
    }

    private func beginEmptyWorkspaceDrag(_ event: NSEvent) -> Bool {
        guard runtime.workspaceStore.visibleIslands.isEmpty,
              let panel = emptyWorkspacePanel,
              panel.windowNumber == event.windowNumber,
              let screen = panel.screen
                ?? screen(for: runtime.workspaceStore.workspace.emptyIslandPlacement.display)
        else { return false }
        isDraggingEmptyWorkspace = true
        dragStartMouseY = NSEvent.mouseLocation.y
        dragStartGap = screen.visibleFrame.maxY - panel.frame.maxY
        dragCurrentGap = dragStartGap
        NSCursor.resizeUpDown.push()
        return true
    }

    private func moveEmptyWorkspace() -> Bool {
        guard let panel = emptyWorkspacePanel,
              let screen = panel.screen
                ?? screen(for: runtime.workspaceStore.workspace.emptyIslandPlacement.display)
        else { return false }
        let frame = panel.frame
        let gap = IslandPlacement.topGap(
            movingFrom: dragStartGap,
            mouseDeltaY: NSEvent.mouseLocation.y - dragStartMouseY,
            islandHeight: frame.height,
            visibleHeight: screen.visibleFrame.height
        )
        dragCurrentGap = gap
        var moved = frame
        moved.origin.y = IslandPlacement.originY(
            topGap: gap,
            islandHeight: frame.height,
            visibleMaxY: screen.visibleFrame.maxY
        )
        panel.setFrame(moved, display: true)
        reconcileEmptyHint(
            relativeTo: moved,
            edge: runtime.workspaceStore.workspace.emptyIslandPlacement.edge
        )
        return true
    }
}

/// Kept as the app lifecycle's concise coordinator name.
typealias IslandController = IslandWindowCoordinator
