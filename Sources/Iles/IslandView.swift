import AppKit
import Domain
import IslandGeometry
import SwiftUI

/// One configured island. The same renderer is used by the floating panel and
/// the live Settings preview so the editor cannot drift from the real result.
struct IslandView: View {
    @Bindable var runtime: IslandRuntime
    let islandID: UUID
    var maxHeight: CGFloat
    var interactive = true
    var selectedComplicationID: UUID? = nil

    var body: some View {
        if let island = runtime.workspaceStore.island(id: islandID) {
            content(island)
        }
    }

    private func content(_ island: IslandConfiguration) -> some View {
        let capacity = IslandMetrics.maxProviderCount(forHeight: maxHeight)
        let complications = Array(runtime.visibleComplications(on: island).prefix(capacity))
        let height = min(
            IslandMetrics.height(forProviderCount: complications.count),
            maxHeight
        )
        let mirrored = island.placement.edge == .leading

        return Group {
            if complications.isEmpty {
                emptyState
            } else {
                VStack(spacing: IslandMetrics.itemSpacing) {
                    ForEach(complications) { complication in
                        if interactive {
                            Button { runtime.handleTap(islandID: islandID, complication: complication) } label: {
                                slot(complication)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { runtime.hoverSelect(islandID: islandID, complicationID: complication.id) }
                            }
                        } else {
                            slot(complication)
                        }
                    }
                }
                .padding(.vertical, IslandMetrics.topPadding)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: IslandMetrics.width, height: height)
        .background {
            IslandShape(mirrored: mirrored)
                .fill(IslandPalette.surface)
        }
        .clipShape(IslandShape(mirrored: mirrored))
        .contentShape(IslandShape(mirrored: mirrored))
        .accessibilityElement(children: interactive ? .contain : .ignore)
        .accessibilityLabel(island.name)
        .onHover { hovering in
            guard interactive else { return }
            runtime.setPointerOverIsland(islandID, hovering)
        }
        .contextMenu {
            if interactive {
                Button("Refresh All Sources") { runtime.refreshNow() }
                Button("Edit \(island.name)…") {
                    runtime.workspaceStore.selectIsland(islandID)
                    runtime.settingsSection = .islands
                    NotificationCenter.default.post(name: .showIslandSettings, object: nil)
                }
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private func slot(_ complication: ComplicationConfiguration) -> some View {
        ComplicationSlotView(
            complication: complication,
            descriptor: runtime.descriptor(sourceID: complication.sourceID),
            values: runtime.values(for: complication),
            sourceError: runtime.snapshot(sourceID: complication.sourceID)?.errorDescription,
            quality: runtime.quality(for: complication),
            trendDirection: runtime.trendDirection(for: complication),
            isSyncing: runtime.provider(id: complication.sourceID)?.isSyncing == true,
            isSelected: selectedComplicationID == complication.id
                || runtime.selection == ComplicationSelection(islandID: islandID, complicationID: complication.id)
        )
    }

    private var emptyState: some View {
        IslandPlusAffordance {
            runtime.workspaceStore.selectIsland(islandID)
            runtime.settingsSection = .islands
            NotificationCenter.default.post(name: .showIslandSettings, object: nil)
        }
    }
}

/// Edge pill shown when the workspace has no islands.
struct EmptyWorkspaceIslandView: View {
    var edge: IslandEdge = .trailing

    var body: some View {
        let mirrored = edge == .leading
        IslandPlusAffordance {
            EmptyWorkspaceHint.dismiss()
            NotificationCenter.default.post(name: .showIslandSettings, object: nil)
        }
        .padding(.horizontal, IslandMetrics.leadingInset)
        .frame(width: IslandMetrics.width, height: IslandMetrics.height(forProviderCount: 0))
        .background {
            IslandShape(mirrored: mirrored)
                .fill(IslandPalette.surface)
        }
        .contentShape(IslandShape(mirrored: mirrored))
        .accessibilityLabel("Add an island")
        .accessibilityHint("Opens Settings to add an island")
        .accessibilityAddTraits(.isButton)
    }
}

private struct IslandPlusAffordance: View {
    let action: () -> Void

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(IslandPalette.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture {
                guard !NSEvent.modifierFlags.contains(.command) else { return }
                action()
            }
    }
}


struct SourceMark: View {
    let sourceID: String
    let descriptor: ComplicationSourceDescriptor?
    var metricID: String? = nil
    var metricIDs: [String] = []
    var size: CGFloat
    var zoomsOnHover = false
    var tint: NSColor = .white

    var body: some View {
        Group {
            if let metricSymbol {
                Image(systemName: metricSymbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.82, weight: .semibold))
                    .foregroundStyle(Color(nsColor: tint))
            } else if let brand = presentationBrand {
                ProviderMark(brand: brand, size: size, zoomsOnHover: zoomsOnHover, tint: tint)
            } else if descriptor?.sourceKindID == ConfigurableSourceKind.githubRepository.sourceKindID {
                VectorTemplateMark(resource: ("GitHubIcon", "svg"), tint: tint)
                    .frame(width: size * 0.82, height: size * 0.82)
            } else {
                Image(systemName: descriptor?.symbol ?? "questionmark")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(Color(nsColor: tint))
            }
        }
        .frame(width: size, height: size)
    }

    private var resolvedMetricIDs: [String] {
        if !metricIDs.isEmpty { return metricIDs }
        return metricID.map { [$0] } ?? []
    }

    private var presentationBrand: ProviderBrand? {
        HarnaisGlance.resolvedBrand(
            sourceID: sourceID,
            metricIDs: resolvedMetricIDs,
            descriptor: descriptor
        )
    }

    private var metricSymbol: String? {
        guard descriptor?.kind != .usage, let metricID else { return nil }
        return descriptor?.metrics.first { $0.id == metricID }?.symbol
    }
}

extension Color {
    init?(hex: String?) {
        guard var hex else { return nil }
        hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
