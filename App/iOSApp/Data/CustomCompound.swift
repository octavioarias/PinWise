import Foundation
import SwiftData
import PeptideKit

/// A compound the user added themselves — outside the verified catalog. PinWise has no data
/// on it, so it bridges with the most conservative posture (research-only, lowest evidence).
/// CloudKit-safe like the other models (defaults everywhere, no unique keys).
@Model
final class CustomCompound {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = CompoundCategory.metabolic.rawValue
    var doseUnitRaw: String = MassUnit.milligram.rawValue
    var notes: String = ""
    var dateAdded: Date = Date()

    init(id: UUID = UUID(), name: String = "", categoryRaw: String = CompoundCategory.metabolic.rawValue,
         doseUnitRaw: String = MassUnit.milligram.rawValue, notes: String = "", dateAdded: Date = Date()) {
        self.id = id; self.name = name; self.categoryRaw = categoryRaw
        self.doseUnitRaw = doseUnitRaw; self.notes = notes; self.dateAdded = dateAdded
    }
}

extension CustomCompound {
    /// Bridge into the value type the pickers and detail views consume.
    var asCompound: Compound {
        Compound(
            id: id,
            name: name,
            category: CompoundCategory(rawValue: categoryRaw) ?? .metabolic,
            regulatoryStatus: .researchOnly,
            evidenceTier: .preclinicalOrFailed,
            preferredDoseUnit: MassUnit(rawValue: doseUnitRaw) ?? .milligram,
            notes: notes
        )
    }
}
