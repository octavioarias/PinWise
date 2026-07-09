import Foundation
import CryptoKit
import SwiftData
import PeptideKit

/// A stable, deterministic compound ID for names outside the verified catalog (custom or
/// legacy compounds). Derived from the name so every DoseLog/DoseProtocol bridge agrees —
/// a random fallback would make each log of the same compound look like a different one,
/// silently breaking per-compound site-rotation history.
func stableCompoundID(for name: String) -> UUID {
    if let c = CompoundCatalog.all.first(where: { $0.name == name }) { return c.id }
    let digest = Insecure.MD5.hash(data: Data(name.utf8))
    let b = Array(digest)
    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
}

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
    /// The vial this dose drew from — enables inventory attribution, restore-on-delete, and
    /// cost-per-dose. Optional/default nil to stay CloudKit-safe.
    var vialID: UUID?
    /// Whether THIS record actually decremented its vial's dosesTaken. For a stack that resolves
    /// to one blend vial we decrement once but stamp vialID on every line, so only the record that
    /// decremented may restore it on delete — keeps decrement and restore symmetric.
    var didDecrement: Bool = false
    /// Optional 0–10 quick self-reports (nil = not recorded).
    var energy: Double?
    var sideEffectSeverity: Double?
    /// The protocol this dose fulfilled, if it came from one — enables real per-protocol
    /// adherence (matching logs to their source schedule). Additive optional to stay
    /// CloudKit-safe; nil = one-time dose not tied to any protocol (and every legacy row).
    var protocolID: UUID? = nil

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        compoundName: String = "",
        doseMicrograms: Double = 0,
        siteRaw: String? = nil,
        notes: String = "",
        vialID: UUID? = nil,
        didDecrement: Bool = false,
        energy: Double? = nil,
        sideEffectSeverity: Double? = nil,
        protocolID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.compoundName = compoundName
        self.doseMicrograms = doseMicrograms
        self.siteRaw = siteRaw
        self.notes = notes
        self.vialID = vialID
        self.didDecrement = didDecrement
        self.energy = energy
        self.sideEffectSeverity = sideEffectSeverity
        self.protocolID = protocolID
    }
}

extension LoggedDose {
    var dose: Mass { Mass(micrograms: doseMicrograms) }
    var site: InjectionSite? { siteRaw.flatMap(InjectionSite.init(rawValue:)) }

    /// Bridge to the pure-domain type so PeptideKit logic can operate on logs.
    /// Carries the 0–10 quick self-reports through as `SubjectiveMetric`s (previously dropped),
    /// and the source-protocol link so domain adherence can attribute the dose.
    func asDomain() -> DoseLog {
        DoseLog(id: id, protocolID: protocolID, compoundID: stableCompoundID(for: compoundName),
                vialID: vialID, timestamp: timestamp, dose: dose, site: site,
                metrics: SubjectiveMetric.quickReports(energy: energy, sideEffectSeverity: sideEffectSeverity),
                notes: notes)
    }
}

