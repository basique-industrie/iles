import AppKit
import Domain
import IslandGeometry
import SwiftUI

struct IslandInspector: View {
    @Bindable var runtime: IslandRuntime
    let island: IslandConfiguration
    let delete: () -> Void
    @State private var topGapDraft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            identity
            SettingsHairline()
            placement
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            PageTitle(title: "Island")
            Spacer()
            Menu {
                Button {
                    runtime.workspaceStore.duplicateIsland(island.id)
                } label: {
                    Label("Duplicate Island", systemImage: "plus.square.on.square")
                }
                Divider()
                Button(role: .destructive, action: delete) {
                    Label("Delete Island", systemImage: "trash")
                }
            } label: {
                RowActionGlyph(symbol: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Island actions")
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            IslandNameEditor(store: runtime.workspaceStore, island: island)
                .id(island.id)
            SettingsToggleRow(title: "Visible", isOn: visibility,
                              horizontalPadding: 0, verticalPadding: 6)
            if island.complications.contains(where: { $0.sourceID == HarnaisWeeklyStarter.sourceID }) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsToggleRow(title: "Include new Harnais accounts", isOn: Binding(
                        get: { island.followsHarnaisAccounts == true },
                        set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.followsHarnaisAccounts = value } }
                    ), horizontalPadding: 0, verticalPadding: 6)
                    Text("Removing a Harnais widget turns off automatic additions for this island.")
                        .font(.system(size: 12))
                        .foregroundStyle(IslandChrome.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var placement: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Placement")
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(title: "Display")
                displayPicker
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(title: "Screen edge")
                IslandSegmentBar(items: IslandEdge.allCases, selection: edge, title: { $0 == .leading ? "Left" : "Right" })
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(title: "Position")
                IslandSegmentBar(items: IslandPlacementMode.allCases, selection: mode, title: { $0 == .automatic ? "Automatic" : "Manual" })
            }
            if island.placement.mode == .manual {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        FieldLabel(title: "Top spacing")
                        Spacer()
                        Text("\(Int(topGap.wrappedValue)) pt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(IslandChrome.text)
                            .monospacedDigit()
                    }
                    SettingsSlider(
                        value: topGap,
                        range: topGapRange,
                        onEditingChanged: topGapEditingChanged
                    )
                    .accessibilityLabel("Top spacing")
                    .accessibilityValue("\(Int(topGap.wrappedValue)) points")
                }
            }
        }
    }

    private var displayPicker: some View {
        Menu {
            Button {
                display.wrappedValue = .main
            } label: {
                Label("Main Display", systemImage: island.placement.display == .main ? "checkmark" : "display")
            }
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                let target = IslandDisplayTarget.display(screenIdentifier(screen, fallback: index))
                Button {
                    display.wrappedValue = target
                } label: {
                    Label(screen.localizedName, systemImage: island.placement.display == target ? "checkmark" : "display")
                }
            }
        } label: {
            SettingsMenuLabel(symbol: "display", title: displayName(for: island.placement.display))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Display")
        .help("Choose which display hosts this island")
    }

    private var visibility: Binding<Bool> {
        Binding(get: { island.isVisible }, set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.isVisible = value } })
    }

    private var edge: Binding<IslandEdge> {
        Binding(get: { island.placement.edge }, set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.placement.edge = value } })
    }

    private var display: Binding<IslandDisplayTarget> {
        Binding(get: { island.placement.display }, set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.placement.display = value } })
    }

    private var mode: Binding<IslandPlacementMode> {
        Binding(get: { island.placement.mode }, set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.placement.mode = value } })
    }

    private var topGapRange: ClosedRange<Double> {
        let screen: NSScreen?
        switch island.placement.display {
        case .main: screen = NSScreen.main
        case .display(let identifier):
            screen = NSScreen.screens.enumerated().first {
                screenIdentifier($0.element, fallback: $0.offset) == identifier
            }?.element ?? NSScreen.main
        }
        let visibleHeight = screen?.visibleFrame.height ?? 900
        let maximumHeight = IslandMetrics.maximumHeight(visibleFrameHeight: visibleHeight)
        let height = min(IslandMetrics.height(forProviderCount: runtime.visibleComplications(on: island).count), maximumHeight)
        let maximumGap = IslandPlacement.clampedTopGap(.greatestFiniteMagnitude, islandHeight: height, visibleHeight: visibleHeight)
        return Double(IslandMetrics.topGap)...max(Double(IslandMetrics.topGap), Double(maximumGap))
    }

    private var topGap: Binding<Double> {
        Binding(
            get: { min(max(topGapDraft ?? island.placement.topGap, topGapRange.lowerBound), topGapRange.upperBound) },
            set: { value in
                topGapDraft = value
                runtime.previewIslandTopGap(island.id, value: value)
            }
        )
    }

    private func topGapEditingChanged(_ editing: Bool) {
        if editing {
            topGapDraft = topGapDraft ?? island.placement.topGap
            return
        }
        guard let value = topGapDraft else { return }
        runtime.workspaceStore.updateIsland(island.id) { $0.placement.topGap = value }
        topGapDraft = nil
        runtime.previewIslandTopGap(island.id, value: nil)
    }

    private func screenIdentifier(_ screen: NSScreen, fallback: Int) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "display-\(fallback)"
    }

    private func displayName(for target: IslandDisplayTarget) -> String {
        switch target {
        case .main:
            return "Main Display"
        case .display(let identifier):
            for (index, screen) in NSScreen.screens.enumerated()
            where screenIdentifier(screen, fallback: index) == identifier {
                return screen.localizedName
            }
            return "Saved Display"
        }
    }
}

/// Keep partially typed names out of the store: its normalization is appropriate
/// when saving, but trims spaces and replaces empty text during live editing.
private struct IslandNameEditor: View {
    let store: IslandWorkspaceStore
    let island: IslandConfiguration
    @State private var draft: String
    @State private var savedName: String

    init(store: IslandWorkspaceStore, island: IslandConfiguration) {
        self.store = store
        self.island = island
        _draft = State(initialValue: island.name)
        _savedName = State(initialValue: island.name)
    }

    var body: some View {
        IslandTextField(title: "Name", text: $draft, prompt: "Main Island", onCommit: commit)
            .onChange(of: island.name) { _, newName in
                // External updates may arrive while the user is typing. Only
                // refresh an untouched field; an active draft belongs to them.
                if draft == savedName { draft = newName }
                savedName = newName
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft != savedName,
              let current = store.island(id: island.id)
        else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            draft = current.name
            savedName = current.name
            return
        }
        if name != current.name {
            store.updateIsland(island.id) { $0.name = name }
        }
        draft = store.island(id: island.id)?.name ?? current.name
        savedName = draft
    }
}
