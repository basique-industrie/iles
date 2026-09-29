import AppKit
import Domain
import SwiftUI

/// Matches Harnais's sidebar geometry, hierarchy and interaction states.
struct SettingsSidebar: View {
    @Bindable var runtime: IslandRuntime
    let section: SettingsSection
    let titlebarLeading: CGFloat
    let titlebarHeight: CGFloat
    let selectSection: (SettingsSection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "capsule.portrait.fill")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 24, height: 24)
                Text("Iles")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(IslandChrome.text)
            .allowsHitTesting(false)
            .padding(.leading, titlebarLeading)
            .frame(height: titlebarHeight)

            VStack(spacing: 1) {
                ForEach([SettingsSection.overview, .islands, .sources]) { item in
                    navigationRow(item)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 2) {
                separator.padding(.bottom, 10)
                Text("My islands")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandChrome.secondaryText)
                    .padding(.horizontal, 8)
                    .accessibilityAddTraits(.isHeader)
                SettingsSidebarRow(title: "Add island", symbol: "plus", muted: true) {
                    runtime.workspaceStore.addIsland()
                    selectSection(.islands)
                }
            }
            .padding(.horizontal, 6)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(runtime.workspaceStore.islands) { island in
                        SettingsSidebarRow(
                            title: island.name,
                            symbol: island.isVisible ? "capsule.portrait" : "eye.slash",
                            selected: section == .islands && runtime.workspaceStore.selectedIslandID == island.id,
                            detail: "\(runtime.visibleComplications(on: island).count)"
                        ) {
                            runtime.workspaceStore.selectIsland(island.id)
                            selectSection(.islands)
                        }
                        .help("Open \(island.name)")
                        .contextMenu {
                            Button("Duplicate") { runtime.workspaceStore.duplicateIsland(island.id) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 1) {
                separator
                navigationRow(.general)
                navigationRow(.about)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .frame(width: IslandChrome.sidebarWidth)
        .background(IslandChrome.sidebar)
    }

    private var separator: some View {
        Rectangle().fill(IslandChrome.border).frame(height: 1)
    }

    private func navigationRow(_ item: SettingsSection) -> some View {
        SettingsSidebarRow(
            title: item.title,
            symbol: item.symbol,
            resource: item == .overview ? "LucideLayoutDashboard" : (item == .general ? "LucideSettings" : nil),
            selected: section == item
        ) {
            selectSection(item)
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
        .help("\(item.title) (⌘\(item.shortcutLabel))")
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let symbol: String
    var resource: String? = nil
    var selected = false
    var muted = false
    var detail: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let resource {
                        VectorTemplateMark(resource: (resource, "svg"), tint: selected || isHovering ? .labelColor : .secondaryLabelColor)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(selected || isHovering ? IslandChrome.text : IslandChrome.secondaryText)
                    }
                }
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(muted && !isHovering ? IslandChrome.secondaryText : IslandChrome.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(IslandChrome.secondaryText)
                        .accessibilityLabel("\(detail) visible widgets")
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(selected ? IslandChrome.rowSelected : (isHovering ? IslandChrome.rowHover : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
