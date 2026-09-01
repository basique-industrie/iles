import Foundation
@testable import Infrastructure

extension IlesSelfTests {
  @MainActor
  static func runSecurityHardeningTests(_ test: TestHarness) async {
    supportLogPrivacy(test)
    settingsRecovery(test)
    authenticatedHookParsing(test)
    hiddenFilesAffectExtensionFingerprint(test)
    credentialFileCoordination(test)
    antigravityCredentialParsing(test)
    await boundedConcurrentSubprocessOutput(test)
    await subprocessTimeout(test)
  }

  @MainActor
  private static func supportLogPrivacy(_ test: TestHarness) {
    let directory = securityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let logURL = directory.appendingPathComponent("Iles.log")
    let exportURL = directory.appendingPathComponent("support.log")
    let logger = FileLogger(fileURL: logURL, maxFileSize: 32_000)

    logger.log(
      .error,
      category: "test",
      message: "account=user@example.com access_token=secret-value\nraw provider response"
    )
    do {
      try logger.exportCurrentLog(to: exportURL)
      let exported = try String(contentsOf: exportURL, encoding: .utf8)
      test.expect(!exported.contains("user@example.com"), "support logs redact email addresses")
      test.expect(!exported.contains("secret-value"), "support logs redact access tokens")
      test.expect(!exported.contains("raw provider response"), "support logs omit multiline bodies")
      test.expect(
        exported.contains("multiline details omitted"), "support logs explain omitted details")
      test.expectEqual(
        filePermissions(exportURL), 0o600, "exported support logs use owner-only permissions")
    } catch {
      test.expect(false, "support log export succeeds: \(error)")
    }
  }

  @MainActor
  private static func settingsRecovery(_ test: TestHarness) {
    let directory = securityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let settingsURL = directory.appendingPathComponent("settings.json")
    do {
      let store = JSONSettingsStore(fileURL: settingsURL)
      try store.writeThrowing(value: "first", key: "sample.value")
      try store.writeThrowing(value: "second", key: "sample.value")
      try Data("not-json".utf8).write(to: settingsURL, options: .atomic)

      let recoveredStore = JSONSettingsStore(fileURL: settingsURL)
      let recovered: String? = recoveredStore.read(key: "sample.value")
      test.expectEqual(recovered, "first", "invalid settings recover from the previous backup")
      test.expect(
        recoveredStore.lastErrorDescription != nil,
        "settings recovery preserves an actionable error")
      test.expectEqual(
        filePermissions(settingsURL), 0o600, "recovered settings use owner-only permissions")
      let recoveryFiles = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
      test.expect(
        recoveryFiles.contains { $0.lastPathComponent.contains("corrupt-") },
        "settings recovery quarantines the corrupt file"
      )
    } catch {
      test.expect(false, "settings backup recovery succeeds: \(error)")
    }
  }

  @MainActor
  private static func authenticatedHookParsing(_ test: TestHarness) {
    let token = "test-token"
    let body = Data(#"{"session_id":"session","hook_event_name":"Stop","cwd":"/tmp"}"#.utf8)
    let valid = hookRequest(body: body, token: token, path: "/hook")

    test.expectEqual(
      HookHTTPRequestParser.parse(valid, authenticationToken: token, isComplete: true),
      .accepted(body),
      "authenticated hook requests are accepted"
    )
    test.expectEqual(
      HookHTTPRequestParser.parse(valid, authenticationToken: "wrong", isComplete: true),
      .rejected(401),
      "hook requests reject the wrong token"
    )
    test.expectEqual(
      HookHTTPRequestParser.parse(
        hookRequest(body: body, token: token, path: "/hook-extra"),
        authenticationToken: token,
        isComplete: true
      ),
      .rejected(404),
      "hook requests require the exact path"
    )
    test.expectEqual(
      HookHTTPRequestParser.parse(
        Data(valid.prefix(valid.count / 2)),
        authenticationToken: token,
        isComplete: false
      ),
      .incomplete,
      "fragmented hook requests remain incomplete"
    )
  }

  @MainActor
  private static func hiddenFilesAffectExtensionFingerprint(_ test: TestHarness) {
    let directory = securityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      let hiddenScript = directory.appendingPathComponent(".probe.sh")
      try Data("first".utf8).write(to: hiddenScript)
      let first = ExtensionDirectoryScanner.fingerprint(directory: directory)
      try Data("second".utf8).write(to: hiddenScript)
      let second = ExtensionDirectoryScanner.fingerprint(directory: directory)
      test.expect(first != nil, "hidden extension files produce a fingerprint")
      test.expect(second != nil, "modified hidden extension files produce a fingerprint")
      test.expect(first != second, "hidden extension files participate in trust fingerprints")
    } catch {
      test.expect(false, "hidden extension fingerprint test succeeds: \(error)")
    }
  }

