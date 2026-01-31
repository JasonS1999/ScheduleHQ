# ScheduleHQ iOS

A native iOS app for employees to view their schedules and manage time off requests.

## Features

- **Schedule View**: View weekly schedules with shift details, times, and notes
- **Time Off Management**: Request PTO, vacation, and day off with auto-approval support
- **Offline Support**: Requests are queued and synced when back online
- **Push Notifications**: Get notified when schedules are published or requests are approved/denied
- **PTO Tracking**: View trimester-based PTO balances with carryover calculations

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

### 1. Open in Xcode

Open the project folder in Xcode or create a new Xcode project and add the existing files:

```bash
open ScheduleHQ_IOS
```

### 2. Add Firebase SDK

Add Firebase packages via Swift Package Manager:

1. In Xcode, go to **File > Add Package Dependencies**
2. Enter: `https://github.com/firebase/firebase-ios-sdk.git`
3. Select version **11.0.0** or later
4. Add these products to your target:
   - FirebaseAuth
   - FirebaseFirestore
   - FirebaseMessaging

### 3. Configure Firebase

The `GoogleService-Info.plist` file should already be in the project root. Make sure it's added to your Xcode target:

1. Drag `GoogleService-Info.plist` into your Xcode project navigator
2. Ensure "Copy items if needed" is checked
3. Ensure your app target is selected

### 4. Enable Push Notifications

1. Select your target in Xcode
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **Push Notifications**
5. Add **Background Modes** and check:
   - Remote notifications

### 5. Configure APNs in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Project Settings > Cloud Messaging**
4. Upload your APNs authentication key or certificates

## Project Structure

```
ScheduleHQ/
├── App/
│   ├── ScheduleHQApp.swift      # App entry point, Firebase config
│   └── AppDelegate.swift        # Push notification handling
├── Models/
│   ├── AppUser.swift            # Firebase Auth user
│   ├── Employee.swift           # Employee profile
│   ├── Shift.swift              # Work shift
│   ├── TimeOffEntry.swift       # Approved time off
│   ├── TimeOffRequest.swift     # Time off request
│   └── TrimesterSummary.swift   # PTO calculations
├── Services/
│   ├── AlertManager.swift       # Centralized alerts
│   ├── AuthManager.swift        # Firebase Auth
│   ├── ScheduleManager.swift    # Schedule data
│   ├── TimeOffManager.swift     # Time off data
│   └── OfflineQueueManager.swift# Offline request queue
├── Utilities/
│   ├── NetworkMonitor.swift     # Connectivity detection
│   └── DateExtensions.swift     # Date helpers
└── Views/
    ├── Auth/
    │   └── LoginView.swift
    ├── Schedule/
    │   └── ScheduleView.swift
    ├── TimeOff/
    │   ├── TimeOffView.swift
    │   └── TimeOffRequestSheet.swift
    ├── Profile/
    │   └── ProfileView.swift
    ├── Components/
    │   ├── CommonComponents.swift
    │   ├── ShiftCard.swift
    │   └── TimeOffRequestCard.swift
    └── MainTabView.swift
```

## Architecture

The app follows a clean MVVM-style architecture:

- **Models**: Codable structs with Firestore support
- **Services**: @Observable managers for data and state
- **Views**: SwiftUI views consuming services via singletons
- **Utilities**: Shared helpers and extensions

### Data Flow

```
Firestore ← → Services (Managers) ← → Views
                  ↓
            AlertManager (errors)
                  ↓
            NetworkMonitor (offline detection)
                  ↓
            OfflineQueueManager (pending sync)
```

## Firebase Collections

The app reads from these Firestore collections:

- `/users/{uid}` - User account linking
- `/managers/{managerUid}/employees/{id}` - Employee profiles
- `/managers/{managerUid}/shifts/{id}` - Work shifts
- `/managers/{managerUid}/timeOff/{id}` - Time off entries
- `/managers/{managerUid}/timeOffRequests/{id}` - Time off requests

## Offline Support

- Firestore has built-in offline persistence (100MB cache)
- Time off requests are queued locally when offline
- Automatic sync when connectivity is restored
- Visual indicator (orange banner) when offline
- Badge on Time Off tab shows pending sync count

## License

Proprietary - ScheduleHQ
