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
    /// The unit the user entered this dose in (mg or mcg). Persisted so the protocol's widgets
    /// (Stack + Home) show the dose in the chosen unit. Additive optional (CloudKit-safe); nil =
    /// legacy line → resolve via the linked vial, then the magnitude heuristic.
    var doseUnitRaw: String? = nil

    var doseUnit: MassUnit? { doseUnitRaw.flatMap(MassUnit.init(rawValue:)) }
}

/// One step of a user-built ramp-up (titration) plan: a dose held for a number of days before
/// the next step. Attached to a protocol so its primary dose auto-advances as phases elapse.
struct RampPhase: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var doseMicrograms: Double = 0
    var durationDays: Int = 7
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
    /// User-built ramp-up plan: ordered dose phases. Empty = no ramp (dose is fixed). Additive/
    /// CloudKit-safe (default empty); paired with `rampStartDate`.
    var rampPhases: [RampPhase] = []
    /// Anchor date the ramp phases are measured from. nil = no active ramp.
    var rampStartDate: Date? = nil

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
    /// Human summary of contents, e.g. "Semaglutide · BPC-157". Primary-only: a line backed by
    /// a blend vial contributes just its primary compound. Use `fullContentsSummary(vials:)`
    /// wherever the vials are available to show a blend's full scope.
    var contentsSummary: String { items.isEmpty ? "No compounds" : compoundNames.joined(separator: " · ") }

    /// Full compound scope, expanding any blend vial a line references into every compound it
    /// holds (deduped, order-preserving). The stored `ProtocolItem` keeps only the primary +
    /// `vialID`, so the rest of a blend is recovered here via the vial link.
    func fullCompoundNames(vials: [StoredVial]) -> [String] {
        var names: [String] = []
        for item in items {
            if let vid = item.vialID, let vial = vials.first(where: { $0.id == vid }), vial.isBlend {
                names.append(contentsOf: vial.apiNames)
            } else {
                names.append(item.compoundName)
            }
        }
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `contentsSummary` with blend vials expanded to their full compound scope.
    func fullContentsSummary(vials: [StoredVial]) -> String {
        let names = fullCompoundNames(vials: vials)
        return names.isEmpty ? "No compounds" : names.joined(separator: " · ")
    }

    /// The dose to show/use. Normally the fixed dose the user set — but when a user-built ramp-up
    /// plan is attached, it auto-advances to the phase active today, so cards, the draw calc, and
    /// logging all follow the ramp without any manual edit.
    var effectiveDose: Mass { rampDose() ?? dose }

    /// True when a ramp-up plan is attached and active.
    var hasRampPlan: Bool { !rampPhases.isEmpty && rampStartDate != nil }

    /// The ramp dose for `date` (nil when no plan): before start → first phase; inside a phase →
    /// that phase's dose; past the final phase → hold the last dose.
    func rampDose(on date: Date = Date(), calendar: Calendar = .current) -> Mass? {
        guard let start = rampStartDate, let first = rampPhases.first, let last = rampPhases.last else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return Mass(micrograms: first.doseMicrograms) }
        var acc = 0
        for phase in rampPhases {
            acc += max(phase.durationDays, 1)
            if days < acc { return Mass(micrograms: phase.doseMicrograms) }
        }
        return Mass(micrograms: last.doseMicrograms)
    }

    /// The next scheduled dose increase after `date` (date it takes effect + the new dose), or nil
    /// once the ramp has reached its final phase.
    func nextRampIncrease(after date: Date = Date(), calendar: Calendar = .current) -> (date: Date, dose: Mass)? {
        guard hasRampPlan, let start = rampStartDate else { return nil }
        var boundary = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: date)
        for (i, phase) in rampPhases.enumerated() where i + 1 < rampPhases.count {
            boundary = calendar.date(byAdding: .day, value: max(phase.durationDays, 1), to: boundary) ?? boundary
            if boundary > today { return (boundary, Mass(micrograms: rampPhases[i + 1].doseMicrograms)) }
        }
        return nil
    }

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

    /// Whether a dose for this protocol has already been logged today — matched by the log's
    /// source protocol when present, else (one-time / legacy logs) by any of its compound names.
    /// This is what lets "due today" clear downstream once the pin is logged.
    func loggedToday(in logs: [LoggedDose], calendar: Calendar = .current) -> Bool {
        logs.contains { log in
            calendar.isDateInToday(log.timestamp) &&
                (log.protocolID == id || compoundNames.contains(log.compoundName))
        }
    }

    /// Next scheduled dose strictly AFTER today — the "next pin" to show once today's is logged.
    func nextDoseAfterToday(calendar: Calendar = .current) -> Date? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return nextDose(after: tomorrow, calendar: calendar)
    }

    /// Convenience: the next pin to display given whether today's dose is already logged.
    func upcomingDose(loggedToday: Bool, calendar: Calendar = .current) -> Date? {
        loggedToday ? nextDoseAfterToday(calendar: calendar) : nextDose(calendar: calendar)
    }

    /// Weekday numbers (1 = Sun … 7 = Sat) reordered so the week starts on MONDAY.
    static func mondayFirst(_ days: [Int]) -> [Int] {
        let order = [2, 3, 4, 5, 6, 7, 1]        // Mon Tue Wed Thu Fri Sat Sun
        return order.filter { days.contains($0) }
    }

    /// Minimal, position-independent weekday label (1 = Sun … 7 = Sat): Su M T W Th F S.
    /// Two letters only where a single one would be ambiguous (Thu vs Tue, Sun vs Sat), so a
    /// subset of days stays legible without relying on order — and all of them fit a stat cell.
    static func shortWeekdayLabel(_ d: Int) -> String {
        switch d {
        case 1: return "Su"; case 2: return "M"; case 3: return "T"; case 4: return "W"
        case 5: return "Th"; case 6: return "F"; case 7: return "S"; default: return "?"
        }
    }

    /// Human cadence label for display — weekdays as compact Monday-first letters so every
    /// selected day is visible (e.g. "M W F"), not truncated. Every day (all 7 selected, or a
    /// 1-day interval) collapses to "Daily".
    var cadenceText: String {
        switch scheduleKind {
        case .daily: return "Daily"
        case .everyNDays: return intervalDays <= 1 ? "Daily" : "Every \(intervalDays) days"
        case .weekly, .specificWeekdays:
            let selected = weekdays.filter { (1...7).contains($0) }
            if Set(selected).count == 7 { return "Daily" }        // every day selected
            let labels = SavedProtocol.mondayFirst(weekdays).map(SavedProtocol.shortWeekdayLabel)
            return labels.isEmpty ? "Weekly" : labels.joined(separator: " ")
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

/// A progress ("physique") photo the user captured to track body changes over time. Only
/// lightweight metadata lives in SwiftData (CloudKit-safe: defaults, no relationships); the
/// image itself is a JPEG on disk (`PhysiquePhotoStore`), never a blob in the store or synced.
@Model
final class PhysiquePhoto {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    /// Filename of the JPEG in the physique-photos directory (see `PhysiquePhotoStore`).
    var filename: String = ""
    var notes: String = ""

    init(id: UUID = UUID(), timestamp: Date = Date(), filename: String = "", notes: String = "") {
        self.id = id; self.timestamp = timestamp; self.filename = filename; self.notes = notes
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
    /// The dose unit the user chose when entering this vial (mg or mcg). Persisted so the same
    /// unit is shown everywhere the vial — or any protocol drawing from it — is displayed, instead
    /// of auto-switching by magnitude. Additive optional to stay CloudKit-safe; nil = legacy vial
    /// (falls back to the magnitude heuristic via `doseUnit`).
    var doseUnitRaw: String? = nil
    /// The unit the vial's STRENGTH/concentration is expressed in (mg ⇒ mg/mL, mcg ⇒ mcg/mL).
    /// The user chooses this for pre-mixed vials (whose label states a strength directly); nil for
    /// powder vials, which fall back to the dose unit via `concentrationUnit`. Additive/CloudKit-safe.
    var concentrationUnitRaw: String? = nil

    init(
        id: UUID = UUID(), label: String = "", apis: [VialAPI] = [], solventVolumeMilliliters: Double? = nil,
        perDoseMicrograms: Double? = nil, dosesTaken: Int = 0, cost: Decimal? = nil, expirationDate: Date? = nil,
        dateAcquired: Date = Date(), notes: String = "", isPremixed: Bool = false,
        dateReconstituted: Date? = nil, doseUnitRaw: String? = nil, concentrationUnitRaw: String? = nil
    ) {
        self.id = id; self.label = label; self.apis = apis; self.solventVolumeMilliliters = solventVolumeMilliliters
        self.perDoseMicrograms = perDoseMicrograms; self.dosesTaken = dosesTaken; self.cost = cost
        self.expirationDate = expirationDate; self.dateAcquired = dateAcquired; self.notes = notes
        self.isPremixed = isPremixed; self.dateReconstituted = dateReconstituted; self.doseUnitRaw = doseUnitRaw
        self.concentrationUnitRaw = concentrationUnitRaw
    }

    /// The dose unit chosen for this vial; legacy vials (no stored choice) fall back to the same
    /// magnitude heuristic the old auto display used, so nothing regresses.
    var doseUnit: MassUnit {
        doseUnitRaw.flatMap(MassUnit.init(rawValue:)) ?? MassUnit.auto(forMicrograms: perDoseMicrograms ?? 0)
    }

    /// The unit the vial's concentration is shown in (mg/mL or mcg/mL). Uses the explicit pre-mixed
    /// choice when set, else follows the dose unit so powder vials read consistently.
    var concentrationUnit: MassUnit {
        concentrationUnitRaw.flatMap(MassUnit.init(rawValue:)) ?? doseUnit
    }

    /// Format a mass in THIS vial's chosen unit.
    func formatDose(_ mass: Mass) -> String { mass.displayString(in: doseUnit) }
}

extension MassUnit {
    /// The unit the old auto-display would have picked for a canonical microgram amount — mg at or
    /// above 1 mg, otherwise mcg. Used as the fallback when no explicit choice is stored.
    static func auto(forMicrograms mcg: Double) -> MassUnit { mcg >= 1_000 ? .milligram : .microgram }
}

extension SavedProtocol {
    /// The unit a protocol shows doses in, resolved in priority order: the unit the user entered
    /// for that line → the linked vial's chosen unit → the magnitude heuristic. `forItemAt`
    /// resolves per-line (for a stack); with no index it resolves the primary.
    func doseUnit(forItemAt index: Int? = nil, vials: [StoredVial]) -> MassUnit {
        let item = index.flatMap { items.indices.contains($0) ? items[$0] : nil } ?? primaryItem
        if let u = item?.doseUnit { return u }
        if let vid = item?.vialID, let v = vials.first(where: { $0.id == vid }) { return v.doseUnit }
        return MassUnit.auto(forMicrograms: item?.doseMicrograms ?? 0)
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

    /// The per-shot dose line shown on every vial row, in the vial's chosen unit — a single compound
    /// reads "BPC-157 250 mcg"; a blend lists each compound the shot delivers "GHK-Cu 5 mg · BPC-157
    /// 1.5 mg · …". nil only when no per-shot dose is set yet.
    var perShotSummary: String? {
        guard perDose.micrograms > 0 else { return nil }
        if let breakdown = doseBreakdown() {
            return breakdown.map { "\($0.name) \(formatDose($0.deliveredDose))" }.joined(separator: " · ")
        }
        guard let name = primaryAPI?.name, !name.isEmpty else { return nil }
        return "\(name) \(formatDose(perDose))"
    }

    /// Per-compound strength for the vial row, in the vial's CHOSEN unit (mg or mcg). Single
    /// compound → "BPC-157 5 mg/mL"; a blend lists each API's strength sharing one denominator →
    /// "BPC-157 5 mg / TB-500 3 mg / mL" (or the mcg forms). nil until a solvent volume is known.
    var concentrationSummary: String? {
        guard let vol = solventVolumeMilliliters, vol > 0, !apis.isEmpty else { return nil }
        let unit = concentrationUnit
        let perUnit = unit.microgramsPerUnit
        func fmt(_ perMl: Double) -> String {
            let rounded = (perMl * 100).rounded() / 100          // 2 dp, trailing zeros trimmed
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
        }
        if apis.count == 1, let a = apis.first {
            return "\(a.name) \(fmt((a.massMicrograms / perUnit) / vol)) \(unit.rawValue)/mL"
        }
        let parts = apis.map { "\($0.name) \(fmt(($0.massMicrograms / perUnit) / vol)) \(unit.rawValue)" }
        return parts.joined(separator: " / ") + " / mL"
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

    /// For a blend, the amount of EACH API delivered per shot. A blend is drawn as one shared
    /// solution, so every component's per-shot mass is simply its share of the vial's total mass
    /// scaled by the primary's per-shot dose — the draw volume cancels out. This means the
    /// breakdown resolves even for a powder blend that hasn't been reconstituted yet (no solvent
    /// volume), not only reconstituted ones. Concentration is filled only when a volume is known.
    func doseBreakdown() -> [BlendComponentDose]? {
        guard isBlend, let p = primaryAPI, p.massMicrograms > 0,
              let perDose = perDoseMicrograms, perDose > 0 else { return nil }
        let ratio = perDose / p.massMicrograms          // primary dose as a fraction of primary mass
        let vol = solventVolumeMilliliters ?? 0
        return apis.map { api in
            BlendComponentDose(
                id: api.id,
                name: api.name,
                concentrationMcgPerMl: vol > 0 ? api.massMicrograms / vol : 0,
                deliveredDose: Mass(micrograms: api.massMicrograms * ratio)
            )
        }
    }

    /// Volume + U-100 syringe units to draw for `dose`, from this vial's primary concentration.
    /// nil until reconstituted (no solvent volume ⇒ no draw to compute). For a blend the primary's
    /// dose fixes the single shared draw, so this is the whole-shot volume.
    func draw(forDose dose: Mass, syringe: SyringeScale = .u100) -> (milliliters: Double, units: Double)? {
        guard let p = primaryAPI, p.massMicrograms > 0,
              let vol = solventVolumeMilliliters, vol > 0, dose.micrograms > 0 else { return nil }
        let concMcgPerMl = p.massMicrograms / vol
        guard concMcgPerMl > 0 else { return nil }
        let ml = dose.micrograms / concMcgPerMl
        return (ml, ml * syringe.unitsPerMilliliter)
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
