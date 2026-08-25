import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func reconcile(engine: ScheduleEngine, leadMinutes: Int = 15, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: centerIdentifiers)

        var identifiers: [String] = []
        for offset in 0..<14 {
            guard let day = engine.calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for occurrence in engine.occurrences(on: day) where occurrence.start > now {
                guard let fireDate = engine.calendar.date(byAdding: .minute, value: -leadMinutes, to: occurrence.start) else { continue }
                let id = "class-\(occurrence.id)"
                identifiers.append(id)
                let content = UNMutableNotificationContent()
                content.title = "\(occurrence.course.code) starts soon"
                content.body = "\(leadMinutes) minutes until \(occurrence.title)."
                content.sound = .default
                let components = engine.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }

            if let item = engine.academicException(on: day) {
                let hour = item.kind == .noClass ? 7 : 9
                guard
                    let fireDate = engine.occurrenceDate(on: day, hour: hour, minute: 0),
                    fireDate > now
                else { continue }
                let id = "academic-\(item.id)"
                identifiers.append(id)
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.detail
                content.sound = .default
                let components = engine.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
        UserDefaults.standard.set(identifiers, forKey: "notificationIdentifiers")
    }

    func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: centerIdentifiers + leaveIdentifiers)
        UserDefaults.standard.removeObject(forKey: "notificationIdentifiers")
        UserDefaults.standard.removeObject(forKey: "leaveNotificationIdentifiers")
    }

    func scheduleLeaveReminder(
        occurrence: ScheduleOccurrence,
        route: RouteEstimate,
        safetyBufferMinutes: Int,
        calendar: Calendar,
        now: Date = Date()
    ) async {
        let fireDate = occurrence.start.addingTimeInterval(-(route.travelTime + Double(safetyBufferMinutes * 60)))
        guard fireDate > now else { return }
        let center = UNUserNotificationCenter.current()
        let id = "leave-\(occurrence.id)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "Time to leave for \(occurrence.course.code)"
        content.body = "About \(route.wholeMinutes) minutes to \(route.destinationName), plus your \(safetyBufferMinutes)-minute arrival buffer."
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        try? await center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        ))
        var identifiers = leaveIdentifiers.filter { $0 != id }
        identifiers.append(id)
        UserDefaults.standard.set(identifiers, forKey: "leaveNotificationIdentifiers")
    }

    func clearLeaveReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: leaveIdentifiers)
        UserDefaults.standard.removeObject(forKey: "leaveNotificationIdentifiers")
    }

    private var centerIdentifiers: [String] {
        UserDefaults.standard.stringArray(forKey: "notificationIdentifiers") ?? []
    }

    private var leaveIdentifiers: [String] {
        UserDefaults.standard.stringArray(forKey: "leaveNotificationIdentifiers") ?? []
    }
}
