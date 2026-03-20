import Foundation

// MARK: - Payload types matching IngestPayload in ingest-parser.ts

struct IngestPayload: Encodable {
    let data: PayloadData
}

struct PayloadData: Encodable {
    let metrics: [MetricPayload]
    let workouts: [WorkoutPayload]
}

struct MetricPayload: Encodable {
    let name: String
    let units: String
    let data: [MetricSample]
}

struct MetricSample: Encodable {
    let date: String
    let qty: Double
    var source: String?
    var asleep: Double?
    var inBed: Double?
    var sleepStart: String?
    var sleepEnd: String?
    var deepMinutes: Double?
    var coreMinutes: Double?
    var remMinutes: Double?
}

struct WorkoutPayload: Encodable {
    let name: String
    let start: String
    let end: String
    let duration: Double // minutes
    var totalEnergyBurned: Double?
    var totalDistance: Double? // km
    var avgHeartRate: Int?
    var maxHeartRate: Int?
}

// MARK: - Intermediate types from HealthKitManager

struct HealthData {
    var heartRateSamples: [DateValue] = []
    var restingHeartRateSamples: [DateValue] = []
    var hrvSamples: [DateValue] = []
    var bloodOxygenSamples: [DateValue] = []
    var sleepSessions: [SleepSession] = []
    var activeEnergyDaily: [DateValue] = []
    var exerciseTimeDaily: [DateValue] = []
    var activitySummaries: [ActivitySummary] = []
    var workouts: [WorkoutData] = []
}

struct DateValue {
    let date: Date
    let value: Double
}

struct SleepSession {
    let date: Date // wake-up date
    let totalHours: Double
    let inBedHours: Double
    let asleepHours: Double
    let deepMinutes: Double?
    let coreMinutes: Double?
    let remMinutes: Double?
    let bedTime: Date?
    let wakeTime: Date?
}

struct ActivitySummary {
    let date: Date
    let moveGoal: Double?
    let exerciseGoal: Double?
    let standHoursGoal: Int?
    let standHours: Int?
}

struct WorkoutData {
    let name: String
    let start: Date
    let end: Date
    let durationMinutes: Double
    let calories: Double?
    let distanceKm: Double?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
}

// MARK: - API Client

enum APIClientError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

struct IngestResponse: Decodable {
    let success: Bool?
    let error: String?
    let records: RecordCounts?
}

struct RecordCounts: Decodable {
    let workouts: Int?
    let heartRate: Int?
    let hrv: Int?
    let sleep: Int?
    let bloodOxygen: Int?
    let activity: Int?
}

enum APIClient {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let maxPayloadBytes = 3_000_000 // 3 MB, under Vercel's 4.5 MB limit

    static func sync(healthData: HealthData, serverURL: String, apiKey: String) async throws -> IngestResponse {
        let payload = buildPayload(from: healthData)
        let jsonData = try JSONEncoder().encode(payload)

        // If payload is small enough, send in one request
        if jsonData.count <= maxPayloadBytes {
            return try await sendPayload(jsonData, serverURL: serverURL, apiKey: apiKey)
        }

        // Otherwise, chunk by day
        return try await sendChunked(healthData: healthData, serverURL: serverURL, apiKey: apiKey)
    }

