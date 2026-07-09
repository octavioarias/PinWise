import Foundation

/// A unit of mass used for peptide/drug amounts.
///
/// The canonical internal representation everywhere in PeptideKit is the **microgram (µg)**.
/// Peptide doses span mcg (research peptides) to mg (GLP-1s), and storing everything in one
/// base unit keeps conversions and comparisons unambiguous.
public enum MassUnit: String, Codable, CaseIterable, Sendable {
    case microgram = "mcg"
    case milligram = "mg"

    public var microgramsPerUnit: Double {
        switch self {
        case .microgram: return 1
        case .milligram: return 1_000
        }
    }
}

/// A mass amount stored canonically in micrograms.
public struct Mass: Codable, Hashable, Sendable, Comparable {
    /// Canonical value in micrograms (µg).
    public var micrograms: Double

    public init(micrograms: Double) { self.micrograms = micrograms }

    public init(_ value: Double, _ unit: MassUnit) {
        self.micrograms = value * unit.microgramsPerUnit
    }

    public var milligrams: Double { micrograms / 1_000 }

    public func value(in unit: MassUnit) -> Double { micrograms / unit.microgramsPerUnit }

    /// A compact human string that auto-selects mg vs mcg for readability.
    public var displayString: String {
        if micrograms >= 1_000 {
            let mg = milligrams
            return mg == mg.rounded() ? "\(Int(mg)) mg" : String(format: "%.2f mg", mg)
        }
        return micrograms == micrograms.rounded() ? "\(Int(micrograms)) mcg" : String(format: "%.1f mcg", micrograms)
    }

    /// Format in a SPECIFIC unit (no auto mg/mcg switch) — used where the user picked a unit for
    /// a vial/protocol and that choice must hold everywhere the amount is shown. Up to 2 decimals,
    /// trailing zeros trimmed.
    public func displayString(in unit: MassUnit) -> String {
        let v = value(in: unit)
        let rounded = (v * 100).rounded() / 100
        let number = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%g", rounded)
        return "\(number) \(unit.rawValue)"
    }

    public static func mcg(_ v: Double) -> Mass { Mass(v, .microgram) }
    public static func mg(_ v: Double) -> Mass { Mass(v, .milligram) }

    public static func < (lhs: Mass, rhs: Mass) -> Bool { lhs.micrograms < rhs.micrograms }
}

/// A solution strength, stored canonically in micrograms per milliliter. Lets pre-mixed /
/// compounded-pharmacy products (labeled e.g. "2.5 mg/mL") be dosed without reconstitution.
public struct Concentration: Codable, Hashable, Sendable {
    public var microgramsPerMilliliter: Double

    public init(microgramsPerMilliliter: Double) { self.microgramsPerMilliliter = microgramsPerMilliliter }
    public init(mgPerMl: Double) { self.microgramsPerMilliliter = mgPerMl * 1_000 }

    /// Derive from a total mass dissolved in a volume (the reconstitution case).
    public init(mass: Mass, inMilliliters volume: Double) {
        self.microgramsPerMilliliter = volume > 0 ? mass.micrograms / volume : 0
    }

    public var milligramsPerMilliliter: Double { microgramsPerMilliliter / 1_000 }

    public static func mgPerMl(_ v: Double) -> Concentration { Concentration(mgPerMl: v) }
}

/// Insulin-syringe scale. The overwhelmingly common standard is **U-100**
/// (100 units per mL); U-50 and U-40 exist for niche cases.
public enum SyringeScale: String, Codable, CaseIterable, Sendable {
    case u100 = "U-100"
    case u50 = "U-50"
    case u40 = "U-40"

    /// Units marked on the barrel per 1 mL of liquid.
    public var unitsPerMilliliter: Double {
        switch self {
        case .u100: return 100
        case .u50: return 50
        case .u40: return 40
        }
    }
}
