//
//  ShhhazamApp.swift
//  Shhhazam
//
//  Menu-bar-only app (LSUIElement). The AppDelegate owns the model objects so
//  monitoring starts at launch, regardless of whether the popover is open.
//

import SwiftUI
import AppKit

@main
struct ShhhazamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                settings: appDelegate.settings,
                monitor: appDelegate.monitor,
                loginItem: appDelegate.loginItem)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar glyph, reflecting the current monitoring state.
struct MenuBarLabel: View {
    @ObservedObject var monitor: AudioMonitor

    var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        if monitor.isAlerting { return "waveform.badge.exclamationmark" }
        if !monitor.isRunning { return "waveform.slash" }
        return "waveform"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let loginItem = LoginItemManager()
    lazy var monitor = AudioMonitor(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.requestAuthorization()
        monitor.setAlertHandler { NotificationManager.fireTooLoud() }
        monitor.requestMicAccessAndStart()
    }
}
