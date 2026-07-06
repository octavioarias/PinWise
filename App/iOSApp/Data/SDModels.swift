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
    /// The vial this dose drew from — enables inventory decrement, restore-on-delete, and
    /// cost-per-dose. Optional/default nil to stay CloudKit-safe.
    var vialID: UUID?
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
        vialID: UUID? = nil,
        energy: Double? = nil,
        sideEffectSeverity: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.compoundName = compoundName
        self.doseMicrograms = doseMicrograms
        self.siteRaw = siteRaw
        self.notes = notes
        self.vialID = vialID
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
        return DoseLog(id: id, compoundID: compoundID, vialID: vialID, timestamp: timestamp, dose: dose, site: site, notes: notes)
    }
}

/// One compound + dose within a protocol. 1 item = single-compound; 2+ = a stack.
struct ProtocolItem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var compoundName: String = ""
    var doseMicrograms: Double = 0
}

/// A saved dosing protocol — one shared schedule covering one or more compounds (a stack).
/// CloudKit-safe like `LoggedDose`.
@Model
final class SavedProtocol {
    var id: UUID = UUID()
    var name: String = ""
    var items: [ProtocolItem] = []           // 1 = single compound; 2+ = a stack
    var scheduleKindRaw: String = "daily"   // DoseSchedule.Kind rawValue
    var intervalDays: Int = 1
    var weekdays: [Int] = []                 // 1 = Sunday … 7 = Saturday
    var startDate: Date = Date()
    var isActive: Bool = true
    var notes: String = ""
    var remindersOn: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    /// Optional ramp-up plan (TitrationTemplate.id); empty = fixed dose.
    var titrationTemplateID: String = ""

    init(
        id: UUID = UUID(), name: String = "", items: [ProtocolItem] = [],
        scheduleKindRaw: String = "daily", intervalDays: Int = 1, weekdays: [Int] = [],
        startDate: Date = Date(), isActive: Bool = true, notes: String = "",
        remindersOn: Bool = false, reminderHour: Int = 9, reminderMinute: Int = 0,
        titrationTemplateID: String = ""
    ) {
        self.id = id; self.name = name; self.items = items
        self.scheduleKindRaw = scheduleKindRaw; self.intervalDays = intervalDays; self.weekdays = weekdays
        self.startDate = startDate; self.isActive = isActive; self.notes = notes
        self.remindersOn = remindersOn; self.reminderHour = reminderHour; self.reminderMinute = reminderMinute
        self.titrationTemplateID = titrationTemplateID
    }
}

extension SavedProtocol {
    var isStack: Bool { items.count > 1 }
    var primaryItem: ProtocolItem? { items.first }
    /// Primary compound name — kept for call sites that show a single compound.
    var compoundName: String { primaryItem?.compoundName ?? "" }
    /// Every compound in the protocol — used to match logs and inventory.
    var compoundNames: [String] { items.map(\.compoundName) }
    /// Primary dose.
    var dose: Mass { Mass(micrograms: primaryItem?.doseMicrograms ?? 0) }
    /// Human summary of contents, e.g. "Semaglutide · BPC-157".
    var contentsSummary: String { items.isEmpty ? "No compounds" : compoundNames.joined(separator: " · ") }

    // MARK: Ramp-up (titration)

    var titrationTemplate: TitrationTemplate? {
        titrationTemplateID.isEmpty ? nil : TitrationTemplates.all.first { $0.id == titrationTemplateID }
    }
    var isTitrating: Bool { titrationTemplate != nil }
    /// The titration phase active today (or the last phase once the ramp completes).
    func currentTitrationPhase(on date: Date = Date()) -> TitrationPlanner.Phase? {
        guard let t = titrationTemplate else { return nil }
        let phases = TitrationPlanner.plan(steps: t.steps, startDate: startDate)
        return TitrationPlanner.phase(on: date, in: phases) ?? phases.last
    }
    /// Dose to show/use now: the ramp-up phase dose if titrating, else the primary item's dose.
    var effectiveDose: Mass { currentTitrationPhase()?.dose ?? dose }
    /// Short "step N of M" label while ramping.
    var titrationLabel: String? {
        guard let t = titrationTemplate, let phase = currentTitrationPhase() else { return nil }
        return "Ramp-up · step \(phase.id + 1) of \(t.steps.count)"
    }

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

/// A logged lab value / body metric (A1c, glucose, lipids, blood pressure, weight, waist) at a
/// point in time. Lets users watch biomarkers move with their protocol. CloudKit-safe.
@Model
final class BiomarkerEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var typeRaw: String = ""   // BiomarkerType rawValue
    var value: Double = 0
    var notes: String = ""

    init(id: UUID = UUID(), timestamp: Date = Date(), typeRaw: String = "", value: Double = 0, notes: String = "") {
        self.id = id; self.timestamp = timestamp; self.typeRaw = typeRaw; self.value = value; self.notes = notes
    }
}

