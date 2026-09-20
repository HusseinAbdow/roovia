# Roovia

> A shared-house management app for organizing roommates, household communication, shared bills, payment proof, and reminders in one place.

Roovia is a Flutter application backed by Firebase. It helps people living together discover or create a house, manage membership, communicate in real time, create and settle shared expenses, submit payment proof, and receive timely notifications when bills are due or overdue.

The project is designed around a simple principle: shared living should be transparent, predictable, and easier to coordinate.

## Features

### House management

- Create a shared house with location, invite code, capacity, description, and estimated monthly costs.
- Discover houses by name and Bartın district.
- Join with an invite code or submit a join request for owner approval.
- Manage house membership with leader/member permissions.
- View a house dashboard with membership and cost summaries.

### Shared expenses

- Create bills for selected house members.
- Calculate each participant's share.
- Track participant payment states: `pending`, `paid`, and `confirmed`.
- Submit payment proof as PDF attachments.
- Let the house leader approve or reject payment proof.
- Keep a bill-level settlement state and participant-level audit trail.

### Communication and notifications

- Real-time chat scoped to each house.
- Unread chat tracking using per-user house metadata.
- In-app notifications for bills, payment proof events, settlement updates, and chat messages.
- Firebase Cloud Messaging push notifications for background delivery.
- Notification taps route directly to the relevant expense or house chat.
- Automated reminders three days before a bill is due, one day before it is due, and after it becomes overdue.

### Profiles and media

- Firebase Authentication sign-up, sign-in, and sign-out.
- Username validation and uniqueness checks.
- Profile editing with avatar cropping, compression, upload, replacement, and cleanup.
- Cached remote images for a smoother UI.

## Architecture

Roovia uses a layered Flutter + Firebase architecture:

```text
Flutter UI
  ├── screens/       User-facing routes and flows
  ├── services/      Business logic and Firebase access
  ├── models/        Typed Firestore document models
  └── constants/     Shared application constants

Firebase backend
  ├── Authentication User identity and sessions
  ├── Firestore      Houses, chat, expenses, participants, and notifications
  ├── Storage        Avatars and payment-proof files
  ├── Cloud Messaging Push delivery
  └── Functions       Notification fan-out and scheduled reminders
```

The client writes canonical notification documents to Firestore. Cloud Functions observe those documents and relay them through FCM, keeping notification history separate from push-delivery concerns.

## Repository layout

```text
lib/
  main.dart                         App bootstrap, Firebase initialization, and routing
  firebase_options.dart             FlutterFire platform configuration
  constants/                        Shared constants, including Bartın locations
  models/                           User, house, message, expense, and proof models
  screens/                          Authentication, house, chat, expense, profile, and alert UI
  services/                         Auth, user, house, chat, expense, and FCM services

functions/
  index.js                          Firebase Cloud Functions
  package.json                      Node.js function dependencies and runtime

firestore.rules                     Firestore authorization and data validation
storage.rules                       Storage access and upload validation
firebase.json                       Firebase Functions, Firestore, and Storage configuration

docs/
  PROJECT_MASTER_CONTEXT.md          Detailed architecture, data model, and product context

test/
  widget_test.dart                  Flutter widget-test entry point

android/ ios/ linux/ macos/ web/ windows/
                                    Flutter platform targets
```

## Technology stack

- **Flutter / Dart** — cross-platform application UI; Dart SDK constraint `^3.10.7`.
- **Firebase Authentication** — user accounts and sessions.
- **Cloud Firestore** — real-time application data.
- **Firebase Storage** — avatars and payment-proof attachments.
- **Firebase Cloud Messaging** — push notifications.
- **Firebase Cloud Functions** — Node.js 20 backend automation.
- **Material 3** — application UI foundation.

