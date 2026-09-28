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
    var title: String { rawValue.capitalized }

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
    @State private var sourceID = ProviderBrand.claude.id
    @State private var presentsGallery = false
    @State private var catalogSourceID: String?

    var body: some View {
        HStack(spacing: 0) {
            navigation
                .frame(width: 210)
                .background(IslandChrome.sidebar)
            Rectangle().fill(IslandChrome.hairline).frame(width: 1)

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
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
        .frame(minWidth: 1120, minHeight: 680)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "capsule.portrait.fill")
                    .font(.system(size: 18, weight: .medium))
                Text("Iles").font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(IslandChrome.text)
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 18)

            ForEach([SettingsSection.overview, .islands, .sources]) { item in
                navigationButton(item)
            }

            if section == .islands {
                SettingsHairline().padding(.vertical, 12)
                HStack {
                    Text("MY ISLANDS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(IslandChrome.secondaryText)
                    Spacer()
                    QuietIconButton(symbol: "plus", accessibilityName: "Add island", helpText: "Add an island") {
                        runtime.workspaceStore.addIsland()
                    }
                }
                .padding(.horizontal, 10)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(runtime.workspaceStore.islands) { island in
                            Button {
                                runtime.workspaceStore.selectIsland(island.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: island.isVisible ? "capsule.portrait" : "eye.slash")
                                        .frame(width: 18)
                                    Text(island.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(runtime.visibleComplications(on: island).count)")
                                        .foregroundStyle(IslandChrome.secondaryText)
                                        .monospacedDigit()
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(IslandChrome.text)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(runtime.workspaceStore.selectedIslandID == island.id ? IslandChrome.selectedFill : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(runtime.workspaceStore.selectedIslandID == island.id ? .isSelected : [])
                            .contextMenu {
                                Button("Duplicate") { runtime.workspaceStore.duplicateIsland(island.id) }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            SettingsHairline().padding(.vertical, 8)
            navigationButton(.general)
            navigationButton(.about)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func navigationButton(_ item: SettingsSection) -> some View {
        let selected = item == section
        return Button {
            if item == .islands { runtime.workspaceStore.selectedComplicationID = nil }
            if item == .sources, section == .islands,
               let complication = runtime.workspaceStore.selectedComplication {
                sourceID = complication.sourceID
            }
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).frame(width: 18)
                Text(item.title)
                Spacer()
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? IslandChrome.text : IslandChrome.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? IslandChrome.track : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .keyboardShortcut(item.shortcut, modifiers: .command)
        .help("\(item.title) (⌘\(item.shortcutLabel))")
    }
}
