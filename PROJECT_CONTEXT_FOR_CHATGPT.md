# Roovia Project Context

## 1) High-Level Overview

**Roovia** is a Flutter + Firebase mobile app for shared-house management.

Right now, the app focuses on a simple first version of the user journey:

1. A user creates an account.
2. The app signs the user in with Firebase Authentication.
3. The app stores or reads the user's profile from Cloud Firestore.
4. The user lands on a house dashboard.
5. If the user is not part of a house yet, they can create one.
6. The house is stored in Firestore and linked to the current user by membership.

The project already has a clean UI direction (green-themed Material 3 design) and a good base for growing into a full roommate / house-management product.

---

## 2) Tech Stack

- **Framework:** Flutter
- **Language:** Dart
- **Backend services:** Firebase
- **Authentication:** Firebase Auth
- **Database:** Cloud Firestore
- **Storage dependency included:** Firebase Storage (currently not used in app logic)
- **Platforms configured:** Android, iOS, Linux, macOS, Web, Windows

Main dependency list from `pubspec.yaml`:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_storage`
- `flutter`
- `cupertino_icons`

---

## 3) Project Folder Structure

### Important custom code folders

- `lib/`
  - `main.dart` → app entry point and theme setup
  - `firebase_options.dart` → generated Firebase configuration
  - `models/` → app data models
  - `services/` → Firebase/business logic
  - `screens/` → UI screens

- `test/`
  - `widget_test.dart` → default starter widget test (currently outdated for this app)

### Mostly generated / platform-specific folders

- `android/`
- `ios/`
- `linux/`
- `macos/`
- `windows/`
- `web/`
- `build/`

These are mostly platform boilerplate or generated build output. The main product logic currently lives in `lib/`.

---

## 4) Current App Architecture

The app uses a simple structure:

- **Models** represent Firestore data.
- **Services** handle Firebase Auth and Firestore operations.
- **Screens** handle the UI and call the services.
- **Navigation** is direct using `Navigator` and `MaterialPageRoute`.

This is a straightforward small-project architecture. It is easy to understand, but it will eventually benefit from state management if the app becomes larger.

---

## 5) App Entry Point

## File: `lib/main.dart`

### `main()`
Purpose:
- Initializes Flutter bindings.
- Initializes Firebase using `Firebase.initializeApp(...)`.
- Starts the app by calling `runApp(const MyApp())`.

Flow:
1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
3. `runApp(...)`

### `MyApp`
Type:
- `StatelessWidget`

Purpose:
- Defines the global app theme.
- Sets `LoginScreen` as the startup screen.

Key behavior:
- Uses Material 3.
- Sets a custom green color scheme.
- Configures `InputDecorationTheme` and `ElevatedButtonThemeData` for consistent rounded UI styling.

Important note:
- The app always starts on the login screen.
- There is **no auth state listener** yet, so already-signed-in users are not automatically routed to the dashboard on app launch.

---

## 6) Data Models

## File: `lib/models/user_model.dart`

### `RooviaUser`
Purpose:
- Represents an app user profile.
- Designed for Firestore storage under a `users` collection.

Fields:
- `uid` → Firebase Auth user ID
- `name` → display name / user’s full name
- `email` → email address
- `rating` → roommate rating field reserved for future use

Constructor:
- Requires `uid`, `name`, `email`
- `rating` defaults to `0.0`

### `toMap()`
Purpose:
- Converts a `RooviaUser` object into a Firestore-friendly map.

Returns:
- A map with `uid`, `name`, `email`, `rating`

### `factory RooviaUser.fromMap(Map<String, dynamic> map)`
Purpose:
- Rebuilds a `RooviaUser` from Firestore data.

Notes:
- `rating` is converted safely using `toDouble()` if present.
- `uid`, `name`, and `email` are read directly and assume valid data exists.

Potential improvement:
- Add safer null/type guards for `uid`, `name`, and `email`.

---

## File: `lib/models/house_model.dart`

### `House`
Purpose:
- Represents a shared house/group in Firestore.

Fields:
- `houseId` → document ID / unique house ID
- `name` → house name
- `leaderId` → UID of the house creator / leader
- `members` → list of member UIDs
- `createdAt` → optional timestamp of creation

Constructor:
- Requires `houseId`, `name`, `leaderId`, `members`
- `createdAt` is optional

### `factory House.fromMap(Map<String, dynamic> map)`
Purpose:
- Builds a `House` from Firestore data.

Behavior:
- Converts `members` to `List<String>`.
- Handles `createdAt` if it is a Firestore `Timestamp`.
- Also supports `DateTime` directly.
- Falls back to empty values if some fields are missing.

### `toMap()`
Purpose:
- Converts the model back into a Firestore-friendly map.

Important note:
- In the current app, house creation is done directly in the service using a raw map, so this `toMap()` is not heavily used yet.

---

## 7) Services Layer

## File: `lib/services/auth_service.dart`

This file contains the authentication and user-profile logic.

### `AuthServiceException`
Purpose:
- A custom exception class used to return user-friendly auth-related error messages.

Field:
- `message`

Method:
- `toString()` returns the message so it can be shown directly in a `SnackBar`.

### `AuthService`
Purpose:
- Wraps Firebase Authentication and Firestore user profile operations.

Private fields:
- `_auth` → `FirebaseAuth.instance`
- `_db` → `FirebaseFirestore.instance`

### `Future<RooviaUser?> signUp(String name, String email, String password)`
Purpose:
- Creates a new Firebase Auth account.
- Updates the Firebase display name.
- Creates the user profile document in Firestore.

Detailed flow:
1. Calls `createUserWithEmailAndPassword`.
2. Checks whether `credential.user` exists.
3. Updates the Firebase Auth display name.
4. Creates a `RooviaUser` object.
5. Writes that profile to `users/{uid}` in Firestore.
6. Returns the created app user.

Error handling:
- Firebase Auth errors are converted to friendly messages.
- Firestore errors trigger rollback logic.
- If Firestore profile creation fails after account creation, `_rollbackFailedSignUp(...)` tries to delete the just-created auth user.
- If the Firestore error is `permission-denied`, a specific message is shown explaining Firestore rules blocked profile setup.

This is a strong safety feature because it avoids half-created accounts.

### `Future<RooviaUser?> signIn(String email, String password)`
Purpose:
- Signs the user in.
- Loads the user profile from Firestore.
- If profile loading fails or the profile is missing, it falls back to Firebase Auth data.

Current flow:
1. Calls `signInWithEmailAndPassword`.
2. Validates that a Firebase user exists.
3. Builds a fallback `RooviaUser` using Firebase Auth info.
4. Tries to load `users/{uid}` from Firestore.
5. If the document exists, returns a merged `RooviaUser`.
6. If the document does not exist, tries to create it.
7. If Firestore read/write fails, still returns the fallback user instead of blocking login.

This was recently improved so the app no longer fails sign-in just because the Firestore profile is unavailable.

### `Future<void> signOut()`
Purpose:
- Signs out the current Firebase Auth user.

### `Future<void> _rollbackFailedSignUp(User? firebaseUser)`
Purpose:
- Internal helper used when signup partially succeeds.

Behavior:
- If a Firebase user exists, tries to delete it.
- If delete fails and the same user is still signed in, signs them out.

Why this exists:
- Prevents inconsistent state where Auth account exists but Firestore profile does not.

### `String _authErrorMessage(FirebaseAuthException exception)`
Purpose:
- Converts Firebase Auth error codes into user-friendly messages.

Handled cases include:
- email already in use
- invalid email
- weak password
- user not found
- wrong password
- invalid credentials
- network failure
- too many requests

### `String _unexpectedErrorMessage(Object error)`
Purpose:
- Provides a fallback readable message for non-Firebase errors.

### `RooviaUser _buildAuthBackedUser(User firebaseUser, String email)`
Purpose:
- Builds a basic app user from Firebase Auth data.

Used when:
- Firestore user profile does not exist
- Firestore user profile cannot be read
- Firestore data is incomplete

---

## File: `lib/services/house_service.dart`

This file contains house-related Firestore logic.

### `HouseService`
Purpose:
- Handles loading and creating houses for the authenticated user.

Private fields:
- `_auth` → `FirebaseAuth.instance`
- `_db` → `FirebaseFirestore.instance`

### `User get _currentUser`
Purpose:
- Internal helper to get the current authenticated user.

Behavior:
- Returns `FirebaseAuth.instance.currentUser`
- Throws `StateError` if there is no authenticated user

Why this matters:
- The house logic assumes a signed-in user exists.
- If this app later adds session restoration or deep linking, this assumption should be handled more carefully in UI routing.

### `Stream<House?> getCurrentUserHouse()`
Purpose:
- Watches Firestore for the house that includes the current user as a member.

Detailed behavior:
1. Reads the current user UID.
2. Queries `houses` where `members` array contains that UID.
3. Limits the query to one result.
4. Returns a stream.
5. Maps the first matching Firestore document into a `House` model.
6. Returns `null` if no house is found.

This powers the dashboard screen in real time.

Important limitation:
- It assumes a user belongs to only one house.
- If multi-house support is added later, this API and UI will need redesign.

### `Future<House> createHouse(String name)`
Purpose:
- Creates a new house in Firestore with the current user as leader and first member.

Detailed flow:
1. Trims the name.
2. Throws `ArgumentError` if the name is empty.
3. Gets the current user UID.
4. Creates a new Firestore document reference.
5. Builds a data map with:
   - `houseId`
   - `name`
   - `leaderId`
   - `members: [uid]`
   - `createdAt: FieldValue.serverTimestamp()`
6. Saves the document.
7. Reads it back.
8. Returns a `House` model.

Potential improvement:
- Prevent creating multiple houses for the same user.
- Add invite/join flow instead of only create flow.

---

## 8) Screens / UI Layer

## File: `lib/screens/login_screen.dart`

### `LoginScreen`
Type:
- `StatefulWidget`

Purpose:
- Sign-in screen for existing users.

### `_LoginScreenState`
Purpose:
- Holds form state and login logic.

State fields:
- `_auth` → `AuthService`
- `emailController`
- `passwordController`
- `_loading`

Theme constants:
- `_darkGreen`
- `_lightGreen`
- `_surfaceGreen`

### `dispose()`
Purpose:
- Disposes text controllers to avoid memory leaks.

### `_signIn()`
Purpose:
- Validates input.
- Calls the auth service.
- Navigates to the dashboard after a successful sign-in.

Flow:
1. Checks email and password are not empty.
2. Shows a `SnackBar` if invalid.
3. Sets loading state.
4. Calls `_auth.signIn(...)`.
5. If user is returned and widget is still mounted, navigates to `HouseDashboardScreen`.
6. On error, shows the exception text in a `SnackBar`.
7. Resets loading.

### `_openSignUp()`
Purpose:
- Pushes the signup screen.

### `build(BuildContext context)`
Purpose:
- Renders the login UI.

Main UI elements:
- Gradient background
- Welcome headline
- Email field
- Password field
- Placeholder “Forgot password?” text (not functional yet)
- Sign-in button / loading spinner
- Security info card
- Link to create account

### `_buildField(...)`
Purpose:
- Shared helper for styled text fields.

---

## File: `lib/screens/sign_up_screen.dart`

### `SignUpScreen`
Type:
- `StatefulWidget`

Purpose:
- Account creation screen.

### `_SignUpScreenState`
Purpose:
- Holds signup form state and validation logic.

State fields:
- `_auth` → `AuthService`
- `nameController`
- `emailController`
- `passwordController`
- `confirmPasswordController`
- `_loading`

### `dispose()`
Purpose:
- Disposes text controllers.

### `Future<void> _signUp()`
Purpose:
- Validates input.
- Creates a user account.
- Navigates to the dashboard.

Validation rules:
- Name, email, and password must not be empty
- Password must be at least 6 characters
- Password and confirm password must match

Flow:
1. Reads and trims field values.
2. Validates the form.
3. Sets loading state.
4. Calls `_auth.signUp(...)`.
5. Shows success `SnackBar`.
6. Waits briefly.
7. Navigates to `HouseDashboardScreen`.
8. On error, shows the error in a `SnackBar`.
9. Resets loading.

### `build(BuildContext context)`
Purpose:
- Renders the signup screen UI.

Main UI elements:
- Back button
- Green-themed signup card
- Name / email / password / confirm password fields
- Submit button or spinner
- Informational card explaining Firebase Auth + Firestore profile save
- Link back to sign in

### `_buildField(...)`
Purpose:
- Shared styled text field helper for the signup form.

---

## File: `lib/screens/create_house_screen.dart`

### `CreateHouseScreen`
Type:
- `StatefulWidget`

Purpose:
- Allows the current user to create a new house.

### `_CreateHouseScreenState`
Purpose:
- Holds form state and create-house logic.

State fields:
- `_houseService` → `HouseService`
- `houseNameController`
- `_loading`

### `dispose()`
Purpose:
- Disposes the house name controller.

### `Future<void> _createHouse()`
Purpose:
- Validates the house name.
- Creates a Firestore house document.
- Returns success back to the previous screen.

Flow:
1. Reads trimmed house name.
2. If empty, shows a `SnackBar`.
3. Sets loading state.
4. Calls `_houseService.createHouse(...)`.
5. Pops the screen with `true` so caller knows a house was created.
6. If creation fails, shows error `SnackBar`.
7. Resets loading.

### `build(BuildContext context)`
Purpose:
- Renders the create-house form.

Main UI elements:
- Back button
- House icon header
- Text field for house name
- Create House button / loading spinner
- Info card explaining Firestore creation behavior

---

## File: `lib/screens/house_dashboard_screen.dart`

### `HouseDashboardScreen`
Type:
- `StatefulWidget`

Purpose:
- Main logged-in screen.
- Shows the user’s house if one exists.
- Otherwise prompts the user to create a house.

### `_HouseDashboardScreenState`
Purpose:
- Controls dashboard actions and renders state based on house stream.

State fields:
- `_houseService` → `HouseService`
- `_authService` → `AuthService`

### `Future<void> _openCreateHouse()`
Purpose:
- Opens the create-house screen.
- If a house is successfully created, shows a success message.

### `Future<void> _signOut()`
Purpose:
- Signs out the current user.
- Clears navigation stack and returns to login screen.

### `build(BuildContext context)`
Purpose:
- Renders the dashboard shell and listens to the current user’s house stream.

Dynamic states handled:
- **Error:** shows a generic “Something went wrong” card
- **Loading:** shows a loading spinner
- **No house found:** shows empty-state card with create-house CTA
- **House found:** shows current house details

### `_buildShell(BuildContext context, {required Widget child})`
Purpose:
- Reusable page shell for the dashboard.
- Adds top title/header and sign-out button.

### `_buildEmptyState(BuildContext context)`
Purpose:
- Reuses `_buildInfoCard(...)` to show the no-house-yet state.

### `_buildHouseView(BuildContext context, House house)`
Purpose:
- Renders the current house details.

Currently shows:
- House name
- Leader UID
- Number of members
- Placeholder text for future features

### `_buildInfoCard(...)`
Purpose:
- Generic reusable card widget for empty/error states.

### `_buildStatChip(...)`
Purpose:
- Small reusable stat display component used in the dashboard house view.

Important limitation:
- Dashboard shows `leaderId` raw UID instead of a leader name.
- No member profile loading yet.

---

## 9) Firebase Integration

## File: `lib/firebase_options.dart`

Purpose:
- Holds generated FlutterFire configuration used by `Firebase.initializeApp(...)`.

Important current detail:
- Firebase options are configured for **Android**.
- Web, iOS, macOS, Windows, and Linux currently throw `UnsupportedError` if used.

What that means:
- The app is effectively configured for Android-first development right now.
- If multi-platform Firebase support is needed later, FlutterFire configuration should be regenerated for the missing platforms.

### Firebase Auth usage
The project uses Firebase Auth for:
- account creation
- sign-in
- sign-out
- storing the user display name in Firebase Auth profile

### Firestore usage
The project uses Cloud Firestore for:
- `users` collection → app user profiles
- `houses` collection → shared house documents

### Current likely Firestore document shapes

#### `users/{uid}`
```json
{
  "uid": "firebase-auth-uid",
  "name": "User Name",
  "email": "user@example.com",
  "rating": 0.0
}
```

#### `houses/{houseId}`
```json
{
  "houseId": "generated-doc-id",
  "name": "Greenview Apartment",
  "leaderId": "firebase-auth-uid",
  "members": ["firebase-auth-uid"],
  "createdAt": "server timestamp"
}
```

---

## 10) Navigation Flow

Current app flow:

1. App starts → `LoginScreen`
2. User can:
   - sign in
   - navigate to sign up
3. On successful sign up or sign in → `HouseDashboardScreen`
4. Dashboard checks whether the user belongs to a house
5. If not, user can open `CreateHouseScreen`
6. After creating a house, user returns to dashboard and the stream should show the created house
7. User can sign out and return to login

---

## 11) Current Product Features

Implemented now:
- Firebase initialization
- User signup
- User login
- User logout
- Firestore user profile creation
- Firestore user profile recovery/fallback on sign-in
- House creation
- Live dashboard stream for current user house
- Clean branded green UI theme

Not implemented yet:
- persistent auth session routing on app startup
- forgot password flow
- edit profile
- join house by invite
- leave house
- multiple houses
- rent/bill/task management
- notifications
- file/image uploads
- profile pictures
- settings page
- admin/leader tools
- real tests for current app behavior

---

## 12) Current Weak Points / Technical Debt

These are important for future planning:

### 1. No state management layer
The app directly calls services from widgets.
This is fine for a small prototype, but growth will get messy.
Possible future tools: Provider, Riverpod, Bloc, Cubit.

### 2. No auth state persistence flow in UI
The app always opens `LoginScreen` first.
Even if the user is already logged in, there is no `StreamBuilder<User?>` or splash/auth gate deciding where to go.

### 3. Minimal Firestore schema
Only users and houses exist right now.
Future features will need more collections or subcollections.

### 4. House membership logic is simplistic
A user is assumed to belong to at most one house.
There is no invite code, join request, or approval flow.

### 5. Dashboard is mostly a placeholder
It currently displays only the house name, leader UID, member count, and a future-features message.

### 6. Error handling is UI-friendly but not comprehensive
There are user-readable messages, but no logging strategy, retry strategy, or analytics.

### 7. Test file is outdated
`test/widget_test.dart` is still the default Flutter counter example and does not match the real app UI.

### 8. Firebase Storage is added but unused
This is not harmful, but it means planned media/file features have not been implemented yet.

### 9. README is still boilerplate
Project documentation has not yet been customized.

---

## 13) Likely Firestore Rules Requirements

For this app to work well, Firestore rules probably need to allow:

- authenticated users to create/read/update their own user profile document
- authenticated users to create a house
- authenticated users to read a house if they are a member

If rules are too strict, signup/profile creation or house loading can fail.

---

## 14) Suggested Next Features (Product Ideas)

These are strong next-step ideas for Roovia:

### House and membership
- invite roommates by code or email
- join house by invite link/code
- approve or reject join requests
- remove a member from house
- leave house
- transfer leader role

### Bills and rent
- monthly rent tracker
- split bills among members
- payment status tracking
- due date reminders
- recurring bills
- late payment warnings

### Tasks and chores
- chore board
- recurring chores
- rotation system
- completion tracking
- penalties or reward points

### Communication
- house announcements
- pinned messages
- issue reporting (maintenance, cleaning, supplies)
- in-app chat per house

### Trust and accountability
- roommate rating system
- payment reliability score
- task completion score
- dispute records / resolution workflow

### User profile upgrades
- profile photo upload
- phone number
- bio/about me
- preferred payment method
- emergency contact

### Documents and storage
- lease upload
- utility bills upload
- receipt/photo evidence
- house rules document storage

### Admin / management tools
- house settings page
- member permissions
- archived houses
- house audit log

### UX improvements
- splash screen with auth check
- onboarding flow
- empty-state illustrations
- dark mode
- profile editing screen
- better loading / retry UX

---

## 15) Good Engineering Improvements

These are technical upgrades worth considering soon:

- add auth gate / session restoration
- introduce state management (Riverpod would fit well)
- separate repositories from services if app grows
- add form widgets and validators as reusable components
- create a central app router
- add Firestore converters for stronger typing
- add unit tests and widget tests
- add integration tests for auth + house creation flow
- add logging and Crashlytics
- add environment separation for dev/staging/prod

---

## 16) Best Summary of What the App Is Right Now

Roovia is an early-stage Flutter/Firebase shared-house management app.
It already supports authentication, user profile creation, house creation, and a live dashboard that reacts to house membership.
The codebase is clean, simple, and suitable for building a stronger second version.
Its biggest current opportunity is expanding from “auth + create house” into real shared-living workflows like invites, rent, bills, chores, communication, and accountability.

---

## 17) Paste-Ready Prompt for ChatGPT

You can paste the following into ChatGPT:

```text
I have a Flutter + Firebase app called Roovia. It is a shared-house / roommate management app.

