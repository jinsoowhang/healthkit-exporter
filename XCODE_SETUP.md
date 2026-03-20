# Xcode Project Setup

Since this repo contains Swift source files without an Xcode project, you'll need to create one. This takes about 2 minutes.

## Steps

1. **Open Xcode** → File → New → Project

2. **Choose template:** iOS → App → Next

3. **Configure:**
   - Product Name: `HealthKitExporter`
   - Organization Identifier: `com.yourname` (anything works for personal use)
   - Interface: SwiftUI
   - Language: Swift
   - Uncheck "Include Tests"
   - Save to a temporary location

4. **Replace source files:**
   - In Xcode's file navigator, delete the auto-generated `ContentView.swift` and `HealthKitExporterApp.swift`
   - Drag all `.swift` files from this repo's `HealthKitExporter/` folder into the Xcode project
   - Make sure "Copy items if needed" is checked

5. **Add HealthKit capability:**
   - Select the project in the navigator → select the target
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability" → search for "HealthKit" → add it

6. **Set deployment target:**
   - In the same target settings, set "Minimum Deployments" → iOS 17.0

7. **Set your development team:**
   - In "Signing & Capabilities", select your personal team under "Team"
   - If you don't have one, sign in with your Apple ID in Xcode → Settings → Accounts

8. **Add HealthKit usage description:**
   - Select the project → select the target → "Info" tab
   - Add a new key: `Privacy - Health Share Usage Description`
   - Value: `This app reads your health data to export it to your personal health dashboard.`

9. **Build and run:**
   - Connect your iPhone via USB
   - Select your iPhone as the run destination
   - Press Cmd+R to build and run
   - On your iPhone, you may need to trust the developer certificate: Settings → General → VPN & Device Management
