import AppKit
import Domain
import Infrastructure
import IslandGeometry
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview
    case islands
    case sources
    case general
    case about

    var id: String { rawValue }
    var title: String { self == .general ? "Settings" : rawValue.capitalized }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .islands: "capsule.portrait"
        case .sources: "square.stack.3d.up"
        case .general: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "0"
        case .islands: "1"
        case .sources: "2"
        case .general: "3"
        case .about: "4"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .overview: "0"
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
    @AppStorage("settingsAppearance") private var appearance: SettingsAppearance = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var section: SettingsSection {
        get { runtime.settingsSection }
        nonmutating set { runtime.settingsSection = newValue }
    }
    @State private var titlebarLeading: CGFloat = 100
    @State private var titlebarHeight: CGFloat = 52
    @State private var sourceID = ProviderBrand.claude.id
    @State private var presentsGallery = false
    @State private var catalogSourceID: String?

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(runtime: runtime, section: section,
                            titlebarLeading: titlebarLeading, titlebarHeight: titlebarHeight,
                            selectSection: selectSection)
            Rectangle().fill(IslandChrome.border).frame(width: 1)

            Group {
                switch section {
                case .overview:
                    IslandOverviewView(runtime: runtime, editIsland: { id in
                        runtime.workspaceStore.selectIsland(id)
                        section = .islands
                    }, showSources: { section = .sources })
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
                            if runtime.workspaceStore.selectedIsland == nil {
                                runtime.workspaceStore.addIsland()
                            }
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
        .background(IslandChrome.background)
        .ignoresSafeArea(edges: .top)
        .background(SettingsWindowConfigurator(
            title: AppIdentity.current.displayName,
            titlebarLeading: $titlebarLeading,
            titlebarHeight: $titlebarHeight
        ))
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
        .frame(minWidth: 1120, minHeight: 680)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    private func selectSection(_ item: SettingsSection) {
        if item == .sources, section == .islands,
           let complication = runtime.workspaceStore.selectedComplication {
            sourceID = complication.sourceID
        }
        if item == .islands { runtime.workspaceStore.selectedComplicationID = nil }
        section = item
    }
}
