import Foundation

/// A single subjective self-report attached to a dose (energy, mood, side-effect severity, …).
/// Kept generic so the insights engine can correlate any tracked metric against dose/time.
public struct SubjectiveMetric: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Normalized 0–10 scale for consistent charting; UI can relabel per metric.
    public var value: Double

    public init(id: UUID = UUID(), name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = min(10, max(0, value))
    }
}

public extension SubjectiveMetric {
    /// Canonical display name for the energy self-report metric.
    static let energyName = "Energy"
    /// Canonical display name for the side-effect self-report metric.
    static let sideEffectName = "Side effects"

    /// Build subjective metrics from PinWise's two optional 0–10 quick self-reports.
    /// `nil` inputs are omitted; values are clamped to 0…10 by `SubjectiveMetric.init`.
    static func quickReports(energy: Double?, sideEffectSeverity: Double?) -> [SubjectiveMetric] {
        var metrics: [SubjectiveMetric] = []
        if let energy { metrics.append(SubjectiveMetric(name: energyName, value: energy)) }
        if let sideEffectSeverity {
            metrics.append(SubjectiveMetric(name: sideEffectName, value: sideEffectSeverity))
        }
        return metrics
    }
}

/// A recorded injection event — the atomic unit of the log.
public struct DoseLog: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// The protocol this dose fulfills, if it came from one.
    public var protocolID: UUID?
    public var compoundID: UUID
    /// The vial drawn from, enabling inventory decrement and cost-per-dose.
    public var vialID: UUID?
    public var timestamp: Date
    public var dose: Mass
    public var site: InjectionSite?
    public var metrics: [SubjectiveMetric]
    public var notes: String

    public init(
        id: UUID = UUID(),
        protocolID: UUID? = nil,
        compoundID: UUID,
        vialID: UUID? = nil,
        timestamp: Date,
        dose: Mass,
        site: InjectionSite? = nil,
        metrics: [SubjectiveMetric] = [],
        notes: String = ""
    ) {
        self.id = id
        self.protocolID = protocolID
        self.compoundID = compoundID
        self.vialID = vialID
        self.timestamp = timestamp
        self.dose = dose
        self.site = site
        self.metrics = metrics
        self.notes = notes
    }
}
