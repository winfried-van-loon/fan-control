import Foundation
import ServiceManagement

/// Starts the app automatically when the user logs in (System Settings → General → Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// True when macOS registered the item but the user switched it off in System Settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Debug aid: `FanControl --login-item on|off|status`.
    static func runCommand(_ arg: String) -> Never {
        do {
            switch arg {
            case "on": try setEnabled(true)
            case "off": try setEnabled(false)
            default: break
            }
            print("status: \(SMAppService.mainApp.status.rawValue) (0 notRegistered, 1 enabled, 2 requiresApproval, 3 notFound)")
            exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
