import Foundation
import HealthKit
import SwiftData

/// Reads the health metrics most relevant when tracking peptides/doses — body weight,
/// resting heart rate, and HRV. Oura, Whoop, etc. write into Apple Health, so PinWise picks
/// them up here without per-vendor SDKs. Read-only.
@Observable
@MainActor
final class HealthManager {
    static let shared = HealthManager()

    private let store = HKHealthStore()
    private static let connectedKey = "healthConnected"

    /// Set by the app at launch so `refresh()` can persist a daily on-device snapshot (history for
    /// CSV export + trends). Plain reference, not observed. Nil = don't persist (just hold live values).
    var modelContext: ModelContext?

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
        // Request ONLY the metrics we actually read + display (Apple guideline 5.1.3 — request the
        // minimum). Oura/Whoop/Fitness/Garmin write these into Apple Health. Add more here only
        // when refresh() + the UI actually consume them.
        for id in [HKQuantityTypeIdentifier.bodyMass, .restingHeartRate, .heartRateVariabilitySDNN, .stepCount] {
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
        sleepHoursLastNight = nil; stepsToday = nil
    }

    func refresh() async {
        latestWeightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        restingHeartRate = await latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        hrvMilliseconds = await latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        stepsToday = await sumToday(.stepCount, unit: .count())
        sleepHoursLastNight = await sleepHours()
        persistSnapshot()
    }

    /// Upsert TODAY's on-device snapshot from the freshly-read values — one row per calendar day, so
    /// history builds up without duplicates. On-device only (never uploaded); the AI sees these
    /// values only if the user opted into sharing Health with Natt. Best-effort: silently no-ops if
    /// no store is wired or nothing was read.
    private func persistSnapshot() {
        guard let context = modelContext else { return }
        let snapshot = HealthSnapshot(
            weightKg: latestWeightKg, restingHeartRate: restingHeartRate,
            hrvMilliseconds: hrvMilliseconds, sleepHoursLastNight: sleepHoursLastNight,
            stepsToday: stepsToday)
        guard snapshot.hasAnyMetric else { return }

        let dayStart = Calendar.current.startOfDay(for: Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.timestamp >= dayStart && $0.timestamp < dayEnd })
        if let existing = try? context.fetch(descriptor).first {
            existing.timestamp = Date()
            existing.weightKg = latestWeightKg
            existing.restingHeartRate = restingHeartRate
            existing.hrvMilliseconds = hrvMilliseconds
            existing.sleepHoursLastNight = sleepHoursLastNight
            existing.stepsToday = stepsToday
        } else {
            context.insert(snapshot)
        }
        try? context.save()
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