/// One compound + dose within a protocol. 1 item = single-compound; 2+ = a stack.
struct ProtocolItem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var compoundName: String = ""
    var doseMicrograms: Double = 0
    /// The inventory vial this line draws from (nil = not linked to a specific vial).
    var vialID: UUID? = nil
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

    init(
        id: UUID = UUID(), name: String = "", items: [ProtocolItem] = [],
        scheduleKindRaw: String = "daily", intervalDays: Int = 1, weekdays: [Int] = [],
        startDate: Date = Date(), isActive: Bool = true, notes: String = "",
        remindersOn: Bool = false, reminderHour: Int = 9, reminderMinute: Int = 0
    ) {
        self.id = id; self.name = name; self.items = items
        self.scheduleKindRaw = scheduleKindRaw; self.intervalDays = intervalDays; self.weekdays = weekdays
        self.startDate = startDate; self.isActive = isActive; self.notes = notes
        self.remindersOn = remindersOn; self.reminderHour = reminderHour; self.reminderMinute = reminderMinute
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

    /// The dose to show/use — always the dose the user set. The app never auto-advances a dose
    /// over time; every dose change is an explicit user edit to the protocol (record-keeper posture).
    var effectiveDose: Mass { dose }

    var scheduleKind: DoseSchedule.Kind { DoseSchedule.Kind(rawValue: scheduleKindRaw) ?? .daily }
    var schedule: DoseSchedule { DoseSchedule(kind: scheduleKind, intervalDays: intervalDays, weekdays: weekdays) }

    func asDomain() -> DoseProtocol {
        DoseProtocol(id: id, name: name, compoundID: stableCompoundID(for: compoundName), dose: dose,
                     schedule: schedule, startDate: startDate, isActive: isActive, notes: notes)
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
    /// The unit this value was entered in (e.g. "lb", "kg", "in", "cm"). Stamped at write so the
    /// global lb/kg toggle can no longer reinterpret a historical row's stored number. Additive
    /// optional to stay CloudKit-safe; nil = legacy row → read paths fall back to the global flag.
    var unitRaw: String? = nil

    init(id: UUID = UUID(), timestamp: Date = Date(), typeRaw: String = "", value: Double = 0, notes: String = "", unitRaw: String? = nil) {
        self.id = id; self.timestamp = timestamp; self.typeRaw = typeRaw; self.value = value; self.notes = notes; self.unitRaw = unitRaw
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
    /// Reconstitution volume; nil = not yet reconstituted / no volume set. (Was a `0` sentinel.)
    var solventVolumeMilliliters: Double? = nil
    /// Target dose of the PRIMARY API (apis.first); nil = no target set. (Was a `0` sentinel.)
    var perDoseMicrograms: Double? = nil
    var dosesTaken: Int = 0
    /// Acquisition cost as a real `Decimal` (money is never a `Double`); nil = unknown, which is
    /// now distinct from a genuine 0 / comped vial. Mirrors the domain `Vial.cost: Decimal?`.
    var cost: Decimal? = nil
    var expirationDate: Date?
    var dateAcquired: Date = Date()
    var notes: String = ""
    var isPremixed: Bool = false                // true = came ready-to-use from a pharmacy
    /// When this vial was reconstituted — provenance the domain `Vial` carries, used for
    /// beyond-use-date / freshness display. Additive optional to stay CloudKit-safe; nil =
    /// unknown (legacy rows, premixed, or not yet mixed).
    var dateReconstituted: Date? = nil

    init(
        id: UUID = UUID(), label: String = "", apis: [VialAPI] = [], solventVolumeMilliliters: Double? = nil,
        perDoseMicrograms: Double? = nil, dosesTaken: Int = 0, cost: Decimal? = nil, expirationDate: Date? = nil,
        dateAcquired: Date = Date(), notes: String = "", isPremixed: Bool = false,
        dateReconstituted: Date? = nil
    ) {
        self.id = id; self.label = label; self.apis = apis; self.solventVolumeMilliliters = solventVolumeMilliliters
        self.perDoseMicrograms = perDoseMicrograms; self.dosesTaken = dosesTaken; self.cost = cost
        self.expirationDate = expirationDate; self.dateAcquired = dateAcquired; self.notes = notes
        self.isPremixed = isPremixed; self.dateReconstituted = dateReconstituted
    }
}

extension StoredVial {
    /// CloudKit-safe manual cascade for vial deletion. There is no `@Relationship` to cascade
    /// (the posture forbids them), so every soft UUID link pointing at this vial must be nilled
    /// by hand before removal — otherwise deleting a vial leaves dangling `vialID`s on logs and
    /// protocols, and a stale `didDecrement` could later mis-restore a vial that no longer exists.
    ///
    /// For each dose drawn from this vial: clear `vialID` and reset `didDecrement` (nothing left
    /// to restore to). For each protocol whose items reference it: rebuild `items` nilling the
    /// matching `vialID` and reassign the array so SwiftData re-persists the JSON blob. Then delete.
    func reconcileDelete(in context: ModelContext,
                         doses: [LoggedDose], protocols: [SavedProtocol]) {
        for dose in doses where dose.vialID == id {
            dose.vialID = nil
            dose.didDecrement = false
        }
        for proto in protocols where proto.items.contains(where: { $0.vialID == id }) {
            proto.items = proto.items.map { item in
                var updated = item
                if updated.vialID == id { updated.vialID = nil }
                return updated
            }
        }
        context.delete(self)
    }

    var isBlend: Bool { apis.count > 1 }
    var primaryAPI: VialAPI? { apis.first }
    var primaryMass: Mass { Mass(micrograms: primaryAPI?.massMicrograms ?? 0) }
    var perDose: Mass { Mass(micrograms: perDoseMicrograms ?? 0) }
    var isReconstituted: Bool { (solventVolumeMilliliters ?? 0) > 0 }
    /// Names of every API — used to match logged doses to this vial.
    var apiNames: [String] { apis.map(\.name) }

    var displayName: String {
        if !label.isEmpty { return label }
        return apis.isEmpty ? "Vial" : apis.map(\.name).joined(separator: " + ")
    }

    var primaryConcentrationMgPerMl: Double? {
        guard let p = primaryAPI, let vol = solventVolumeMilliliters, vol > 0 else { return nil }
        return (p.massMicrograms / vol) / 1_000
    }

    var totalDoses: Int {
        guard let p = primaryAPI, let perDose = perDoseMicrograms, perDose > 0 else { return 0 }
        return Int((p.massMicrograms / perDose).rounded(.down))
    }

    var fractionRemaining: Double {
        guard let p = primaryAPI, p.massMicrograms > 0, let perDose = perDoseMicrograms, perDose > 0 else { return 0 }
        let remaining = max(0, p.massMicrograms - Double(dosesTaken) * perDose)
        return remaining / p.massMicrograms
    }

    /// Run-out/cost projection (anchored on the primary API) via the verified estimator.
    func projection(schedule: DoseSchedule, referenceDate: Date = Date()) -> InventoryEstimator.Projection {
        let vial = Vial(
            compoundID: UUID(),
            mass: primaryMass,
            solventVolumeMilliliters: isReconstituted ? solventVolumeMilliliters : nil,
            cost: cost
        )
        return InventoryEstimator.project(
            vial: vial, dose: perDose, dosesTaken: dosesTaken,
            schedule: schedule, referenceDate: referenceDate
        )
    }

    /// For a blend, the amount of each API delivered per dose — the primary's dose fixes the
    /// draw volume and the rest scale with it. Requires a reconstituted/known volume.
    func doseBreakdown() -> [BlendComponentDose]? {
        guard isBlend, let vol = solventVolumeMilliliters, vol > 0, let p = primaryAPI,
              p.massMicrograms > 0, let perDose = perDoseMicrograms, perDose > 0 else { return nil }
        let concPrimary = p.massMicrograms / vol
        let drawVolume = perDose / concPrimary
        let blend = Blend(name: displayName,
                          components: apis.map { BlendComponent(name: $0.name, massPerVial: Mass(micrograms: $0.massMicrograms)) })
        return try? BlendCalculator.dose(blend: blend, solventVolumeMilliliters: vol,
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
