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
        header
        identity
        SettingsHairline()
        placement
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
        SettingsGroup(title: "Identity") {
            IslandTextField(title: "Name", text: name, prompt: "Main Island") {}
            SettingsToggleRow(title: "Visible", isOn: visibility)
        }
    }

    private var placement: some View {
        SettingsGroup(title: "Placement") {
            FieldLabel(title: "Display")
            displayPicker
            FieldLabel(title: "Screen edge")
            IslandSegmentBar(items: IslandEdge.allCases, selection: edge, title: { $0 == .leading ? "Left" : "Right" })
            FieldLabel(title: "Mode")
            IslandSegmentBar(items: IslandPlacementMode.allCases, selection: mode, title: { $0 == .automatic ? "Automatic" : "Manual" })
            if island.placement.mode == .manual {
                HStack {
                    Text("Top spacing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandChrome.secondaryText)
                    Spacer()
                    Text("\(Int(topGap.wrappedValue)) pt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                SettingsSlider(
                    value: topGap,
                    range: 8...600,
                    onEditingChanged: topGapEditingChanged
                )
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
            SettingsMenuLabel(
                symbol: "display",
                title: displayName(for: island.placement.display)
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
        .settingsPopupChrome()
        .accessibilityLabel("Display")
        .help("Choose which display hosts this island")
    }

    private var name: Binding<String> {
        Binding(get: { island.name }, set: { value in runtime.workspaceStore.updateIsland(island.id) { $0.name = value } })
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

    private var topGap: Binding<Double> {
        Binding(
            get: { topGapDraft ?? island.placement.topGap },
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
