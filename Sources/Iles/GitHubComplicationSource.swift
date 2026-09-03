import Domain
import Foundation
import Infrastructure

struct GitHubRepositoryChoice: Equatable, Sendable, Identifiable {
    var id: String { nameWithOwner }
    let nameWithOwner: String
    let isPrivate: Bool
}

enum GitHubRepositoryListResult: Equatable, Sendable {
    case repositories([GitHubRepositoryChoice])
    case unauthenticated
    case failed(String)
}

@MainActor
final class GitHubComplicationSource: ComplicationSource {
    private let store: JSONSettingsStore
    private let cliExecutor: any CLIExecutor
    private let sourceID: String
    private let placeholderName: String
    private let repositoryKey: String
    private(set) var repository: String?
    private var cachedSnapshot: SourceSnapshot

    var descriptor: ComplicationSourceDescriptor {
        ComplicationSourceDescriptor(
            id: sourceID,
            sourceKindID: ConfigurableSourceKind.githubRepository.sourceKindID,
            allowsMultipleInstances: true,
            name: repository.map { "GitHub · \($0)" } ?? placeholderName,
            kind: .system,
            symbol: "chevron.left.forwardslash.chevron.right",
            metrics: Self.metrics,
            supportedFamilies: [.value, .status, .activity, .summary],
            complications: FirstPartyComplicationCatalog.githubRecipes.map { $0.bound(to: sourceID) },
            capabilities: [.networkAccess, .repositoryRead, .status],
            actionURL: repository.flatMap { URL(string: "https://github.com/\($0)") }
        )
    }

