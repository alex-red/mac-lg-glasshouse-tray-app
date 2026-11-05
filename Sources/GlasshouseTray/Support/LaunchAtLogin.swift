import ServiceManagement
import os

@MainActor
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.github.alex-red.GlasshouseTray", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Could not change login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
