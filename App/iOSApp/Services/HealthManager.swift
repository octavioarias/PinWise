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
    private(set) var sleepHoursLastNight: Double?
    private(set) var stepsToday: Double?

    private init() {
        authorized = UserDefaults.standard.bool(forKey: Self.connectedKey)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        // Body, heart, and the activity/fitness/wearable metrics that Oura, Whoop, Apple Fitness,
        // Garmin, etc. write into Apple Health.
        for id in [HKQuantityTypeIdentifier.bodyMass, .restingHeartRate, .heartRateVariabilitySDNN,
                   .heartRate, .stepCount, .activeEnergyBurned, .appleExerciseTime, .vo2Max, .respiratoryRate] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        set.insert(HKObjectType.workoutType())
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
        stepsToday = await sumToday(.stepCount, unit: .count())
        sleepHoursLastNight = await sleepHours()
    }

    /// Cumulative sum for today (steps, active energy…).
    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Hours asleep in the last ~18 hours (sums "asleep" sleep-analysis samples).
    private func sleepHours() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let cats = (samples as? [HKCategorySample]) ?? []
                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let seconds = cats.filter { asleep.contains($0.value) }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
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
