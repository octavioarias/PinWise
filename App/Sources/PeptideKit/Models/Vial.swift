import Foundation

/// A physical vial the user owns — the unit of inventory.
///
/// A vial starts lyophilized (`solventVolumeMilliliters == nil`); once the user
/// reconstitutes it, they record the water volume and the concentration becomes known.
public struct Vial: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var compoundID: UUID
    /// Optional user label, e.g. "Batch 3 — 10mg tirz".
    public var label: String
    /// Total peptide mass the vial contained when full.
    public var mass: Mass
    /// Water added at reconstitution; `nil` until reconstituted.
    public var solventVolumeMilliliters: Double?
    public var dateAcquired: Date?
    public var dateReconstituted: Date?
    public var expirationDate: Date?
    /// Purchase cost in the user's currency (kept as Decimal for money math).
    public var cost: Decimal?

    public init(
        id: UUID = UUID(),
        compoundID: UUID,
        label: String = "",
        mass: Mass,
        solventVolumeMilliliters: Double? = nil,
        dateAcquired: Date? = nil,
        dateReconstituted: Date? = nil,
        expirationDate: Date? = nil,
        cost: Decimal? = nil
    ) {
        self.id = id
        self.compoundID = compoundID
        self.label = label
        self.mass = mass
        self.solventVolumeMilliliters = solventVolumeMilliliters
        self.dateAcquired = dateAcquired
        self.dateReconstituted = dateReconstituted
        self.expirationDate = expirationDate
        self.cost = cost
    }

    public var isReconstituted: Bool { (solventVolumeMilliliters ?? 0) > 0 }

    /// Concentration in µg/mL once reconstituted, else `nil`.
    public var concentrationMcgPerMl: Double? {
        guard let v = solventVolumeMilliliters, v > 0 else { return nil }
        return mass.micrograms / v
    }
}
