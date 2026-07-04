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
