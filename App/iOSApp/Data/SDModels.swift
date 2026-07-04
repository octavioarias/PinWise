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

/// A physical vial in inventory. CloudKit-safe. `0` sentinels mean "unknown/not set" for
/// value types that can't be optional cleanly across CloudKit.
@Model
final class StoredVial {
    var id: UUID = UUID()
    var compoundName: String = ""
    var label: String = ""
    var massMicrograms: Double = 0            // total peptide when full
    var solventVolumeMilliliters: Double = 0  // 0 = not reconstituted
    var perDoseMicrograms: Double = 0         // the dose drawn from this vial
    var dosesTaken: Int = 0
    var cost: Double = 0                       // 0 = unknown
    var expirationDate: Date?
    var dateAcquired: Date = Date()
    var notes: String = ""

    init(
        id: UUID = UUID(), compoundName: String = "", label: String = "", massMicrograms: Double = 0,
        solventVolumeMilliliters: Double = 0, perDoseMicrograms: Double = 0, dosesTaken: Int = 0,
        cost: Double = 0, expirationDate: Date? = nil, dateAcquired: Date = Date(), notes: String = ""
    ) {
        self.id = id; self.compoundName = compoundName; self.label = label; self.massMicrograms = massMicrograms
        self.solventVolumeMilliliters = solventVolumeMilliliters; self.perDoseMicrograms = perDoseMicrograms
        self.dosesTaken = dosesTaken; self.cost = cost; self.expirationDate = expirationDate
        self.dateAcquired = dateAcquired; self.notes = notes
    }
}

extension StoredVial {
    var mass: Mass { Mass(micrograms: massMicrograms) }
    var perDose: Mass { Mass(micrograms: perDoseMicrograms) }
    var isReconstituted: Bool { solventVolumeMilliliters > 0 }
    var totalDoses: Int { perDoseMicrograms > 0 ? Int((massMicrograms / perDoseMicrograms).rounded(.down)) : 0 }

    var fractionRemaining: Double {
        guard massMicrograms > 0, perDoseMicrograms > 0 else { return 0 }
        let remaining = max(0, massMicrograms - Double(dosesTaken) * perDoseMicrograms)
        return remaining / massMicrograms
    }

    /// Run-out/cost projection via the verified `InventoryEstimator`. `schedule` comes from a
    /// matching active protocol when available, else as-needed (no run-out date).
    func projection(schedule: DoseSchedule, referenceDate: Date = Date()) -> InventoryEstimator.Projection {
        let vial = Vial(
            compoundID: UUID(),
            mass: mass,
            solventVolumeMilliliters: isReconstituted ? solventVolumeMilliliters : nil,
            cost: cost > 0 ? Decimal(cost) : nil
        )
        return InventoryEstimator.project(
            vial: vial, dose: perDose, dosesTaken: dosesTaken,
            schedule: schedule, referenceDate: referenceDate
        )
    }

    var expiryState: (label: String, isWarning: Bool, isError: Bool)? {
        guard let exp = expirationDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: exp)).day ?? 0
        if days < 0 { return ("Expired", false, true) }
        if days <= 14 { return ("Expires in \(days)d", true, false) }
        return (exp.formatted(.dateTime.month().day().year()), false, false)
    }
}
