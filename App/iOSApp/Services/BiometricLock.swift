import Foundation
import LocalAuthentication

/// Optional Face ID / Touch ID app lock. OFF by default — users opt in under Security & Privacy.
/// The preference lives in @AppStorage("faceIDLock"); this service does the biometric evaluation.
/// The launch/foreground gate that actually blocks the UI reads the same preference.
enum BiometricLock {
    static let prefKey = "faceIDLock"

    /// Whether the device has enrolled biometrics we can use.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// "Face ID" / "Touch ID" / "Biometrics" for labeling the toggle to match the hardware.
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrics"
        }
    }

    /// Prompt for biometric authentication. Returns true if the user passed. A fresh LAContext per
    /// call (contexts are single-use). No passcode fallback here — this is an opt-in convenience
    /// lock, not a hard security boundary (the data is already device-sandboxed).
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}
