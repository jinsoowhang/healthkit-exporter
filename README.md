# HealthKit Exporter

A free, open-source iOS app that exports Apple Watch health data to your self-hosted [Apple Watch Health Dashboard](https://github.com/jinsoowhang/apple-watch). Replaces paid alternatives like Health Auto Export.

Your data goes directly from your iPhone to your own server — no third parties, no analytics, no data collection.

## Supported Metrics

| Metric | Data |
|--------|------|
| Heart Rate | Resting, average, min, max (daily) |
| HRV | Heart rate variability (daily) |
| Sleep | Total, deep, core, REM, awake time + bed/wake times |
| Blood Oxygen | SpO2 readings |
| Activity Rings | Move calories, exercise minutes, stand hours + goals |
| Workouts | Duration, calories, distance, heart rate per session |

## Prerequisites

- iPhone with Apple Watch (paired)
- Mac with [Xcode](https://developer.apple.com/xcode/) 15+
- Free Apple Developer account (for sideloading)
- A deployed [Apple Watch Health Dashboard](https://github.com/jinsoowhang/apple-watch)

## Setup

1. Clone this repo:
   ```bash
   git clone https://github.com/jinsoowhang/healthkit-exporter.git
   ```

2. Open in Xcode — see [XCODE_SETUP.md](XCODE_SETUP.md) for step-by-step instructions

3. Build and run on your iPhone (not the simulator — HealthKit requires a real device)

## Usage

1. Enter your dashboard URL (e.g., `https://your-app.vercel.app`)
2. Enter the API key you set as `INGEST_API_KEY` in your dashboard's environment variables
3. Select a date range (7, 30, or 90 days)
4. Tap **Sync Now**
5. On first sync, approve the HealthKit permissions when prompted

## Dashboard Setup

This app sends data to the [Apple Watch Health Dashboard](https://github.com/jinsoowhang/apple-watch). Follow the setup instructions in that repo to deploy your own instance.

## Privacy

- All data is sent directly from your iPhone to your own server
- No third-party services, analytics, or tracking
- No data leaves your device except to the server URL you configure
- API key is stored in the iOS Keychain (encrypted)
- Source code is fully auditable
