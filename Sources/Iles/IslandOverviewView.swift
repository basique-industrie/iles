import Domain
import IslandGeometry
import SwiftUI

/// Daily overview; editing stays in the island workspace.
struct IslandOverviewView: View {
    @Bindable var runtime: IslandRuntime
    let editIsland: (UUID) -> Void
    let showSources: () -> Void

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "Your islands", subtitle: "Check your data, then choose an island to edit.") {
                QuietButton(title: "Add island", symbol: "plus", prominence: .primary) {
                    runtime.workspaceStore.addIsland()
                    if let id = runtime.workspaceStore.selectedIslandID { editIsland(id) }
                }
            }

            if runtime.workspaceStore.islands.isEmpty {
                ContentUnavailableView("Create your first island", systemImage: "capsule.portrait",
                                       description: Text("Add an island, then choose the usage and system widgets you want on your desktop."))
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVGrid(columns: runtime.workspaceStore.islands.count == 1 ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(runtime.workspaceStore.islands) { island in
                        islandCard(island)
                    }
                }
            }

            IslandCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 18))
                        .foregroundStyle(IslandChrome.secondaryText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources").font(.system(size: 14, weight: .semibold))
                        Text("Manage the data and accounts behind your widgets.")
                            .font(.system(size: 12)).foregroundStyle(IslandChrome.secondaryText)
                    }
                    Spacer()
                    QuietButton(title: "Manage sources", symbol: "arrow.right", action: showSources)
                }
            }
        }
    }

    private func islandCard(_ island: IslandConfiguration) -> some View {
        IslandCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: island.isVisible ? "capsule.portrait.fill" : "eye.slash")
                        .font(.system(size: 18)).foregroundStyle(IslandChrome.text)
                        .frame(width: 36, height: 36)
                        .background(IslandChrome.sidebar, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(island.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(island.isVisible ? "\(island.placement.edge == .leading ? "Left" : "Right") screen edge · \(runtime.visibleComplications(on: island).count) visible" : "Hidden from desktop")
                            .font(.system(size: 12)).foregroundStyle(IslandChrome.secondaryText)
                    }
                    Spacer(minLength: 8)
                    QuietButton(title: "Edit", symbol: "slider.horizontal.3") { editIsland(island.id) }
                        .accessibilityLabel("Edit \(island.name)")
                }
                .padding(16)
                SettingsHairline()
                if island.complications.isEmpty {
                    Text("No widgets yet. Open the editor to add one.")
                        .font(.system(size: 13)).foregroundStyle(IslandChrome.secondaryText)
                        .padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 12)], spacing: 0) {
                        ForEach(island.complications) { item in
                            overviewRow(item)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func overviewRow(_ item: ComplicationConfiguration) -> some View {
        let descriptor = runtime.descriptor(sourceID: item.sourceID)
        let name = HarnaisGlance.metricSummary(sourceID: item.sourceID, metricIDs: item.metricIDs, descriptor: descriptor)
        let hidden = !item.isVisible || runtime.isHiddenBySource(item)
        let quality = runtime.quality(for: item)
        return HStack(spacing: 10) {
            SourceMark(sourceID: item.sourceID, descriptor: descriptor, metricIDs: item.metricIDs, size: 17, tint: .labelColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? (descriptor?.name ?? item.sourceID) : name)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                if hidden || quality != .live {
                    Text(hidden ? "Hidden" : (quality == .stale ? "Out of date" : (quality == .unavailable || quality == .failed ? "No current data" : "Saved data")))
                        .font(.system(size: 11)).foregroundStyle(IslandChrome.secondaryText)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(runtime.values(for: item).map(\.displayText).joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(hidden ? IslandChrome.secondaryText : IslandChrome.text)
                if descriptor?.kind == .usage, item.metricIDs.count == 1,
                   case .gauge = runtime.values(for: item).first {
                    Text(item.valueMode(at: 0) == .remaining ? "left" : "used")
                        .font(.system(size: 11)).foregroundStyle(IslandChrome.secondaryText)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 42)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
