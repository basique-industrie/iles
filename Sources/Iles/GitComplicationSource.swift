import Domain
import Foundation
import Infrastructure

@MainActor
final class GitComplicationSource: ComplicationSource {
    private let store: JSONSettingsStore
    private let sourceID: String
    private let placeholderName: String
    private let repositoryKey: String
    private(set) var repositoryPath: String?
    private var cachedSnapshot: SourceSnapshot

    var descriptor: ComplicationSourceDescriptor {
        ComplicationSourceDescriptor(
            id: sourceID,
            sourceKindID: ConfigurableSourceKind.gitRepository.sourceKindID,
            allowsMultipleInstances: true,
            name: repositoryName,
            kind: .system,
            symbol: "arrow.triangle.branch",
            metrics: Self.metrics,
            supportedFamilies: [.value, .status, .activity, .trend, .summary],
            complications: FirstPartyComplicationCatalog.gitRecipes.map { $0.bound(to: sourceID) },
            capabilities: [.repositoryRead],
            actionURL: repositoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }

    init(
        sourceID: String = ConfigurableSourceKind.gitRepository.sourceKindID,
        placeholderName: String = ConfigurableSourceKind.gitRepository.title,
        store: JSONSettingsStore = .shared
    ) {
        self.store = store
        self.sourceID = sourceID
        self.placeholderName = placeholderName
        repositoryKey = Self.configurationKey(sourceID: sourceID, field: "repository")
        repositoryPath = store.read(key: repositoryKey)
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    var currentSnapshot: SourceSnapshot { cachedSnapshot }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        guard let repositoryPath else {
            cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
            return cachedSnapshot
        }
        let snapshot = await Self.probe(path: repositoryPath, sourceID: sourceID)
        cachedSnapshot = snapshot
        return snapshot
    }

    func setRepository(_ url: URL) {
        let path = url.standardizedFileURL.path
        repositoryPath = path
        store.write(value: path, key: repositoryKey)
        cachedSnapshot = SourceSnapshot(
            sourceID: sourceID,
            values: [:],
            quality: .cached,
            availability: .available
        )
    }

    func clearRepository() {
        repositoryPath = nil
        store.write(value: nil, key: repositoryKey)
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    private var repositoryName: String {
        guard let repositoryPath else { return placeholderName }
        return URL(fileURLWithPath: repositoryPath).lastPathComponent
    }

    private static let metrics: [ComplicationMetricDescriptor] = [
        ComplicationMetricDescriptor(id: "status", name: "Repository status", kind: .status, symbol: "arrow.triangle.branch", policy: ComplicationMetricPolicy(format: .status, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "branch", name: "Current branch", kind: .value, symbol: "arrow.triangle.branch", policy: ComplicationMetricPolicy(format: .text, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "changes", name: "Changed files", kind: .value, symbol: "doc.badge.ellipsis", policy: ComplicationMetricPolicy(format: .count, direction: .lowerIsBetter, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60, keepsHistory: true)),
        ComplicationMetricDescriptor(id: "staged", name: "Staged files", kind: .value, symbol: "checkmark.rectangle.stack", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "unstaged", name: "Unstaged files", kind: .value, symbol: "pencil.and.scribble", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "untracked", name: "Untracked files", kind: .value, symbol: "doc.badge.plus", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "sync", name: "Upstream sync", kind: .status, symbol: "arrow.triangle.2.circlepath", policy: ComplicationMetricPolicy(format: .status, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "ahead", name: "Commits ahead", kind: .value, symbol: "arrow.up", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "behind", name: "Commits behind", kind: .value, symbol: "arrow.down", policy: ComplicationMetricPolicy(format: .count, direction: .lowerIsBetter, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ComplicationMetricDescriptor(id: "lastCommit", name: "Last commit age", kind: .duration, symbol: "clock.arrow.circlepath", policy: ComplicationMetricPolicy(format: .duration, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
    ]

    private nonisolated static func probe(
        path: String,
        sourceID: String = ConfigurableSourceKind.gitRepository.sourceKindID,
        date: Date = Date()
    ) async -> SourceSnapshot {
        guard let root = await git(path: path, arguments: ["rev-parse", "--show-toplevel"]), !root.isEmpty else {
            return SourceSnapshot(
                sourceID: sourceID,
                capturedAt: date,
                values: [:],
                errorDescription: "The selected folder is not a readable Git repository.",
                quality: .failed,
                availability: ComplicationAvailability(
                    state: .failed,
                    message: "Choose another repository.",
                    recoveryAction: .configure
                )
            )
        }

        let porcelain = await git(path: root, arguments: ["status", "--porcelain=v1", "--branch"]) ?? ""
        let lines = porcelain.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let branchLine = lines.first(where: { $0.hasPrefix("## ") }) ?? "## HEAD"
        let fileLines = lines.filter { !$0.hasPrefix("## ") }
        let branch = branchName(from: branchLine)
        let conflicts = fileLines.filter { line in
            let code = String(line.prefix(2))
            return code.contains("U") || ["AA", "DD"].contains(code)
        }.count
        let untracked = fileLines.filter { $0.hasPrefix("??") }.count
        let staged = fileLines.filter { line in
            guard let first = line.first else { return false }
            return first != " " && first != "?"
        }.count
        let unstaged = fileLines.filter { line in
            guard line.count >= 2 else { return false }
            let index = line.index(after: line.startIndex)
            return line[index] != " " && line[index] != "?"
        }.count

        let syncCounts = await git(path: root, arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"])?
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        let behind = syncCounts?.first ?? 0
        let ahead = syncCounts?.dropFirst().first ?? 0
        let hasUpstream = syncCounts?.count == 2

        let status: ComplicationValue
        if conflicts > 0 {
            status = .status(label: "Conflict", level: .critical)
        } else if fileLines.isEmpty {
            status = .status(label: "Clean", level: .healthy)
        } else {
            status = .status(label: "\(fileLines.count) changes", level: .warning)
        }

        let sync: ComplicationValue
        if !hasUpstream {
            sync = .status(label: "No upstream", level: .inactive)
        } else if ahead > 0 && behind > 0 {
            sync = .status(label: "Diverged", level: .critical)
        } else if behind > 0 {
            sync = .status(label: "Behind \(behind)", level: .warning)
        } else if ahead > 0 {
            sync = .status(label: "Ahead \(ahead)", level: .warning)
        } else {
            sync = .status(label: "Up to date", level: .healthy)
        }

        var values: [String: ComplicationValue] = [
            "status": status,
            "branch": .value(branch, unit: nil),
            "changes": .value("\(fileLines.count)", unit: nil),
            "staged": .value("\(staged)", unit: nil),
            "unstaged": .value("\(unstaged)", unit: nil),
            "untracked": .value("\(untracked)", unit: nil),
            "sync": sync,
            "ahead": .value("\(ahead)", unit: nil),
            "behind": .value("\(behind)", unit: nil),
        ]
        if let timestamp = await git(path: root, arguments: ["log", "-1", "--format=%ct"]).flatMap(TimeInterval.init) {
            let commitAge = max(date.timeIntervalSince1970 - timestamp, 0)
            values["lastCommit"] = .duration(
                commitAge,
                label: CompactDurationFormatter.largestUnit(commitAge)
            )
        }
        return SourceSnapshot(sourceID: sourceID, capturedAt: date, values: values)
    }

    nonisolated static func branchName(from porcelainHeader: String) -> String {
        let header = porcelainHeader.hasPrefix("## ")
            ? String(porcelainHeader.dropFirst(3))
            : porcelainHeader
        if header.hasPrefix("No commits yet on ") {
            return String(header.dropFirst("No commits yet on ".count))
        }
        let withoutTracking = header.components(separatedBy: "...").first ?? header
        return withoutTracking.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "HEAD"
    }

    private nonisolated static func git(path: String, arguments: [String]) async -> String? {
        guard let result = try? await SimpleCLIExecutor().execute(
            binary: "/usr/bin/git",
            args: ["-C", path] + arguments,
            input: nil,
            timeout: 8,
            workingDirectory: nil,
            autoResponses: [:]
        ), result.exitCode == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func setupSnapshot(sourceID: String) -> SourceSnapshot {
        SourceSnapshot(
            sourceID: sourceID,
            values: [:],
            errorDescription: "Choose a Git repository to enable repository complications.",
            quality: .unavailable,
            availability: ComplicationAvailability(
                state: .setupRequired,
                message: "Choose a local Git repository.",
                recoveryAction: .configure
            )
        )
    }

    private static func configurationKey(sourceID: String, field: String) -> String {
        if sourceID == ConfigurableSourceKind.gitRepository.sourceKindID {
            return "developer.git.\(field)"
        }
        return "sourceInstances.\(sourceID.replacingOccurrences(of: ".", with: "_")).\(field)"
    }

}
