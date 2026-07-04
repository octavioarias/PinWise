import Foundation

/// How often a protocol calls for a dose. Modeled as a struct (rather than an enum
/// with associated values) to stay trivially Codable and to expand cleanly.
public struct DoseSchedule: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case daily
        case everyNDays
        case weekly
        case specificWeekdays
        case asNeeded
    }

    public var kind: Kind
    /// Interval in days when `kind == .everyNDays`.
    public var intervalDays: Int
    /// Weekdays (1 = Sunday … 7 = Saturday) when `kind == .weekly`/`.specificWeekdays`.
    public var weekdays: [Int]

    public init(kind: Kind, intervalDays: Int = 1, weekdays: [Int] = []) {
        self.kind = kind
        self.intervalDays = intervalDays
        self.weekdays = weekdays
    }

    public static let daily = DoseSchedule(kind: .daily)
    public static let weekly = DoseSchedule(kind: .weekly, weekdays: [1]) // default Sunday
    public static func everyNDays(_ n: Int) -> DoseSchedule { DoseSchedule(kind: .everyNDays, intervalDays: max(1, n)) }
    public static func weekdays(_ days: [Int]) -> DoseSchedule { DoseSchedule(kind: .specificWeekdays, weekdays: days) }

    /// Expected number of doses across an inclusive day-count window (approximate for `.weekly`).
    public func expectedDoses(overDays days: Int) -> Double {
        guard days > 0 else { return 0 }
        switch kind {
        case .daily: return Double(days)
        case .everyNDays: return Double(days) / Double(max(1, intervalDays))
        case .weekly: return Double(days) / 7.0 * Double(max(1, weekdays.count))
        case .specificWeekdays: return Double(days) / 7.0 * Double(max(1, weekdays.count))
        case .asNeeded: return 0
        }
    }
}

/// A dosing plan for one compound: the dose, the cadence, and the active window.
public struct DoseProtocol: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var compoundID: UUID
    public var dose: Mass
    public var schedule: DoseSchedule
    public var preferredSites: [InjectionSite]
    public var startDate: Date
    public var endDate: Date?
    public var isActive: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        compoundID: UUID,
        dose: Mass,
        schedule: DoseSchedule,
        preferredSites: [InjectionSite] = [],
        startDate: Date,
        endDate: Date? = nil,
        isActive: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.compoundID = compoundID
        self.dose = dose
        self.schedule = schedule
        self.preferredSites = preferredSites
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.notes = notes
    }
}