    init(
        sourceID: String = ConfigurableSourceKind.githubRepository.sourceKindID,
        placeholderName: String = ConfigurableSourceKind.githubRepository.title,
        store: JSONSettingsStore = .shared,
        // Pipes, not a PTY: `gh` pages and wraps JSON when it thinks it has a terminal.
        cliExecutor: any CLIExecutor = SimpleCLIExecutor()
    ) {
        self.store = store
        self.cliExecutor = cliExecutor
        self.sourceID = sourceID
        self.placeholderName = placeholderName
        repositoryKey = Self.configurationKey(sourceID: sourceID, field: "repository")
        let saved: String? = store.read(key: repositoryKey)
        repository = saved.flatMap { Self.isValidRepository($0) ? $0 : nil }
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    var repositoryText: String { repository ?? "" }
    var currentSnapshot: SourceSnapshot { cachedSnapshot }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        guard let repository else {
            cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
            return cachedSnapshot
        }
        let snapshot = await Self.probe(
            repository: repository,
            sourceID: sourceID,
            cliExecutor: cliExecutor
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    @discardableResult
    func setRepository(_ raw: String) -> Bool {
        let normalized = Self.normalizedRepository(raw)
        guard Self.isValidRepository(normalized) else { return false }
        repository = normalized
        store.write(value: normalized, key: repositoryKey)
        cachedSnapshot = SourceSnapshot(sourceID: descriptor.id, values: [:], quality: .cached)
        return true
    }

    func clearRepository() {
        repository = nil
        store.write(value: nil, key: repositoryKey)
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    func listAccessibleRepositories() async -> GitHubRepositoryListResult {
        await Self.listAccessibleRepositories(cliExecutor: cliExecutor)
    }

    private static let metrics: [ComplicationMetricDescriptor] = [
        ComplicationMetricDescriptor(id: "ci", name: "Latest workflow", kind: .status, symbol: "checkmark.seal", policy: ComplicationMetricPolicy(format: .status, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "workflow", name: "Workflow name", kind: .value, symbol: "arrow.triangle.2.circlepath", policy: ComplicationMetricPolicy(format: .text, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "failingJobs", name: "Failing jobs", kind: .value, symbol: "xmark.octagon", policy: ComplicationMetricPolicy(format: .count, direction: .lowerIsBetter, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "lastRun", name: "Last workflow age", kind: .duration, symbol: "clock.arrow.circlepath", policy: ComplicationMetricPolicy(format: .duration, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "openPRs", name: "Open pull requests", kind: .value, symbol: "arrow.triangle.pull", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "reviews", name: "Reviews requested", kind: .value, symbol: "person.crop.circle.badge.checkmark", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "deployment", name: "Latest deployment", kind: .status, symbol: "shippingbox", policy: ComplicationMetricPolicy(format: .status, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "environment", name: "Deployment environment", kind: .value, symbol: "server.rack", policy: ComplicationMetricPolicy(format: .text, privacy: .personal, refreshClass: .periodicNetwork, staleAfter: 300)),
    ]

    private nonisolated static func probe(
        repository: String,
        sourceID: String = ConfigurableSourceKind.githubRepository.sourceKindID,
        cliExecutor: any CLIExecutor,
        date: Date = Date()
    ) async -> SourceSnapshot {
        guard let authentication = try? await cliExecutor.execute(
            binary: "gh",
            args: ["auth", "status", "--hostname", "github.com"],
            input: nil,
            timeout: 5,
            workingDirectory: nil,
            autoResponses: [:]
        ), authentication.exitCode == 0 else {
            return SourceSnapshot(
                sourceID: sourceID,
                capturedAt: date,
                values: [:],
                errorDescription: "GitHub CLI is missing or not authenticated. Install gh and run ‘gh auth login’.",
                quality: .unavailable,
                availability: ComplicationAvailability(
                    state: .setupRequired,
                    message: "Authenticate GitHub CLI.",
                    recoveryAction: .configure
                )
            )
        }

        async let runResponse = jsonObject(
            endpoint: "repos/\(repository)/actions/runs?per_page=1",
            cliExecutor: cliExecutor
        )
        async let pullsResponse = jsonObject(
            endpoint: "repos/\(repository)/pulls?state=open&per_page=100",
            cliExecutor: cliExecutor
        )
        async let userResponse = jsonObject(endpoint: "user", cliExecutor: cliExecutor)
        async let deploymentsResponse = jsonObject(
            endpoint: "repos/\(repository)/deployments?per_page=1",
            cliExecutor: cliExecutor
        )

        let runObject = await runResponse as? [String: Any]
        let runs = runObject?["workflow_runs"] as? [[String: Any]]
        let run = runs?.first
        let pulls = await pullsResponse as? [[String: Any]]
        let login = (await userResponse as? [String: Any])?["login"] as? String
        let runID = run?["id"] as? NSNumber
        let jobs: [[String: Any]]?
        if let runID,
           let object = await jsonObject(
               endpoint: "repos/\(repository)/actions/runs/\(runID.int64Value)/jobs?per_page=100",
               cliExecutor: cliExecutor
           ) as? [String: Any] {
            jobs = object["jobs"] as? [[String: Any]] ?? []
        } else {
            jobs = run == nil ? [] : nil
        }

        let deployments = await deploymentsResponse as? [[String: Any]]
        let deployment = deployments?.first
        let deploymentID = deployment?["id"] as? NSNumber
        let deploymentStatus: [String: Any]?
        if let deploymentID {
            deploymentStatus = (await jsonObject(
                endpoint: "repos/\(repository)/deployments/\(deploymentID.int64Value)/statuses?per_page=1",
                cliExecutor: cliExecutor
            ) as? [[String: Any]])?.first
        } else {
            deploymentStatus = nil
        }

        var values: [String: ComplicationValue] = [:]
        if runs != nil {
            values["ci"] = run.map {
                statusValue(
                    status: ($0["status"] as? String) ?? "unknown",
                    conclusion: $0["conclusion"] as? String
                )
            } ?? .status(label: "No Runs", level: .inactive)
            values["workflow"] = .value((run?["name"] as? String) ?? "No workflow", unit: nil)
        }
        if let jobs {
            let failingJobs = jobs.filter {
                let conclusion = $0["conclusion"] as? String
                return conclusion == "failure" || conclusion == "timed_out" || conclusion == "cancelled"
            }.count
            values["failingJobs"] = .value("\(failingJobs)", unit: nil)
        }
        if let pulls {
            values["openPRs"] = .value("\(pulls.count)", unit: nil)
            if let login {
                let reviews = pulls.filter { pull in
                    let requested = pull["requested_reviewers"] as? [[String: Any]] ?? []
                    return requested.contains { ($0["login"] as? String) == login }
                }.count
                values["reviews"] = .value("\(reviews)", unit: nil)
            }
        }
        if deployments != nil {
            if deployment == nil {
                values["deployment"] = .status(label: "No Deploy", level: .inactive)
                values["environment"] = .value("No deployment", unit: nil)
            } else {
                if let deploymentStatus {
                    values["deployment"] = deploymentValue(deploymentStatus["state"] as? String)
                }
                values["environment"] = .value(
                    (deploymentStatus?["environment"] as? String)
                        ?? (deployment?["environment"] as? String)
                        ?? "Unknown",
                    unit: nil
                )
            }
        }
        if let updated = (run?["updated_at"] as? String).flatMap(isoDate) {
            let age = max(date.timeIntervalSince(updated), 0)
            values["lastRun"] = .duration(age, label: CompactDurationFormatter.largestUnit(age))
        }
        guard !values.isEmpty else {
            return SourceSnapshot(
                sourceID: sourceID,
                capturedAt: date,
                values: [:],
                errorDescription: "GitHub did not return repository data. Check access to \(repository) and try again.",
                quality: .failed,
                availability: ComplicationAvailability(
                    state: .temporarilyUnavailable,
                    message: "GitHub API requests failed.",
                    recoveryAction: .retry
                )
            )
        }
        return SourceSnapshot(sourceID: sourceID, capturedAt: date, values: values)
    }

    private nonisolated static func statusValue(status: String, conclusion: String?) -> ComplicationValue {
        if status != "completed" {
            return .status(label: status.capitalized, level: .warning)
        }
        switch conclusion {
        case "success": return .status(label: "Passing", level: .healthy)
        case "failure", "timed_out": return .status(label: "Failing", level: .critical)
        case "cancelled": return .status(label: "Cancelled", level: .warning)
        case "skipped", "neutral": return .status(label: "Neutral", level: .inactive)
        default: return .status(label: "Unknown", level: .inactive)
        }
    }

    private nonisolated static func deploymentValue(_ state: String?) -> ComplicationValue {
        switch state {
        case "success": .status(label: "Deployed", level: .healthy)
        case "failure", "error": .status(label: "Failed", level: .critical)
        case "pending", "queued", "in_progress": .status(label: "Deploying", level: .warning)
        case "inactive": .status(label: "Inactive", level: .inactive)
        default: .status(label: "No Deploy", level: .inactive)
        }
    }

    nonisolated static func listAccessibleRepositories(
        cliExecutor: any CLIExecutor
    ) async -> GitHubRepositoryListResult {
        guard let authentication = try? await cliExecutor.execute(
            binary: "gh",
            args: ["auth", "status", "--hostname", "github.com"],
            input: nil,
            timeout: 5,
            workingDirectory: nil,
            autoResponses: [:]
        ), authentication.exitCode == 0 else {
            return .unauthenticated
        }

        let api = await repositoriesFromUserAPI(cliExecutor: cliExecutor)
        if let repositories = api.repositories, !repositories.isEmpty {
            return .repositories(repositories)
        }
        let fallback = await repositoriesFromRepoList(cliExecutor: cliExecutor)
        if let repositories = fallback.repositories {
            return .repositories(repositories)
        }
        return .failed(
            userFacingListFailure(apiError: api.failure, fallbackError: fallback.failure)
        )
    }

    private nonisolated static func repositoriesFromUserAPI(
        cliExecutor: any CLIExecutor
    ) async -> (repositories: [GitHubRepositoryChoice]?, failure: String?) {
        let result = await runGitHubCLI(
            cliExecutor: cliExecutor,
            args: [
                "api",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2026-03-10",
                "user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member",
                "--jq", "[.[] | {full_name, private}]",
            ],
            timeout: 20
        )
        guard let payload = result.object as? [[String: Any]] else {
            return (nil, result.failure)
        }
        return (decodeRepositoryChoices(payload, nameKey: "full_name", privateKey: "private"), nil)
    }

    private nonisolated static func repositoriesFromRepoList(
        cliExecutor: any CLIExecutor
    ) async -> (repositories: [GitHubRepositoryChoice]?, failure: String?) {
        let result = await runGitHubCLI(
            cliExecutor: cliExecutor,
            args: ["repo", "list", "--limit", "100", "--json", "nameWithOwner,isPrivate"],
            timeout: 20
        )
        guard let payload = result.object as? [[String: Any]] else {
            return (nil, result.failure)
        }
        return (decodeRepositoryChoices(payload, nameKey: "nameWithOwner", privateKey: "isPrivate"), nil)
    }

    private nonisolated static func decodeRepositoryChoices(
        _ payload: [[String: Any]],
        nameKey: String,
        privateKey: String
    ) -> [GitHubRepositoryChoice] {
        var seen = Set<String>()
        var choices: [GitHubRepositoryChoice] = []
        for item in payload {
            guard let name = item[nameKey] as? String, isValidRepository(name), seen.insert(name).inserted else {
                continue
            }
            choices.append(
                GitHubRepositoryChoice(
                    nameWithOwner: name,
                    isPrivate: item[privateKey] as? Bool ?? false
                )
            )
        }
        return choices
    }

    private nonisolated static func jsonObject(
        endpoint: String,
        cliExecutor: any CLIExecutor
    ) async -> Any? {
        await runGitHubCLI(
            cliExecutor: cliExecutor,
            args: [
                "api",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2026-03-10",
                endpoint,
            ],
            timeout: 10
        ).object
    }

    private nonisolated static func runGitHubCLI(
        cliExecutor: any CLIExecutor,
        args: [String],
        timeout: TimeInterval
    ) async -> (object: Any?, failure: String?) {
        do {
            let result = try await cliExecutor.execute(
                binary: "gh",
                args: args,
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
            if result.exitCode != 0 {
                return (nil, userFacingCLIError(result.output) ?? "GitHub CLI exited with status \(result.exitCode).")
            }
            guard let object = firstJSONObject(in: result.output) else {
                return (nil, "GitHub CLI returned a response that Iles could not read.")
            }
            return (object, nil)
        } catch {
            return (nil, userFacingCLIError(error.localizedDescription) ?? "GitHub CLI could not be run.")
        }
    }

    /// `gh` sometimes prefixes JSON with an update notice on stderr, which
    /// `SimpleCLIExecutor` concatenates onto stdout. Pull the first JSON value.
    nonisolated static func firstJSONObject(in raw: String) -> Any? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(where: { $0 == "[" || $0 == "{" }) else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var end: String.Index?
        scan: for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escape {
                    escape = false
                    continue
                }
                if character == "\\" {
                    escape = true
                    continue
                }
                if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "[", "{":
                depth += 1
            case "]", "}":
                depth -= 1
                if depth == 0 {
                    end = index
                    break scan
                }
            default:
                break
            }
        }
        guard let end else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))
    }

    private nonisolated static func userFacingListFailure(apiError: String?, fallbackError: String?) -> String {
        let detail = [apiError, fallbackError]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        if let detail {
            return detail
        }
        return "GitHub CLI did not return a repository list."
    }

    private nonisolated static func userFacingCLIError(_ raw: String) -> String? {
        let line = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard var line, !line.isEmpty else { return nil }
        line = line.replacingOccurrences(
            of: #"\b(?:gho|ghu|ghs|github_pat)_[A-Za-z0-9_]+"#,
            with: "<redacted>",
            options: .regularExpression
        )
        if line.count > 160 {
            return String(line.prefix(157)) + "…"
        }
        return line
    }

    nonisolated static func selectableRepository(from raw: String) -> String? {
        let normalized = normalizedRepository(raw)
        return isValidRepository(normalized) ? normalized : nil
    }

    private nonisolated static func normalizedRepository(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:"] {
            if value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private nonisolated static func isValidRepository(_ repository: String) -> Bool {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty
                && part.count <= 100
                && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private nonisolated static func isoDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private nonisolated static func setupSnapshot(sourceID: String) -> SourceSnapshot {
        SourceSnapshot(
            sourceID: sourceID,
            values: [:],
            errorDescription: "Choose a GitHub repository. Iles uses your existing authenticated GitHub CLI session and does not store a token.",
            quality: .unavailable,
            availability: ComplicationAvailability(
                state: .setupRequired,
                message: "Choose a GitHub repository.",
                recoveryAction: .configure
            )
        )
    }

    private static func configurationKey(sourceID: String, field: String) -> String {
        if sourceID == ConfigurableSourceKind.githubRepository.sourceKindID {
            return "developer.github.\(field)"
        }
        return "sourceInstances.\(sourceID.replacingOccurrences(of: ".", with: "_")).\(field)"
    }
}
