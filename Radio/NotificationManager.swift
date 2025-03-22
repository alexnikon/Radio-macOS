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
                self.scheduleWeeklyNotification()
            }
            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    func scheduleWeeklyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Radio"
        content.body = "Прямой эфир!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive // Функция для macOS 15
        
        // Создаем компоненты даты для субботы, 23:00 МСК
        var dateComponents = DateComponents()
        dateComponents.weekday = 7 // Суббота (1 = воскресенье, 7 = суббота)
        dateComponents.hour = 23
        dateComponents.minute = 0
        dateComponents.timeZone = TimeZone(identifier: "Europe/Moscow")
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "radio-t-live", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    // Обработка уведомлений когда приложение активно
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.sound, .banner])
    }
} 