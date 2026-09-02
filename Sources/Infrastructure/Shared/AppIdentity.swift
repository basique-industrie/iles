import Foundation

/// Distinguishes the notarized shipped app from the local development build.
///
/// The two identities use different bundle IDs, data directories, Keychain
/// services, and Claude hook files so they can run side by side.
public struct AppIdentity: Sendable, Equatable {
    public static let shippedBundleIdentifier = "com.jean.iles"
    public static let developmentBundleIdentifier = "com.jean.iles.dev"

    public static let shipped = AppIdentity(bundleIdentifier: shippedBundleIdentifier)
    public static let development = AppIdentity(bundleIdentifier: developmentBundleIdentifier)
    public static let current = AppIdentity()

    public let bundleIdentifier: String
    public let isDevelopment: Bool
    public let displayName: String
    public let dataDirectoryName: String
    public let logDirectoryName: String
    public let logFileName: String
    public let keychainService: String
    public let hookFunctionName: String
    public let hookPortFileName: String
    public let hookAuthFileName: String
    public let hookTempPrefix: String

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? shippedBundleIdentifier) {
        self.bundleIdentifier = bundleIdentifier
        let isDevelopment = bundleIdentifier == Self.developmentBundleIdentifier
        self.isDevelopment = isDevelopment
        if isDevelopment {
            displayName = "Iles Dev"
            dataDirectoryName = ".iles-dev"
            logDirectoryName = "Iles-Dev"
            logFileName = "Iles-Dev.log"
            keychainService = "\(Self.developmentBundleIdentifier).credentials"
            hookFunctionName = "__iles_dev_hook"
            hookPortFileName = "iles-dev-hook-port"
            hookAuthFileName = "iles-dev-hook-auth"
            hookTempPrefix = "iles-dev-hook"
        } else {
            displayName = "Iles"
            dataDirectoryName = ".iles"
            logDirectoryName = "Iles"
            logFileName = "Iles.log"
            keychainService = "\(Self.shippedBundleIdentifier).credentials"
            hookFunctionName = "__iles_hook"
            hookPortFileName = "iles-hook-port"
            hookAuthFileName = "iles-hook-auth"
            hookTempPrefix = "iles-hook"
        }
    }

    public var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
    }

    public var settingsFileURL: URL {
        dataDirectory.appendingPathComponent("settings.json")
    }

    public var extensionsDirectory: URL {
        dataDirectory.appendingPathComponent("extensions", isDirectory: true)
    }

    public var logsDirectory: URL {
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return libraryDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(logDirectoryName, isDirectory: true)
    }

    public var logFileURL: URL {
        logsDirectory.appendingPathComponent(logFileName)
    }

    public var hookPortFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(hookPortFileName)
    }

    public var hookAuthFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(hookAuthFileName)
    }
}