Current architecture:
- Flutter app with custom screens, models, and services
- Firebase Auth for sign up / sign in / sign out
- Cloud Firestore for user profiles and house data
- App starts on login screen
- After login/signup, user goes to a dashboard
- Dashboard watches whether the current user belongs to a house
- If the user has no house, they can create one
- House document stores houseId, name, leaderId, members, createdAt
- User profile stores uid, name, email, rating

Current implemented screens:
- LoginScreen
- SignUpScreen
- HouseDashboardScreen
- CreateHouseScreen

Current implemented services:
- AuthService for auth + profile creation/recovery
- HouseService for creating and streaming the current user’s house

Current limitations:
- no auth gate on startup
- no forgot password
- no profile editing
- no house invites or join flow
- no rent, bills, chores, payments, chat, or notifications yet
- dashboard is still basic
- Firebase Storage is included but unused

I want you to act like a senior product + engineering strategist.
Please suggest:
1. the best next features to build
2. a roadmap in priority order
3. the Firestore schema I should evolve toward
4. UX improvements for the current flow
5. technical architecture improvements for scalability
6. monetizable features if this became a startup

Please be specific and practical.
```

---

## 18) Final Notes

If someone is reviewing this codebase, the most important thing to understand is:

- the real app logic is concentrated in `lib/models`, `lib/services`, and `lib/screens`
- Firebase is central to both identity and data
- the app is still in a strong prototype/MVP stage
- the next phase should focus on deeper house-management workflows, better data design, and stronger app architecture
