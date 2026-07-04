import Foundation

/// One peptide within a multi-component blend vial (e.g. the BPC-157 in "Wolverine").
public struct BlendComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Mass of THIS component present in the vial when full.
    public var massPerVial: Mass

    public init(id: UUID = UUID(), name: String, massPerVial: Mass) {
        self.id = id
        self.name = name
        self.massPerVial = massPerVial
    }
}

/// A vial that contains more than one peptide co-lyophilized in a fixed ratio
/// (the biohacker "blend" — Wolverine, GLOW, etc.).
///
/// The defining constraint the app must honor: **a single injection volume dictates the
/// dose of every component simultaneously.** You cannot dose one component independently
/// of the others — see ``BlendCalculator``.
public struct Blend: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var components: [BlendComponent]
    /// Water added at reconstitution; `nil` until reconstituted.
    public var solventVolumeMilliliters: Double?
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        components: [BlendComponent],
        solventVolumeMilliliters: Double? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.components = components
        self.solventVolumeMilliliters = solventVolumeMilliliters
        self.notes = notes
    }

    /// Total peptide mass across all components (useful for a sanity display).
    public var totalMass: Mass {
        Mass(micrograms: components.reduce(0) { $0 + $1.massPerVial.micrograms })
    }
}