    private static func sendPayload(_ jsonData: Data, serverURL: String, apiKey: String) async throws -> IngestResponse {
        guard let url = URL(string: "\(serverURL)/api/ingest") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.httpError(statusCode: 0, body: "Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw APIClientError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(IngestResponse.self, from: data)
    }

    private static func sendChunked(healthData: HealthData, serverURL: String, apiKey: String) async throws -> IngestResponse {
        // Collect all unique dates
        var allDates = Set<String>()
        for s in healthData.heartRateSamples { allDates.insert(dayString(s.date)) }
        for s in healthData.restingHeartRateSamples { allDates.insert(dayString(s.date)) }
        for s in healthData.hrvSamples { allDates.insert(dayString(s.date)) }
        for s in healthData.bloodOxygenSamples { allDates.insert(dayString(s.date)) }
        for s in healthData.sleepSessions { allDates.insert(dayString(s.date)) }
        for s in healthData.activeEnergyDaily { allDates.insert(dayString(s.date)) }
        for s in healthData.exerciseTimeDaily { allDates.insert(dayString(s.date)) }
        for s in healthData.activitySummaries { allDates.insert(dayString(s.date)) }
        for w in healthData.workouts { allDates.insert(dayString(w.start)) }

        var lastResponse = IngestResponse(success: true, error: nil, records: nil)

        for date in allDates.sorted() {
            let dayData = filterByDay(healthData: healthData, day: date)
            let payload = buildPayload(from: dayData)
            let jsonData = try JSONEncoder().encode(payload)
            lastResponse = try await sendPayload(jsonData, serverURL: serverURL, apiKey: apiKey)
        }

        return lastResponse
    }

    private static func filterByDay(healthData: HealthData, day: String) -> HealthData {
        var filtered = HealthData()
        filtered.heartRateSamples = healthData.heartRateSamples.filter { dayString($0.date) == day }
        filtered.restingHeartRateSamples = healthData.restingHeartRateSamples.filter { dayString($0.date) == day }
        filtered.hrvSamples = healthData.hrvSamples.filter { dayString($0.date) == day }
        filtered.bloodOxygenSamples = healthData.bloodOxygenSamples.filter { dayString($0.date) == day }
        filtered.sleepSessions = healthData.sleepSessions.filter { dayString($0.date) == day }
        filtered.activeEnergyDaily = healthData.activeEnergyDaily.filter { dayString($0.date) == day }
        filtered.exerciseTimeDaily = healthData.exerciseTimeDaily.filter { dayString($0.date) == day }
        filtered.activitySummaries = healthData.activitySummaries.filter { dayString($0.date) == day }
        filtered.workouts = healthData.workouts.filter { dayString($0.start) == day }
        return filtered
    }

    // MARK: - Payload Builder

    static func buildPayload(from data: HealthData) -> IngestPayload {
        var metrics: [MetricPayload] = []

        // Heart rate
        if !data.heartRateSamples.isEmpty {
            metrics.append(MetricPayload(
                name: "heart_rate",
                units: "bpm",
                data: data.heartRateSamples.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // Resting heart rate
        if !data.restingHeartRateSamples.isEmpty {
            metrics.append(MetricPayload(
                name: "resting_heart_rate",
                units: "bpm",
                data: data.restingHeartRateSamples.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // HRV
        if !data.hrvSamples.isEmpty {
            metrics.append(MetricPayload(
                name: "heart_rate_variability",
                units: "ms",
                data: data.hrvSamples.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // Sleep
        if !data.sleepSessions.isEmpty {
            metrics.append(MetricPayload(
                name: "sleep_analysis",
                units: "hr",
                data: data.sleepSessions.map { session in
                    MetricSample(
                        date: iso8601.string(from: session.date),
                        qty: session.totalHours,
                        asleep: session.asleepHours,
                        inBed: session.inBedHours,
                        sleepStart: session.bedTime.map { iso8601.string(from: $0) },
                        sleepEnd: session.wakeTime.map { iso8601.string(from: $0) },
                        deepMinutes: session.deepMinutes,
                        coreMinutes: session.coreMinutes,
                        remMinutes: session.remMinutes
                    )
                }
            ))
        }

        // Blood oxygen
        if !data.bloodOxygenSamples.isEmpty {
            metrics.append(MetricPayload(
                name: "blood_oxygen",
                units: "%",
                data: data.bloodOxygenSamples.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // Active energy (daily sums)
        if !data.activeEnergyDaily.isEmpty {
            metrics.append(MetricPayload(
                name: "active_energy",
                units: "kcal",
                data: data.activeEnergyDaily.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // Exercise time (daily sums)
        if !data.exerciseTimeDaily.isEmpty {
            metrics.append(MetricPayload(
                name: "apple_exercise_time",
                units: "min",
                data: data.exerciseTimeDaily.map { MetricSample(date: iso8601.string(from: $0.date), qty: $0.value) }
            ))
        }

        // Stand hours + goals from activity summaries
        if !data.activitySummaries.isEmpty {
            let standData = data.activitySummaries.compactMap { summary -> MetricSample? in
                guard let hours = summary.standHours else { return nil }
                return MetricSample(date: dayString(summary.date) + "T00:00:00Z", qty: Double(hours))
            }
            if !standData.isEmpty {
                metrics.append(MetricPayload(name: "apple_stand_hour", units: "hr", data: standData))
            }

            let moveGoalData = data.activitySummaries.compactMap { summary -> MetricSample? in
                guard let goal = summary.moveGoal else { return nil }
                return MetricSample(date: dayString(summary.date) + "T00:00:00Z", qty: goal)
            }
            if !moveGoalData.isEmpty {
                metrics.append(MetricPayload(name: "apple_move_goal", units: "kcal", data: moveGoalData))
            }

            let exerciseGoalData = data.activitySummaries.compactMap { summary -> MetricSample? in
                guard let goal = summary.exerciseGoal else { return nil }
                return MetricSample(date: dayString(summary.date) + "T00:00:00Z", qty: goal)
            }
            if !exerciseGoalData.isEmpty {
                metrics.append(MetricPayload(name: "apple_exercise_goal", units: "min", data: exerciseGoalData))
            }

            let standGoalData = data.activitySummaries.compactMap { summary -> MetricSample? in
                guard let goal = summary.standHoursGoal else { return nil }
                return MetricSample(date: dayString(summary.date) + "T00:00:00Z", qty: Double(goal))
            }
            if !standGoalData.isEmpty {
                metrics.append(MetricPayload(name: "apple_stand_goal", units: "hr", data: standGoalData))
            }
        }

        // Workouts
        let workoutPayloads = data.workouts.map { w in
            WorkoutPayload(
                name: w.name,
                start: iso8601.string(from: w.start),
                end: iso8601.string(from: w.end),
                duration: w.durationMinutes,
                totalEnergyBurned: w.calories,
                totalDistance: w.distanceKm,
                avgHeartRate: w.avgHeartRate,
                maxHeartRate: w.maxHeartRate
            )
        }

        return IngestPayload(data: PayloadData(metrics: metrics, workouts: workoutPayloads))
    }

    // MARK: - Helpers

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
