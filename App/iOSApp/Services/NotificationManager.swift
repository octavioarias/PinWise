import Foundation
import UserNotifications
import PeptideKit

/// Schedules per-protocol dose reminders as local notifications. Because `everyNDays`/weekly
/// schedules have no single repeating trigger, it schedules a rolling window of the next N
/// expected dose dates and re-schedules on launch and whenever protocols change.
enum NotificationManager {
    private static let idPrefix = "pinwise-dose-"
    private static let perProtocolCap = 12
    private static let totalCap = 60   // iOS allows 64 pending; stay under.

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Clears PinWise dose reminders and reschedules the rolling window for enabled protocols.
    static func reschedule(protocols: [SavedProtocol]) async {
        let center = UNUserNotificationCenter.current()

        // Only touch our own reminders.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var scheduled = 0

        for p in protocols where p.remindersOn && p.isActive {
            guard scheduled < totalCap else { break }
            let end = cal.date(byAdding: .day, value: 45, to: today) ?? today
            let dates = AdherenceCalculator.expectedDates(
                schedule: p.schedule,
                start: max(today, cal.startOfDay(for: p.startDate)),
                end: end, calendar: cal
            ).prefix(perProtocolCap)

            for (index, day) in dates.enumerated() {
                guard scheduled < totalCap else { break }
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = p.reminderHour
                comps.minute = p.reminderMinute
                if let fire = cal.date(from: comps), fire <= Date() { continue } // skip past times

                let content = UNMutableNotificationContent()
                content.title = "Dose reminder"
                content.body = "\(p.name): \(p.dose.displayString) \(p.compoundName)"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(idPrefix)\(p.id.uuidString)-\(index)",
                    content: content, trigger: trigger
                )
                try? await center.add(request)
                scheduled += 1
            }
        }
    }
}
