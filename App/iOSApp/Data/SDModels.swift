import Foundation
import SwiftData
import PeptideKit

/// A logged injection, persisted with SwiftData.
///
/// Kept **CloudKit-safe** so private-database sync can be switched on later without a
/// migration: every property has a default, there are no unique constraints, and there are
/// no required relationships. Bridges to PeptideKit value types via `asDomain()` so the
/// pure domain logic (site rotation, adherence) can consume logged data.
@Model
final class LoggedDose {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var compoundName: String = ""
    var doseMicrograms: Double = 0
    var siteRaw: String?
    var notes: String = ""
    /// Optional 0–10 quick self-reports (nil = not recorded).
    var energy: Double?
    var sideEffectSeverity: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        compoundName: String = "",
        doseMicrograms: Double = 0,
        siteRaw: String? = nil,
        notes: String = "",
        energy: Double? = nil,
        sideEffectSeverity: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.compoundName = compoundName
        self.doseMicrograms = doseMicrograms
        self.siteRaw = siteRaw
        self.notes = notes
        self.energy = energy
        self.sideEffectSeverity = sideEffectSeverity
    }
}

extension LoggedDose {
    var dose: Mass { Mass(micrograms: doseMicrograms) }
    var site: InjectionSite? { siteRaw.flatMap(InjectionSite.init(rawValue:)) }

    /// Bridge to the pure-domain type so PeptideKit logic can operate on logs.
    func asDomain() -> DoseLog {
        let compoundID = CompoundCatalog.all.first { $0.name == compoundName }?.id ?? UUID()
        return DoseLog(id: id, compoundID: compoundID, timestamp: timestamp, dose: dose, site: site, notes: notes)
    }
}

/// A saved dosing protocol (compound + dose + schedule). CloudKit-safe like `LoggedDose`.
@Model
final class SavedProtocol {
    var id: UUID = UUID()
    var name: String = ""
    var compoundName: String = ""
    var doseMicrograms: Double = 0
    var scheduleKindRaw: String = "daily"   // DoseSchedule.Kind rawValue
    var intervalDays: Int = 1
    var weekdays: [Int] = []                 // 1 = Sunday … 7 = Saturday
    var startDate: Date = Date()
    var isActive: Bool = true
    var notes: String = ""

    init(
        id: UUID = UUID(), name: String = "", compoundName: String = "", doseMicrograms: Double = 0,
        scheduleKindRaw: String = "daily", intervalDays: Int = 1, weekdays: [Int] = [],
        startDate: Date = Date(), isActive: Bool = true, notes: String = ""
    ) {
        self.id = id; self.name = name; self.compoundName = compoundName; self.doseMicrograms = doseMicrograms
        self.scheduleKindRaw = scheduleKindRaw; self.intervalDays = intervalDays; self.weekdays = weekdays
        self.startDate = startDate; self.isActive = isActive; self.notes = notes
    }
}

extension SavedProtocol {
    var dose: Mass { Mass(micrograms: doseMicrograms) }
    var scheduleKind: DoseSchedule.Kind { DoseSchedule.Kind(rawValue: scheduleKindRaw) ?? .daily }
    var schedule: DoseSchedule { DoseSchedule(kind: scheduleKind, intervalDays: intervalDays, weekdays: weekdays) }

    func asDomain() -> DoseProtocol {
        let cid = CompoundCatalog.all.first { $0.name == compoundName }?.id ?? UUID()
        return DoseProtocol(id: id, name: name, compoundID: cid, dose: dose, schedule: schedule,
                            startDate: startDate, isActive: isActive, notes: notes)
    }

    /// Next scheduled dose date on/after `date` (nil for as-needed / none upcoming).
    func nextDose(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        let from = max(calendar.startOfDay(for: startDate), calendar.startOfDay(for: date))
        let end = calendar.date(byAdding: .day, value: 90, to: from) ?? from
        return AdherenceCalculator.expectedDates(schedule: schedule, start: from, end: end, calendar: calendar).first
    }

    /// Human cadence label for display.
    var cadenceText: String {
        switch scheduleKind {
        case .daily: return "Daily"
        case .everyNDays: return "Every \(intervalDays) days"
        case .weekly, .specificWeekdays:
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = weekdays.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            return days.isEmpty ? "Weekly" : days.joined(separator: ", ")
        case .asNeeded: return "As needed"
        }
    }
}
