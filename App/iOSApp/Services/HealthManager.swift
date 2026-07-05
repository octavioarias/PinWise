import Foundation
import HealthKit

/// Reads the health metrics most relevant when tracking peptides/doses — body weight,
/// resting heart rate, and HRV. Oura, Whoop, etc. write into Apple Health, so PinWise picks
/// them up here without per-vendor SDKs. Read-only.
@Observable
@MainActor
final class HealthManager {
    static let shared = HealthManager()

    private let store = HKHealthStore()
    private static let connectedKey = "healthConnected"

    /// Whether the user has connected Apple Health. Persisted, so it survives app close/refresh
    /// (HealthKit deliberately won't reveal read-permission status, so we remember the choice).
    private(set) var authorized: Bool
    private(set) var latestWeightKg: Double?
    private(set) var restingHeartRate: Double?      // bpm
    private(set) var hrvMilliseconds: Double?       // SDNN

    private init() {
        authorized = UserDefaults.standard.bool(forKey: Self.connectedKey)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for id in [HKQuantityTypeIdentifier.bodyMass, .restingHeartRate, .heartRateVariabilitySDNN, .heartRate, .stepCount] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            await refresh()
        } catch {
            // Keep any prior connected state — don't force a re-prompt on a transient error.
        }
    }

    /// Called on launch: if the user already connected, silently refresh the metrics.
    func refreshIfConnected() async {
        if authorized { await refresh() }
    }

    /// Lets the user explicitly disconnect (from Settings) if they want to stop reading Health.
    func disconnect() {
        authorized = false
        UserDefaults.standard.set(false, forKey: Self.connectedKey)
        latestWeightKg = nil; restingHeartRate = nil; hrvMilliseconds = nil
    }

    func refresh() async {
        latestWeightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        restingHeartRate = await latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        hrvMilliseconds = await latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    /// Most recent sample value for a quantity type, or nil.
    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
