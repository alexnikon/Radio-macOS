import UserNotifications
import Foundation
import Combine

class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationManager()
    
    // Свойство для отслеживания статуса разрешений
    @Published var notificationEnabled: Bool = false
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationEnabled = granted
            }
            
            if granted {
                self.scheduleWeeklyNotifications()
            }
            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    func scheduleWeeklyNotifications() {
        let center = UNUserNotificationCenter.current()
        let preliveId = "radio-t-prelive-2245"
        let liveId = "radio-t-live-2300"
        
        // Обновляем существующие запросы, чтобы избежать дубликатов
        center.removePendingNotificationRequests(withIdentifiers: [preliveId, liveId])
        
        // 1) 22:45 — за 15 минут до эфира
        let preliveContent = UNMutableNotificationContent()
        preliveContent.title = "Radio"
        preliveContent.body = "Трансляция начнется через 15 минут"
        preliveContent.sound = .default
        preliveContent.interruptionLevel = .timeSensitive
        
        var preliveComponents = DateComponents()
        preliveComponents.weekday = 7 // Суббота (1 = воскресенье, 7 = суббота)
        preliveComponents.hour = 22
        preliveComponents.minute = 45
        preliveComponents.timeZone = TimeZone(identifier: "Europe/Moscow")
        
        let preliveTrigger = UNCalendarNotificationTrigger(dateMatching: preliveComponents, repeats: true)
        let preliveRequest = UNNotificationRequest(identifier: preliveId, content: preliveContent, trigger: preliveTrigger)
        
        // 2) 23:00 — начало эфира
        let liveContent = UNMutableNotificationContent()
        liveContent.title = "Radio"
        liveContent.body = "Трансляция начинается"
        liveContent.sound = .default
        liveContent.interruptionLevel = .timeSensitive
        
        var liveComponents = DateComponents()
        liveComponents.weekday = 7
        liveComponents.hour = 23
        liveComponents.minute = 0
        liveComponents.timeZone = TimeZone(identifier: "Europe/Moscow")
        
        let liveTrigger = UNCalendarNotificationTrigger(dateMatching: liveComponents, repeats: true)
        let liveRequest = UNNotificationRequest(identifier: liveId, content: liveContent, trigger: liveTrigger)
        
        center.add(preliveRequest) { error in
            if let error { print("Error scheduling prelive notification: \(error)") }
        }
        center.add(liveRequest) { error in
            if let error { print("Error scheduling live notification: \(error)") }
        }
    }
    
    // Обработка уведомлений когда приложение активно
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.sound, .banner])
    }
} 