import Foundation
import ServiceManagement
import OSLog

@MainActor
class LaunchAtLoginManager: ObservableObject {
    private let logger = Logger(subsystem: "com.magpie.sound2text", category: "LaunchAtLogin")
    
    @Published private(set) var isEnabled: Bool = false
    
    init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Successfully registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Successfully unregistered from launch at login")
            }
            refreshStatus()
        } catch {
            logger.error("Failed to update launch at login status: \(error.localizedDescription)")
            // Reset to actual system status
            refreshStatus()
        }
    }
}


