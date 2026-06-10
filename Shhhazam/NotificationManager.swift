//
//  NotificationManager.swift
//  Shhhazam
//
//  System notifications via UserNotifications.
//

import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func fireTooLoud() {
        let content = UNMutableNotificationContent()
        content.title = "Shhhazam 🤫"
        content.body = "You've been a bit loud — mind the volume."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
