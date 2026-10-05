import Foundation
import KSCrashRecording

enum CrashRecording {
    static func install(at path: URL) throws -> CrashReportStore? {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = KSCrashConfiguration()
        config.installPath = path.path
        config.enableMemoryIntrospection = false; config.enableQueueNameSearch = false
        config.enableSwapCxaThrow = false; config.enableSigTermMonitoring = false
        config.deadlockWatchdogInterval = 0; config.addConsoleLogToReport = false; config.printPreviousLogOnStartup = false
        config.reportStoreConfiguration.maxReportCount = 3
        try KSCrash.shared.install(with: config)
        let store = KSCrash.shared.reportStore; store?.sink = nil
        return store
    }
}
