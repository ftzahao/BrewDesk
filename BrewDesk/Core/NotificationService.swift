//
//  NotificationService.swift
//  BrewDesk
//

import Foundation
import UserNotifications

enum NotificationService {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func post(title: String, body: String, success: Bool = true) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            _ = success

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
