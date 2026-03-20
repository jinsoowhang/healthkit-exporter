import SwiftUI

struct ContentView: View {
    @State private var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var apiKey: String = KeychainHelper.load(key: "apiKey") ?? ""
    @State private var selectedRange: Int = 30
    @State private var syncState: SyncState = .idle
    @State private var hasRequestedAuth = false

    private let ranges = [7, 30, 90]

    enum SyncState: Equatable {
        case idle
        case syncing
        case success(String)
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 4) {
                    Text("HealthKit Exporter")
                        .font(.title2.bold())
                    Text("Export Apple Watch data to your dashboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Server config
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server")
                        .font(.headline)

                    TextField("https://your-dashboard.vercel.app", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onChange(of: serverURL) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "serverURL")
                        }

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            KeychainHelper.save(key: "apiKey", value: newValue)
                        }
                }
                .padding(.horizontal)

                // Date range
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date Range")
                        .font(.headline)

                    Picker("Range", selection: $selectedRange) {
                        ForEach(ranges, id: \.self) { days in
                            Text("\(days)d").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                // Sync button
                Button(action: performSync) {
                    HStack {
                        if syncState == .syncing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(syncState == .syncing ? "Syncing..." : "Sync Now")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSync ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canSync)
                .padding(.horizontal)

                // Status
                switch syncState {
                case .idle:
                    EmptyView()
                case .syncing:
                    EmptyView()
                case .success(let message):
                    StatusView(message: message, isError: false)
                case .error(let message):
                    StatusView(message: message, isError: true)
                }

                Spacer()
            }
        }
    }

    private var canSync: Bool {
        syncState != .syncing && !serverURL.isEmpty && !apiKey.isEmpty
    }

    private func performSync() {
        Task {
            syncState = .syncing

            do {
                if !hasRequestedAuth {
                    try await HealthKitExporterApp.requestAuthorization()
                    hasRequestedAuth = true
                }

                let healthData = try await HealthKitManager.fetchAll(days: selectedRange)
                let response = try await APIClient.sync(
                    healthData: healthData,
                    serverURL: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                    apiKey: apiKey
                )

                if let records = response.records {
                    let parts = [
                        records.heartRate.map { "\($0) heart rate" },
                        records.hrv.map { "\($0) HRV" },
                        records.sleep.map { "\($0) sleep" },
                        records.workouts.map { "\($0) workouts" },
                        records.bloodOxygen.map { "\($0) SpO2" },
                        records.activity.map { "\($0) activity" },
                    ].compactMap { $0 }
                    syncState = .success("Sent: \(parts.joined(separator: ", "))")
                } else {
                    syncState = .success("Sync complete")
                }
            } catch {
                syncState = .error(error.localizedDescription)
            }
        }
    }
}

struct StatusView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
