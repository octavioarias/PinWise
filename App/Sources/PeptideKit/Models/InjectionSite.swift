import Foundation

/// Common subcutaneous injection sites, split left/right so the app can drive a
/// body-map heatmap and least-recently-used rotation suggestions.
public enum InjectionSite: String, Codable, CaseIterable, Sendable, Identifiable {
    case abdomenUpperLeft
    case abdomenUpperRight
    case abdomenLowerLeft
    case abdomenLowerRight
    case flankLeft
    case flankRight
    case thighLeft
    case thighRight
    case gluteLeft
    case gluteRight
    case armLeft
    case armRight

    public var id: String { rawValue }

    /// Coarse region, used for grouping and for the "rotate across regions" heuristic.
    public var region: Region {
        switch self {
        case .abdomenUpperLeft, .abdomenUpperRight, .abdomenLowerLeft, .abdomenLowerRight: return .abdomen
        case .flankLeft, .flankRight: return .flank
        case .thighLeft, .thighRight: return .thigh
        case .gluteLeft, .gluteRight: return .glute
        case .armLeft, .armRight: return .arm
        }
    }

    public var displayName: String {
        switch self {
        case .abdomenUpperLeft: return "Abdomen — upper left"
        case .abdomenUpperRight: return "Abdomen — upper right"
        case .abdomenLowerLeft: return "Abdomen — lower left"
        case .abdomenLowerRight: return "Abdomen — lower right"
        case .flankLeft: return "Flank — left (love handle)"
        case .flankRight: return "Flank — right (love handle)"
        case .thighLeft: return "Thigh — left"
        case .thighRight: return "Thigh — right"
        case .gluteLeft: return "Glute — left"
        case .gluteRight: return "Glute — right"
        case .armLeft: return "Arm — left"
        case .armRight: return "Arm — right"
        }
    }

    public enum Region: String, Codable, CaseIterable, Sendable {
        case abdomen, flank, thigh, glute, arm
    }
}