Notable Flutter packages include `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `flutter_local_notifications`, `image_picker`, `image_cropper`, `file_picker`, `cached_network_image`, and `intl`.

## Data model

The primary Firestore collections are:

| Collection | Purpose |
| --- | --- |
| `users/{uid}` | Profile data, avatar metadata, and FCM token |
| `houses/{houseId}` | House identity, leader, members, invite code, and cost summary |
| `join_requests/{requestId}` | House membership request lifecycle |
| `house_chats/{houseId}/messages/{messageId}` | Real-time house chat messages |
| `house_user_meta/{metaId}` | Per-user chat last-seen metadata |
| `house_expenses/{expenseId}` | Shared bill details and bill-level state |
| `house_expenses/{expenseId}/participants/{userId}` | Individual amount owed, payment state, and proof metadata |
| `user_notifications/{uid}/notifications/{nid}` | Canonical in-app notification stream |

### Storage paths

- `users/{uid}/profile/...` — profile avatars.
- `bills/{billId}/payments/{userId}/proofs/...` — current PDF payment proofs.
- `profile_images/{uid}/...` — legacy avatar path retained for compatibility.
- `house_images/{houseId}/...` — future-facing house image storage path.

## Security model

Access is enforced in Firebase Security Rules as well as in the application services:

- Users can update only their own profile documents and avatars.
- House leaders control house updates, deletion, join-request decisions, bill creation, and payment-proof review.
- House members can access member-scoped house details and chat.
- Participants can submit and update their own payment state.
- Payment proofs are restricted to the relevant bill owner and participant.
- Current payment-proof uploads must be PDF files smaller than 12 MB.
- Profile avatars must be images smaller than 5 MB.

Review `firestore.rules` and `storage.rules` before deploying a Firebase project or changing the data model.

## Requirements

Install the following before starting development:

- Flutter SDK compatible with Dart `^3.10.7`.
- A configured Firebase project.
- Node.js 20 for Firebase Cloud Functions.
- Firebase CLI, if deploying Functions or Security Rules.
- Android Studio and/or Xcode for mobile builds.

## Local development

### 1. Clone the repository

```bash
git clone https://github.com/HusseinAbdow/roovia.git
cd roovia
```

### 2. Install Flutter dependencies

```bash
flutter pub get
```

### 3. Configure Firebase

The FlutterFire configuration is represented by `lib/firebase_options.dart`. For a new Firebase project, regenerate or replace the platform configuration using the FlutterFire CLI, then enable the services used by the app:

- Authentication
- Cloud Firestore
- Cloud Storage
- Cloud Messaging

Also verify the Android, iOS, web, and desktop platform configuration before running a target that is not already configured.

### 4. Install Functions dependencies

```bash
cd functions
npm ci
cd ..
```

### 5. Run the Flutter app

```bash
flutter run
```

To select a device or target explicitly:

```bash
flutter devices
flutter run -d <device-id>
```

The app starts at the login screen. Firebase initialization occurs in `lib/main.dart` before the Flutter application is launched.

## Testing and analysis

Run the available Flutter checks with:

```bash
flutter analyze
flutter test
```

The repository currently contains a starter widget test in `test/widget_test.dart`. As product flows evolve, expand the test suite around authentication, house membership, bill state transitions, proof review, and notification routing.

## Deploying Firebase resources

Authenticate with the Firebase CLI and select the intended project before deploying:

```bash
firebase login
firebase use <firebase-project-id>
firebase deploy --only firestore:rules,storage,functions
```

Deploy only the Functions backend when appropriate:

```bash
firebase deploy --only functions
```

The scheduled `processBillReminders` function runs hourly in UTC. Confirm that the selected Firebase project and billing configuration support the deployed Functions workload before enabling it in production.

## Cloud Functions

`functions/index.js` currently provides:

- `sendPushOnHouseChatMessage` — fans out new house chat messages to other members.
- `sendPushOnUserNotification` — relays canonical Firestore notifications through FCM.
- `processBillReminders` — scans upcoming and overdue bills and creates reminder notifications.

Notification document IDs are deterministic for the main flows, which helps prevent duplicate notifications during retries.

## Current status and known limitations

Roovia has a working foundation for shared-house operations, but it is still under active development. The following areas are intentionally incomplete or need follow-up:

- Financial analytics are not yet a complete dashboard.
- The activity/feed experience is currently a future-facing shell.
- Some members and notifications entry points are auxiliary or placeholder surfaces.
- House deletion does not yet cascade through every dependent Firestore collection and Storage object.
- Some legacy Firestore field names are accepted during reads for backward compatibility.
- Desktop and web Firebase configuration may require additional setup.
- Chat currently has no message editing, deletion, attachments, typing indicators, pagination, or read receipts beyond last-seen tracking.

For the most detailed implementation notes, data-model documentation, and technical-debt inventory, see [`docs/PROJECT_MASTER_CONTEXT.md`](docs/PROJECT_MASTER_CONTEXT.md).

## Contributing

1. Create a feature branch.
2. Keep Firebase access and business rules in the service layer instead of embedding them in screens.
3. Update Firestore or Storage rules whenever a data-access boundary changes.
4. Add or update tests for changed flows.
5. Run `flutter analyze` and `flutter test` before opening a pull request.

## License

No license file is currently included. Until a license is added, all rights are reserved by the repository owner.