/// A self-reported symptom / side effect at a point in time (0–10 severity). Independent of
/// doses so users can log how they feel anytime. CloudKit-safe (defaults, no unique keys).
@Model
final class SymptomEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var symptomRaw: String = ""   // SymptomType rawValue
    var severity: Int = 0         // 0–10
    var notes: String = ""

    init(id: UUID = UUID(), timestamp: Date = Date(), symptomRaw: String = "", severity: Int = 0, notes: String = "") {
        self.id = id; self.timestamp = timestamp; self.symptomRaw = symptomRaw; self.severity = severity; self.notes = notes
    }
}

/// One active pharmaceutical ingredient (API) inside a vial's formula.
struct VialAPI: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var massMicrograms: Double = 0
}

/// A physical vial in inventory — i.e. a *formula* of one or more APIs. One API = a
/// single-compound vial; two or more = a blend. CloudKit-safe (defaults; no unique keys).
@Model
final class StoredVial {
    var id: UUID = UUID()
    var label: String = ""
    var apis: [VialAPI] = []                    // 1 = single-compound vial; 2+ = a blend
    var solventVolumeMilliliters: Double = 0    // 0 = not yet reconstituted / no volume set
    var perDoseMicrograms: Double = 0           // target dose of the PRIMARY API (apis.first)
    var dosesTaken: Int = 0
    var cost: Double = 0                         // 0 = unknown
    var expirationDate: Date?
    var dateAcquired: Date = Date()
    var notes: String = ""
    var isPremixed: Bool = false                // true = came ready-to-use from a pharmacy

    init(
        id: UUID = UUID(), label: String = "", apis: [VialAPI] = [], solventVolumeMilliliters: Double = 0,
        perDoseMicrograms: Double = 0, dosesTaken: Int = 0, cost: Double = 0, expirationDate: Date? = nil,
        dateAcquired: Date = Date(), notes: String = "", isPremixed: Bool = false
    ) {
        self.id = id; self.label = label; self.apis = apis; self.solventVolumeMilliliters = solventVolumeMilliliters
        self.perDoseMicrograms = perDoseMicrograms; self.dosesTaken = dosesTaken; self.cost = cost
        self.expirationDate = expirationDate; self.dateAcquired = dateAcquired; self.notes = notes
        self.isPremixed = isPremixed
    }
}

extension StoredVial {
    var isBlend: Bool { apis.count > 1 }
    var primaryAPI: VialAPI? { apis.first }
    var primaryMass: Mass { Mass(micrograms: primaryAPI?.massMicrograms ?? 0) }
    var perDose: Mass { Mass(micrograms: perDoseMicrograms) }
    var isReconstituted: Bool { solventVolumeMilliliters > 0 }
    /// Names of every API — used to match logged doses to this vial.
    var apiNames: [String] { apis.map(\.name) }

    var displayName: String {
        if !label.isEmpty { return label }
        return apis.isEmpty ? "Vial" : apis.map(\.name).joined(separator: " + ")
    }

    var primaryConcentrationMgPerMl: Double? {
        guard let p = primaryAPI, solventVolumeMilliliters > 0 else { return nil }
        return (p.massMicrograms / solventVolumeMilliliters) / 1_000
    }

    var totalDoses: Int {
        guard let p = primaryAPI, perDoseMicrograms > 0 else { return 0 }
        return Int((p.massMicrograms / perDoseMicrograms).rounded(.down))
    }

    var fractionRemaining: Double {
        guard let p = primaryAPI, p.massMicrograms > 0, perDoseMicrograms > 0 else { return 0 }
        let remaining = max(0, p.massMicrograms - Double(dosesTaken) * perDoseMicrograms)
        return remaining / p.massMicrograms
    }

    /// Run-out/cost projection (anchored on the primary API) via the verified estimator.
    func projection(schedule: DoseSchedule, referenceDate: Date = Date()) -> InventoryEstimator.Projection {
        let vial = Vial(
            compoundID: UUID(),
            mass: primaryMass,
            solventVolumeMilliliters: isReconstituted ? solventVolumeMilliliters : nil,
            cost: cost > 0 ? Decimal(cost) : nil
        )
        return InventoryEstimator.project(
            vial: vial, dose: perDose, dosesTaken: dosesTaken,
            schedule: schedule, referenceDate: referenceDate
        )
    }

    /// For a blend, the amount of each API delivered per dose — the primary's dose fixes the
    /// draw volume and the rest scale with it. Requires a reconstituted/known volume.
    func doseBreakdown() -> [BlendComponentDose]? {
        guard isBlend, isReconstituted, let p = primaryAPI, p.massMicrograms > 0, perDoseMicrograms > 0 else { return nil }
        let concPrimary = p.massMicrograms / solventVolumeMilliliters
        let drawVolume = perDoseMicrograms / concPrimary
        let blend = Blend(name: displayName,
                          components: apis.map { BlendComponent(name: $0.name, massPerVial: Mass(micrograms: $0.massMicrograms)) })
        return try? BlendCalculator.dose(blend: blend, solventVolumeMilliliters: solventVolumeMilliliters,
                                         drawVolumeMilliliters: drawVolume).components
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