  @MainActor
  private static func credentialFileCoordination(_ test: TestHarness) {
    let directory = securityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("credentials.json")
    do {
      try Data(#"{"token":"old","vendorField":42}"#.utf8).write(to: url, options: .atomic)
      try CredentialFileStore.update(at: url.path) { document in
        document["token"] = "new"
      }
      let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
      test.expectEqual(
        updated?["token"] as? String, "new", "credential updates replace the requested field")
      test.expectEqual(
        updated?["vendorField"] as? Int, 42, "credential updates preserve vendor fields")
      test.expectEqual(filePermissions(url), 0o600, "credential files use owner-only permissions")

      do {
        try CredentialFileStore.update(at: url.path) { document in
          try Data(#"{"token":"vendor-new"}"#.utf8).write(to: url, options: .atomic)
          document["token"] = "iles-new"
        }
        test.expect(false, "credential updates reject external races")
      } catch {
        test.expect(
          error is CredentialFileStore.StoreError, "credential races return the typed store error")
      }
    } catch {
      test.expect(false, "credential file coordination succeeds: \(error)")
    }
  }

  @MainActor
  private static func antigravityCredentialParsing(_ test: TestHarness) {
    let json =
      #"{"token":{"access_token":"access","refresh_token":"refresh","expiry":"2030-01-02T03:04:05Z"}}"#
    let encoded = Data(json.utf8).base64EncodedString()
    let credentials = AntigravityKeychainCredentialLoader.parse(raw: "go-keyring-base64:\(encoded)")
    test.expectEqual(
      credentials?.accessToken, "access", "go-keyring payload exposes the access token")
    test.expectEqual(
      credentials?.refreshToken, "refresh", "go-keyring payload exposes the refresh token")
    test.expect(credentials?.expiresAt != nil, "go-keyring payload parses the expiration date")
  }

  @MainActor
  private static func boundedConcurrentSubprocessOutput(_ test: TestHarness) async {
    let script = "i=0; while [ $i -lt 20000 ]; do echo out; echo err >&2; i=$((i+1)); done"
    do {
      let output = try await SubprocessSupport.run(
        executablePath: "/bin/sh",
        arguments: ["-c", script],
        outputLimit: 4_096,
        timeout: 5
      )
      test.expect(output.isSuccess, "bounded subprocess output completes successfully")
      test.expect(output.wasTruncated, "bounded subprocess output records truncation")
      test.expect(
        output.standardOutput.utf8.count + output.standardError.utf8.count <= 4_096,
        "stdout and stderr share the configured output bound"
      )
    } catch {
      test.expect(false, "bounded subprocess output succeeds: \(error)")
    }
  }

  @MainActor
  private static func subprocessTimeout(_ test: TestHarness) async {
    let start = ContinuousClock.now
    do {
      _ = try await SubprocessSupport.run(
        executablePath: "/bin/sh",
        arguments: ["-c", "sleep 5"],
        timeout: 0.1
      )
      test.expect(false, "subprocess timeout throws")
    } catch {
      test.expect(
        error is SubprocessSupport.ExecutionError, "subprocess timeout returns an execution error")
    }
    test.expect(start.duration(to: .now) < .seconds(2), "subprocess timeout terminates promptly")
  }

  private static func hookRequest(body: Data, token: String, path: String) -> Data {
    var request = Data(
      "POST \(path) HTTP/1.1\r\nContent-Type: application/json\r\nX-Iles-Token: \(token)\r\nContent-Length: \(body.count)\r\n\r\n"
        .utf8
    )
    request.append(body)
    return request
  }

  private static func securityTestDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("iles-security-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func filePermissions(_ url: URL) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
  }
}
