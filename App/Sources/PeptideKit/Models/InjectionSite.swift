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
    case armLeft
    case armRight
    case gluteLeft
    case gluteRight
    case tricepLeft
    case tricepRight
    case lowerBackLeft
    case lowerBackRight

    public var id: String { rawValue }

    /// Coarse region, used for grouping and for the "rotate across regions" heuristic.
    public var region: Region {
        switch self {
        case .abdomenUpperLeft, .abdomenUpperRight, .abdomenLowerLeft, .abdomenLowerRight: return .abdomen
        case .flankLeft, .flankRight: return .flank
        case .thighLeft, .thighRight: return .thigh
        case .gluteLeft, .gluteRight: return .glute
        case .armLeft, .armRight: return .arm
        case .tricepLeft, .tricepRight: return .tricep
        case .lowerBackLeft, .lowerBackRight: return .lowerBack
        }
    }

    /// Whether the site sits on the back of the body (drives the front/back views).
    public var isBack: Bool {
        switch region {
        case .glute, .tricep, .lowerBack: return true
        default: return false
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
        case .armLeft: return "Arm — left"
        case .armRight: return "Arm — right"
        case .gluteLeft: return "Glute — left"
        case .gluteRight: return "Glute — right"
        case .tricepLeft: return "Tricep — left"
        case .tricepRight: return "Tricep — right"
        case .lowerBackLeft: return "Lower back — left (love handle)"
        case .lowerBackRight: return "Lower back — right (love handle)"
        }
    }

    /// Short label for compact chips (region is shown separately).
    public var shortName: String {
        switch self {
        case .abdomenUpperLeft: return "Upper L"
        case .abdomenUpperRight: return "Upper R"
        case .abdomenLowerLeft: return "Lower L"
        case .abdomenLowerRight: return "Lower R"
        default: return rawValue.hasSuffix("Left") ? "Left" : "Right"
        }
    }

    public enum Region: String, Codable, CaseIterable, Sendable {
        case abdomen, flank, thigh, arm, glute, tricep, lowerBack
        public var label: String {
            switch self {
            case .abdomen: return "Abdomen"
            case .flank: return "Flank (love handle)"
            case .thigh: return "Thigh"
            case .arm: return "Arm"
            case .glute: return "Glute"
            case .tricep: return "Tricep"
            case .lowerBack: return "Lower back (love handle)"
            }
        }
    }
}
