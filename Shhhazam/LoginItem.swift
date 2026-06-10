//
//  LoginItem.swift
//  Shhhazam
//
//  Thin wrapper over SMAppService for "launch at login". The service's
//  status is the source of truth, so the UI reflects it directly.
//

import Foundation
import ServiceManagement
import Combine

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail (e.g. running an unsigned debug build from
            // a transient location). Fall through and report the real state.
            NSLog("Shhhazam: login item toggle failed: \(error.localizedDescription)")
        }
        refresh()
    }
}
