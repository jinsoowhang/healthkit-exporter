import SwiftUI
import HealthKit

@main
struct HealthKitExporterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    static let healthStore = HKHealthStore()

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleExerciseTime),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
        ]
        types.insert(HKObjectType.activitySummaryType())
        return types
    }

    static func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }
}
