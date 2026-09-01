import Foundation
import Domain
import SwiftTerm

/// Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
/// Implements the UsageProbe protocol from the domain layer.
///
/// When using the default CLI executor, this probe strips `CLAUDE_CODE_OAUTH_TOKEN`
/// from the subprocess environment. This ensures `claude /usage` falls back to stored
/// credentials (from `claude login`) which have the full `user:profile` scope required
/// for quota data, rather than using the inference-only setup-token.
public final class ClaudeUsageProbe: UsageProbe, @unchecked Sendable {
    private let claudeBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor
    let terminalRenderer: TerminalRenderer

    /// Environment variables to strip from the CLI subprocess.
    /// `CLAUDE_CODE_OAUTH_TOKEN` is excluded because setup-tokens only have
    /// `user:inference` scope and cannot access quota data via `/usage`.
    static let envExclusions = ["CLAUDE_CODE_OAUTH_TOKEN"]

    /// Resolves account info from `~/.claude.json`
    let accountInfoResolver: any AccountInfoResolving

    public init(
        claudeBinary: String = "claude",
        timeout: TimeInterval = 20.0,
        cliExecutor: CLIExecutor? = nil,
        accountInfoResolver: any AccountInfoResolving = ClaudeAccountInfoResolver()
    ) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor(environmentExclusions: Self.envExclusions)
        self.terminalRenderer = TerminalRenderer(cols: 160, rows: 50)
        self.accountInfoResolver = accountInfoResolver
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(claudeBinary) != nil {
            return true
        }

        // Log diagnostic info when binary not found
        let env = ProcessInfo.processInfo.environment
        AppLog.probes.error("Claude binary '\(claudeBinary)' not found in PATH")
        AppLog.probes.debug("Current directory: \(FileManager.default.currentDirectoryPath)")
        AppLog.probes.debug("PATH: \(env["PATH"] ?? "<not set>")")
        if let configDir = env["CLAUDE_CONFIG_DIR"] {
            AppLog.probes.debug("CLAUDE_CONFIG_DIR: \(configDir)")
        }
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        let probeStart = CFAbsoluteTimeGetCurrent()
        let workingDir = probeWorkingDirectory()
        AppLog.probes.info("Starting Claude probe with /usage command...")

        let usageResult: CLIResult
        let cliStart = CFAbsoluteTimeGetCurrent()
        do {
            usageResult = try await cliExecutor.execute(
                binary: claudeBinary,
                args: ["/usage", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: workingDir,
                autoResponses: [
                    "Esc to cancel": "\r",  // Trust prompt - press Enter to confirm
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                    "ctrl+t to disable": "\r",  // Onboarding complete
                    "Yes, I trust this folder": "\r",  // New trust prompt format
                ]
            )
        } catch {
            AppLog.probes.error("Claude /usage probe failed: \(error.localizedDescription)")
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }
        let cliElapsed = CFAbsoluteTimeGetCurrent() - cliStart
        AppLog.probes.debug("Claude CLI execution took \(String(format: "%.3f", cliElapsed))s")

        AppLog.probes.debug("Claude /usage command returned \(usageResult.output.count) characters")

        let parseStart = CFAbsoluteTimeGetCurrent()
        let snapshot: UsageSnapshot
        do {
            snapshot = try parseClaudeOutput(usageResult.output)
        } catch ProbeError.folderTrustRequired {
            // Auto-response failed to dismiss trust prompt — write trust to ~/.claude.json and retry
            AppLog.probes.info("Writing trust for probe directory and retrying...")
            if writeClaudeTrust(for: workingDir) {
                return try await probe()
            }
            throw ProbeError.folderTrustRequired
        } catch ProbeError.subscriptionRequired {
            // API Usage Billing accounts don't support /usage, try /cost instead
            AppLog.probes.info("Account requires /cost command, falling back...")
            return try await probeCost(workingDir: workingDir)
        } catch {
            AppLog.probes.debug("Working directory: \(workingDir.path)")
            throw error
        }
        let parseElapsed = CFAbsoluteTimeGetCurrent() - parseStart
        AppLog.probes.debug("Claude parsing took \(String(format: "%.3f", parseElapsed))s")

        let totalElapsed = CFAbsoluteTimeGetCurrent() - probeStart
        AppLog.probes.info("Claude probe success: accountTier=\(snapshot.accountTier?.badgeText ?? "unknown"), quotas=\(snapshot.quotas.count) (total: \(String(format: "%.3f", totalElapsed))s)")

        return snapshot
    }

    /// Probes using /cost command for API Usage Billing accounts
    private func probeCost(workingDir: URL) async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Claude probe with /cost command...")

        let costResult: CLIResult
        do {
            costResult = try await cliExecutor.execute(
                binary: claudeBinary,
                args: ["/cost", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: workingDir,
                autoResponses: [
                    "Esc to cancel": "\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                    "ctrl+t to disable": "\r",
                    "Yes, I trust this folder": "\r",  // New trust prompt format
                ]
            )
        } catch {
            AppLog.probes.error("Claude /cost probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        AppLog.probes.debug("Claude /cost command returned \(costResult.output.count) characters")

        let snapshot = try parseCostOutput(costResult.output)

        AppLog.probes.info("Claude /cost probe success")

        return snapshot
    }

}
