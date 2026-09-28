import Foundation

public enum IlesSelfTests {
    @MainActor
    public static func run() async -> Int {
        let test = TestHarness()
        await runGeometryAndExtensionTests(test)
        await runSettingsPersistenceTests(test)
        await runComplicationCatalogTests(test)
        await runRuntimeAndPresentationTests(test)
        runIslandPresentationTests(test)
        await runHarnaisRefreshTests(test)
        await runSecurityHardeningTests(test)
        return test.finish()
    }

    static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
