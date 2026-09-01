import AppKit
import Domain
import Infrastructure
import IslandGeometry
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsSection: String, CaseIterable, Identifiable {
    case islands
    case sources
    case general
    case about

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .islands: "capsule.portrait"
        case .sources: "square.stack.3d.up"
        case .general: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .islands: "1"
        case .sources: "2"
        case .general: "3"
        case .about: "4"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .islands: "1"
        case .sources: "2"
        case .general: "3"
        case .about: "4"
        }
    }
}
/// Workspace editor inspired by complication configuration: islands are
/// containers, sources produce metrics, and each complication is an instance.
struct IslandSettingsView: View {
    @Bindable var runtime: IslandRuntime
    @State private var section: SettingsSection = .islands
    @State private var sourceID = ProviderBrand.claude.id
    @State private var presentsGallery = false
    @State private var catalogSourceID: String?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, IslandChrome.pageInset)
                .padding(.top, 8)

            Group {
                switch section {
                case .islands:
                    IslandWorkspaceEditor(
                        runtime: runtime,
                        presentsGallery: $presentsGallery,
                        catalogSourceID: $catalogSourceID
                    ) { id in
                        sourceID = id
                        section = .sources
                    }
                case .sources:
                    SourceSettingsPane(
                        runtime: runtime,
                        selectedSourceID: $sourceID,
                        browseComplications: {
                            catalogSourceID = sourceID
                            presentsGallery = true
                            runtime.workspaceStore.selectedComplicationID = nil
                            section = .islands
                        }
                    )
                case .general:
                    GeneralSettingsPane(runtime: runtime)
                case .about:
                    AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(IslandPalette.popover)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1120, minHeight: 680)
    }

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                let selected = item == section
                Button {
                    if item == .islands {
                        runtime.workspaceStore.selectedComplicationID = nil
                    }
                    if item == .sources, section == .islands,
                       let complication = runtime.workspaceStore.selectedComplication {
                        sourceID = complication.sourceID
                    }
                    section = item
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        }
                        .foregroundStyle(selected ? Color.white : IslandChrome.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        Rectangle()
                            .fill(selected ? Color.white : Color.clear)
                            .frame(height: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .keyboardShortcut(item.shortcut, modifiers: .command)
                .help("\(item.title) Settings (⌘\(item.shortcutLabel))")
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(IslandChrome.hairline).frame(height: 1)
        }
    }
}
