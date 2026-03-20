import HealthKit

enum HealthKitManager {
    private static let store = HealthKitExporterApp.healthStore

    static func fetchAll(days: Int) async throws -> HealthData {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now)!

        async let hr = fetchQuantitySamples(.heartRate, from: start, unit: HKUnit.count().unitDivided(by: .minute()))
        async let restingHr = fetchQuantitySamples(.restingHeartRate, from: start, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = fetchQuantitySamples(.heartRateVariabilitySDNN, from: start, unit: .secondUnit(with: .milli))
        async let spo2 = fetchQuantitySamples(.oxygenSaturation, from: start, unit: .percent())
        async let sleepData = fetchSleep(from: start)
        async let energy = fetchDailySum(.activeEnergyBurned, from: start, unit: .kilocalorie())
        async let exercise = fetchDailySum(.appleExerciseTime, from: start, unit: .minute())
        async let summaries = fetchActivitySummaries(from: start)
        async let workoutData = fetchWorkouts(from: start)

        var data = HealthData()
        data.heartRateSamples = try await hr
        data.restingHeartRateSamples = try await restingHr
        data.hrvSamples = try await hrv
        data.bloodOxygenSamples = try await spo2
        data.sleepSessions = try await sleepData
        data.activeEnergyDaily = try await energy
        data.exerciseTimeDaily = try await exercise
        data.activitySummaries = try await summaries
        data.workouts = try await workoutData
        return data
    }

    // MARK: - Quantity Samples (heart rate, resting HR, HRV, SpO2)

    private static func fetchQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        from startDate: Date,
        unit: HKUnit
    ) async throws -> [DateValue] {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample] ?? []).map { sample in
                    DateValue(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    // MARK: - Daily Sums (active energy, exercise time)

    private static func fetchDailySum(
        _ identifier: HKQuantityTypeIdentifier,
        from startDate: Date,
        unit: HKUnit
    ) async throws -> [DateValue] {
        let type = HKQuantityType(identifier)
        let interval = DateComponents(day: 1)
        let anchorDate = Calendar.current.startOfDay(for: startDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var values: [DateValue] = []
                results?.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        values.append(DateValue(date: statistics.startDate, value: sum.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    private static func fetchSleep(from startDate: Date) async throws -> [SleepSession] {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }

        // Group by wake-up date (use endDate's calendar day)
        var byDate: [String: [HKCategorySample]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        for sample in samples {
            let key = dateFormatter.string(from: sample.endDate)
            byDate[key, default: []].append(sample)
        }

        var sessions: [SleepSession] = []
        for (_, daySamples) in byDate {
            var deepMins = 0.0
            var coreMins = 0.0
            var remMins = 0.0
            var inBedMins = 0.0
            var asleepMins = 0.0
            var earliestStart: Date?
            var latestEnd: Date?

            for sample in daySamples {
                let mins = sample.endDate.timeIntervalSince(sample.startDate) / 60.0

                if earliestStart == nil || sample.startDate < earliestStart! {
                    earliestStart = sample.startDate
                }
                if latestEnd == nil || sample.endDate > latestEnd! {
                    latestEnd = sample.endDate
                }

                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                switch value {
                case .inBed:
                    inBedMins += mins
                case .asleepCore:
                    coreMins += mins
                    asleepMins += mins
                case .asleepDeep:
                    deepMins += mins
                    asleepMins += mins
                case .asleepREM:
                    remMins += mins
                    asleepMins += mins
                case .asleepUnspecified:
                    asleepMins += mins
                default:
                    break
                }
            }

            // If we only have inBed (no stage breakdown), use inBed as total
            let totalHours = asleepMins > 0 ? asleepMins / 60.0 : inBedMins / 60.0
            let totalInBedHours = inBedMins > 0 ? inBedMins / 60.0 : totalHours
            guard totalHours > 0 else { continue }

            let wakeDate = latestEnd ?? Date()

            sessions.append(SleepSession(
                date: wakeDate,
                totalHours: totalHours,
                inBedHours: totalInBedHours,
                asleepHours: asleepMins > 0 ? asleepMins / 60.0 : totalHours,
                deepMinutes: deepMins > 0 ? deepMins : nil,
                coreMinutes: coreMins > 0 ? coreMins : nil,
                remMinutes: remMins > 0 ? remMins : nil,
                bedTime: earliestStart,
                wakeTime: latestEnd
            ))
        }

        return sessions
    }

    // MARK: - Activity Summaries

    private static func fetchActivitySummaries(from startDate: Date) async throws -> [ActivitySummary] {
        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endComps = calendar.dateComponents([.year, .month, .day], from: Date())

        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComps,
            end: endComps
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let results = (summaries ?? []).compactMap { summary -> ActivitySummary? in
                    let comps = summary.dateComponents(for: calendar)
                    guard let date = calendar.date(from: comps) else { return nil }

                    return ActivitySummary(
                        date: date,
                        moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                        exerciseGoal: summary.exerciseTimeGoal.doubleValue(for: .minute()),
                        standHoursGoal: Int(summary.standHoursGoal.doubleValue(for: .count())),
                        standHours: Int(summary.appleStandHours.doubleValue(for: .count()))
                    )
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    private static func fetchWorkouts(from startDate: Date) async throws -> [WorkoutData] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workoutSamples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        var workoutResults: [WorkoutData] = []
        for workout in workoutSamples {
            // Fetch heart rate samples during the workout
            let hrStats = try await fetchWorkoutHeartRate(workout: workout)

            let name = workout.workoutActivityType.displayName
            let durationMinutes = workout.duration / 60.0
            let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            let distanceKm = workout.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }

            workoutResults.append(WorkoutData(
                name: name,
                start: workout.startDate,
                end: workout.endDate,
                durationMinutes: (durationMinutes * 10).rounded() / 10,
                calories: calories,
                distanceKm: distanceKm.map { ($0 * 10).rounded() / 10 },
                avgHeartRate: hrStats.avg,
                maxHeartRate: hrStats.max
            ))
        }

        return workoutResults
    }

    private static func fetchWorkoutHeartRate(workout: HKWorkout) async throws -> (avg: Int?, max: Int?) {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: results as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return (nil, nil) }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
        let avg = Int((values.reduce(0, +) / Double(values.count)).rounded())
        let max = Int(values.max()!.rounded())

        return (avg, max)
    }
}

// MARK: - Workout Activity Type Names

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        case .pilates: return "Pilates"
        case .kickboxing: return "Kickboxing"
        case .boxing: return "Boxing"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        default: return "Other"
        }
    }
}
