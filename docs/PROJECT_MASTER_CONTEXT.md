# Roovia Project Master Context

Last updated: 2026-07-01

This is the primary context document for Roovia. If this file conflicts with older docs, follow this file and the live codebase.

Roovia is a shared-house management platform designed to reduce the friction of living with roommates. The codebase already reflects a production-oriented architecture centered on Firebase, deterministic billing flows, push notifications, and strict Firestore/Storage rules. The long-term vision is bigger than simple bill splitting: Roovia should help small houses, student apartments, and eventually larger shared communities coordinate membership, expenses, trust, reminders, and accountability with minimal manual work.

---

## 1. Project Vision

Roovia exists to make shared housing feel organized, transparent, and trustworthy.

The product is built around the real problems that appear in roommate life:

- members join and leave shared homes
- monthly costs must be understood before people commit to a house
- bills need to be requested, tracked, and confirmed without repeated manual reminders
- payment proof needs to be reviewed consistently
- people need a central place to see house updates, chat, and notifications
- trust depends on clear records, role boundaries, and predictable behavior

The codebase shows that Roovia is not meant to be a generic social app. It is a house-operations system: discover a house, request to join, manage household costs, send bills, confirm payment, and keep everyone informed. The intended future direction is to scale this same structure from small student houses to much larger communities without replacing the underlying model.

The product vision should be read as:

1. reduce repetitive roommate coordination
2. automate reminders and confirmations
3. preserve a clear audit trail for bills and proofs
4. keep the UI simple enough that normal users do not need training
5. keep the architecture production-ready so the platform can grow safely

If a future feature does not solve a real roommate problem, it is probably out of scope.

---

## 2. Design Philosophy

Roovia prioritizes:

- simplicity over feature bloat
- automation over manual follow-up
- trust over hidden state
- transparency over opaque workflows
- scalability over quick one-off shortcuts
- production-ready architecture over demo-only code
- clean UI over visual noise
- minimal user friction over unnecessary steps

This philosophy is visible in the code:

- all major side effects are handled through services rather than screens
- Firestore document IDs and notification IDs are deterministic
- the app uses rules and Cloud Functions to protect cross-user flows
- existing data is normalized defensively so older documents still work
- the interface uses Material 3, card-based layouts, and restrained color usage

The design direction is intentionally conservative. Roovia should feel polished and modern, but it should not become heavy, decorative, or difficult to maintain. Every feature should map back to a roommate problem.

---

## 3. Current Project State

### Implemented systems

The current codebase already includes:

- Firebase Auth sign-up, sign-in, and sign-out
- Firestore-backed user profile creation and recovery
- username normalization, uniqueness checks, and profile editing
- profile image upload, cropping, compression, replacement, and cleanup
- house creation with invite codes, membership, location, and monthly cost totals
- house discovery by name and Bartın district filter
- invite-code joining and join-request workflows
- owner approval/rejection of join requests
- house dashboard with membership, house details, invite code, and cost summary
- real-time house chat with unread tracking metadata
- bill creation and per-participant settlement records
- payment proof submission and review
- in-app notification documents plus FCM push relay
- scheduled bill reminders
- alerts inbox with navigation to expense detail screens
- notification tap handling for foreground, background, and terminated app states

### Partially implemented systems

- the house dashboard has a members entry point that is still a placeholder
- `FeedScreen` exists as a future shell, not as a production feed
- `NotificationsScreen` exists as a future shell, while `AlertsScreen` is the active inbox
- `ChatInboxScreen` exists as an auxiliary entry surface, but the main navigation uses house dashboard plus notification routing
- some Firestore schemas still accept legacy field names during reads, but writes are not uniformly normalized across all historical data
- the profile UI can display a bio field, but the current profile service/model does not formally manage it

### Unfinished or intentionally incomplete systems

- financial analytics dashboard is the current major milestone, but it is not fully implemented yet
- a true activity feed is not yet present
- admin tools are not yet a primary surface
- house deletion does not cascade through every dependent collection and storage object
- cross-platform Firebase options are not configured for all desktop/web targets

### Temporary or legacy implementations

- the dashboard members card is a placeholder
- `house_images` in Storage rules is permissive future scaffolding, not a backed feature
- old docs still describe an earlier financial model and earlier upload assumptions
- some screens include future-facing empty states instead of live product data

### Future-ready implementations already in place

- deterministic notification IDs prevent duplicates across retries
- legacy membership fields are accepted on reads for older house documents
- payment proof parsing still renders legacy image attachments if they exist in data
- chat unread logic uses last-seen metadata and has a fallback path when that metadata is missing
- avatar uploads store both download URLs and storage paths so old files can be removed safely later

### Current technical debt

- house deletion is not a full cascade
- `currentHouseId` is checked in join logic but is not written by any obvious current flow
- profile `bio` is surfaced in UI but not fully modeled in the service layer
- some older docs are stale enough to be misleading if read without this file

---

## 4. Complete Architecture

### Layering

The application is split into a clean set of layers:

- Flutter UI screens and widgets
- service layer for all business logic and Firebase I/O
- model layer for Firestore serialization and type safety
- Firebase backend services
- Firestore security rules
- Storage security rules
- Cloud Functions for cross-user and scheduled side effects

This separation exists so the UI remains lightweight, business logic stays reusable, and production behavior can evolve without rewriting screens.

### App bootstrap and navigation

- [lib/main.dart](../lib/main.dart) initializes Firebase, registers the background FCM handler, fetches the initial notification tap payload, and wires the navigation key used for notification-driven routing.
- The app starts at the login screen and routes to the main shell after authentication.
- Notification taps route directly to either bill detail or chat, depending on payload contents.
- [lib/screens/main_screen.dart](../lib/screens/main_screen.dart) is the central shell with bottom navigation and a center create-house action.

### Service layer

The service layer is split by domain:

- [lib/services/auth_service.dart](../lib/services/auth_service.dart)
- [lib/services/user_service.dart](../lib/services/user_service.dart)
- [lib/services/house_service.dart](../lib/services/house_service.dart)
- [lib/services/chat_service.dart](../lib/services/chat_service.dart)
- [lib/services/expense_service.dart](../lib/services/expense_service.dart)
- [lib/services/fcm_service.dart](../lib/services/fcm_service.dart)

Why this exists:

- auth/profile logic should not be duplicated in screens
- house creation/search/join logic should stay together
- billing and proof logic need one controlled code path
- chat message sending and unread tracking are separate concerns
- notification registration belongs in one service because it crosses app lifecycle, FCM, and Firestore

### Model layer

The model layer contains typed representations for the main Firestore documents:

- [lib/models/user_model.dart](../lib/models/user_model.dart)
- [lib/models/house_model.dart](../lib/models/house_model.dart)
- [lib/models/join_request_model.dart](../lib/models/join_request_model.dart)
- [lib/models/message_model.dart](../lib/models/message_model.dart)
- [lib/models/expense_model.dart](../lib/models/expense_model.dart)
- [lib/models/payment_proof.dart](../lib/models/payment_proof.dart)

Why this exists:

- Firestore data remains typed when it enters Dart
- screens can render from models rather than raw maps
- legacy data normalization can happen in one place
- future migrations can be implemented gradually

### Firebase stack

Roovia currently uses:

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Messaging
- flutter_local_notifications
- Cloud Functions

The package set in [pubspec.yaml](../pubspec.yaml) supports the current production path, including avatar uploads, payment proofs, local notifications, and file picking.

### Cloud Functions

The Node 20 functions project in [functions/index.js](../functions/index.js) currently exports:

- `sendPushOnHouseChatMessage`
- `sendPushOnUserNotification`
- `processBillReminders`

These functions exist to keep push delivery, chat notification fan-out, and reminder scheduling event-driven rather than pushing that complexity into the client.

### Project folder responsibilities

- `lib/constants/`: location constants and shared configuration values
- `lib/models/`: Firestore-to-Dart data classes
- `lib/screens/`: UI screens and route destinations
- `lib/services/`: Firebase access and domain logic
- `functions/`: Cloud Functions backend logic
- `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`: platform shells and generated config
- `firestore.rules`: Firestore access policy
- `storage.rules`: Storage access policy
- `docs/`: long-form project documentation and handoff context

---

## 5. Firestore Structure

### Collection map

| Path | Purpose | Ownership and access |
| --- | --- | --- |
| `users/{uid}` | User profile, avatar, push token, and profile metadata | Readable by signed-in users; writable only by the owner |
| `houses/{houseId}` | House identity, membership, location, monthly totals, invite code | Readable by signed-in users; writable/deletable only by the leader |
| `join_requests/{requestId}` | Join request lifecycle between a user and a house | Readable by requester and house leader; managed by requester and leader |
| `house_chats/{houseId}/messages/{messageId}` | Real-time group chat messages for a house | Read/write for house members and the house leader |
| `house_user_meta/{metaId}` | Per-user per-house chat metadata such as `lastSeenAt` | Used for unread counts; owner-scoped |
| `house_expenses/{expenseId}` | Shared bill record and settlement state | House members can read; house leader controls write and settlement |
| `house_expenses/{expenseId}/participants/{userId}` | Per-user bill state, proof metadata, and settlement state | Readable by house members; updates controlled by leader or participant depending on transition |
| `user_notifications/{uid}/notifications/{nid}` | Canonical in-app notification stream for a user | Readable and mutable by the owner; create is intentionally permissive |

### `users/{uid}`

Current fields seen in code and rules:

- `uid`
- `name`
- `email`
- `username`
- `profileImageUrl`
- `profileImageStoragePath`
- `profileImageUpdatedAt`
- `rating`
- `fcmToken`
- `fcmTokenUpdatedAt`

Fields that appear in current UI or logic but are not fully formalized:

- `bio`
- `currentHouseId`

Important notes:

- the Firestore rules allow any signed-in user to read user documents
- updates are self-owned only
- `fcmToken` is used by the Cloud Function push relay
- profile image cleanup depends on `profileImageStoragePath` when available

### `houses/{houseId}`

Current normalized fields:

- `houseId`
- `name`
- `chatName`
- `leaderId`
- `members`
- `inviteCode`
- `discoverable`
- `city`
- `district`
- `address`
- `rentTotal`
- `electricityTotal`
- `waterTotal`
- `internetTotal`
- `maxMembers`
- `description`
- `createdAt`
- `updatedAt`

Legacy field names accepted during reads:

- `ownerId`
- `adminId`
- `leader_id`
- `houseName`
- `house_name`
- `title`
- `invite_code`
- `code`
- `memberIds`
- `users`
- `userIds`
- `isDiscoverable`
- `public`
- `area`

Why the structure was chosen:

- one house document can serve as the membership and summary source of truth
- the `members` array enables efficient membership checks
- totals are stored directly so the app can compute estimated shares at read time
- invite codes make house discovery and onboarding simple

### `join_requests/{requestId}`

Fields:

- `houseId`
- `userId`
- `status`
- `createdAt`
- `updatedAt`
- `handledBy`

States:

- `pending`
- `accepted`
- `rejected`

Why it exists:

- join requests are separate from house membership so the owner can approve or reject explicitly
- the request document becomes the audit trail for onboarding decisions

### `house_chats/{houseId}/messages/{messageId}`

Fields:

- `senderId`
- `senderName`
- `text`
- `createdAt`

Why it exists:

- chat data is scoped to the house namespace
- message ordering is stable because it is based on `createdAt`
- sender display data is denormalized into the message for faster rendering

### `house_user_meta/{houseId}_{userId}`

Fields:

- `houseId`
- `userId`
- `lastSeenAt`

Why it exists:

- unread counts need a compact and queryable last-seen marker
- storing this separately avoids modifying message documents for every read event

### `house_expenses/{expenseId}`

Fields:

- `houseId`
- `category`
- `title`
- `description`
- `dueDate`
- `reference`
- `totalAmount`
- `perPersonAmount`
- `createdBy`
- `createdAt`
- `status`
- `reminderEnabled`
- `reminderCount`
- `overdueReminderCount`
- `lastReminderAt`
- `lastReminderSentAt`

Why it exists:

- the root bill document stores the bill-level state machine and reminder counters
- `perPersonAmount` is persisted for each bill even though house-level cost estimates are derived dynamically elsewhere
- `status` keeps the bill lifecycle simple for UI and Cloud Functions

### `house_expenses/{expenseId}/participants/{userId}`

Current fields:

- `userId`
- `amountOwed`
- `status`
- `paidAt`
- `confirmedAt`
- `paymentProofStatus`
- `paymentProofRevision`
- `paymentProofNote`
- `paymentProofs`
- `paymentProofSubmittedAt`
- `paymentProofReviewedAt`
- `paymentProofReviewReason`

Why it exists:

- each participant needs an independent settlement state
- proofs belong to the participant, not to the expense root
- the structure supports approval, rejection, resubmission, and deterministic notification fan-out

### `user_notifications/{uid}/notifications/{nid}`

This is the canonical in-app notification stream.

Common fields across notification types:

- `title`
- `body`
- `type`
- `read`
- `createdAt`
- `houseId`
- `expenseId`
- `fromUserId`
- `userName`

Additional fields used by specific flows:

- `billTitle`
- `billAmount`
- `dueDate`
- `details`
- `paymentProofRevision`
- `paymentProofCount`
- `paymentProofNote`
- `messageId`
- `senderId`
- `senderName`
- `messageText`
- `pushSentAt`
- `pushMessageId`
- `pushFailedAt`
- `pushErrorCode`

Why it exists:

- the Firestore notification document is the source of truth
- FCM is a delivery mechanism, not the canonical record
- deterministic IDs make the flow repeatable and duplicate-resistant

### Ownership rules

- user documents are self-owned for writes
- house documents are leader-owned for writes and deletes
- join requests are requester-owned for creation and leader-owned for adjudication
- expense roots are leader-created and leader-managed
- participant documents are user-specific, but the leader controls approval and rejection transitions
- notification documents are owner-visible, but creation is intentionally permissive so lightweight client writes can work

---

## 6. Storage Structure

### Current paths

| Path | Purpose | Notes |
| --- | --- | --- |
| `users/{uid}/profile/avatar_<timestamp>.<ext>` | Preferred profile avatar location | Current upload path from [UserService](../lib/services/user_service.dart) |
| `profile_images/{uid}/...` | Legacy avatar path | Still readable for backward compatibility |
| `bills/{billId}/payments/{userId}/proofs/{revision}_{index}_{stamp}_{fileName}` | Payment proof attachments | Current upload path for bill proofs |
| `house_images/{houseId}/...` | Future house image scaffolding | Present in rules, not a primary product feature |

### Profile images

Profile avatar handling is production-oriented:

- selected in [EditProfileScreen](../lib/screens/edit_profile_screen.dart)
- cropped to square before upload
- compressed if needed to stay under the size limit
- uploaded as image content only
- stored along with the download URL and storage path in Firestore
- old files are deleted on replacement when the path is known

Security approach:

- only the authenticated owner can upload or delete their own avatar
- content type must be an image
- size limit is enforced in both UI and Storage rules

### Payment proofs

Payment proof uploads are currently PDF-only.

Why PDF-only:

- easier for owners to review consistently
- safer to archive than a loose image set
- smaller attachment variety means less ambiguity in the approval workflow
- the UI and service layer can enforce one deterministic upload path

Current proof structure:

- files are attached to a specific expense and participant
- each submission can contain up to 3 PDF files
- each file is capped at 12 MB in the UI and rules
- the upload path includes expense, participant, revision, index, and a unique stamp

Backward compatibility:

- legacy image proof attachments remain readable if they already exist in Firestore data or Storage
- the expense detail screen can still render them
- current uploads do not create new image proofs

Security approach:

- the owner or the relevant participant may access proof files
- uploads are restricted to PDF content for the current proof path
- deletion is limited to the same access boundary

### Naming conventions

- avatar files use a timestamp-based name to avoid collisions
- proof files include revision and index so resubmissions remain distinguishable
- storage-safe path segments are sanitized before upload
- the code keeps download URL and storage path together so cleanup remains possible later

---

## 7. Billing System

The billing system is one of the most important production subsystems in Roovia.

### Current lifecycle

1. the house leader creates a bill in [ExpenseService.createExpense](../lib/services/expense_service.dart)
2. the root `house_expenses` document is created with a `pending` status
3. the owner is inserted as a confirmed participant immediately
4. selected members are inserted as pending participants
5. in-app notification documents are created for each participant
6. the bill appears in the expense list and detail views through Firestore streams
7. a participant submits payment proof and marks themselves paid
8. the owner reviews the proof and either approves or rejects it
9. once all non-owner participants are confirmed, the expense can become fully confirmed
10. notification documents are written at each major transition so the push relay can notify users

### Bill state machine

#### Expense root

| State | Meaning | Transition out |
| --- | --- | --- |
| `pending` | The bill exists but is not yet fully settled | Moves to `confirmed` when all participants are confirmed |
| `confirmed` | The bill is fully settled | Terminal state in the current implementation |

#### Participant state

| State | Meaning | Transition out |
| --- | --- | --- |
| `pending` | Participant has not submitted proof yet, or proof was rejected and needs resubmission | Moves to `paid` when participant submits proof |
| `paid` | Participant has submitted proof and is waiting on owner review | Moves to `confirmed` on approval, or back to `pending` on rejection |
| `confirmed` | Owner has accepted the participant’s payment | Usually terminal for that participant |

### Owner creation path

When the leader creates a bill:

- the leader is enforced by the service layer and by Firestore rules
- `perPersonAmount` is computed from the total divided by total participants
- the owner is auto-confirmed to avoid a deadlock where the creator would need to pay themselves manually
- the bill root gets reminder counters and reminder flags initialized
- each participant gets its own document for state, amount owed, and proof data

### Participant submission path

When a participant submits payment:

- only the participant can mark their own payment as paid
- optional proof attachments are uploaded first
- the participant document moves from `pending` to `paid`
- proof metadata is written to the participant document
- a notification document is written for the creator
- if all non-owner participants are now paid, the creator receives a settlement-ready notification

### Owner approval and rejection path

Approval:

- only the expense creator can approve
- the participant must already be in `paid`
- the participant moves to `confirmed`
- the proof review metadata is updated
- the participant receives a confirmation notification
- if all participants are confirmed, the bill root becomes `confirmed`

Rejection:

- only the expense creator can reject
- the participant must already be in `paid`
- the participant returns to `pending`
- proof attachments are deleted best-effort from Storage
- the participant receives a rejection notification
- the bill root remains or returns to `pending`

### Batch confirmation path

The service also supports a final settlement path:

- the creator can confirm all currently paid participants in one batch
- participants that are still only `pending` remain unchanged
- after batch confirmation, if every participant is confirmed, the root bill becomes confirmed and settlement notifications are sent

### Reminder lifecycle

Reminder automation is handled by Cloud Functions:

- `processBillReminders` scans expenses due within the reminder window
- reminders are sent on the 3-day, 1-day, and overdue schedule when eligibility rules allow it
- cooldown counters avoid repeated spam within a short window
- reminder notifications are also written as Firestore docs so the same push relay can deliver them

### Cloud Function involvement

- Firestore notification docs are written by the client and by Cloud Functions
- `sendPushOnUserNotification` relays those docs to FCM using the stored user token
- `processBillReminders` runs hourly in UTC
- the architecture intentionally keeps the client responsible for local state, while the backend handles delivery and automation

---

## 8. Notification System

### Canonical notification model

Roovia treats Firestore notification documents as the source of truth. FCM is downstream delivery.

The canonical path is:

`user_notifications/{uid}/notifications/{nid}`

### Notification types in the current system

- bill created / expense request
- payment proof submitted
- payment proof approved
- payment proof rejected
- bill ready for owner confirmation
- bill settled / paid
- bill due soon
- bill due tomorrow
- bill overdue reminder
- chat message

### FCM token handling

- FCM tokens are stored on `users/{uid}.fcmToken`
- tokens are refreshed on auth changes and token rotation
- token writes are guarded so the same token is not stored repeatedly in the same session
- invalid tokens are cleared when FCM returns registration-token errors

### Cloud Functions and push relay

`sendPushOnUserNotification` performs the relay:

- it reads the destination user’s stored token
- it skips pushes when the notification already has `pushSentAt`
- it writes `pushSentAt` and `pushMessageId` on success
- it stores `pushFailedAt` and `pushErrorCode` on failure
- it clears invalid tokens when FCM says the token is dead

### Deterministic notifications

Duplicate prevention is intentionally deterministic:

- notification doc IDs are stable and action-specific
- chat notification IDs include house, message, and recipient
- bill notification IDs include expense, recipient, and action type
- `pushSentAt` prevents duplicate relay attempts on the same doc

This means retrying a write does not invent a new notification identity.

### Local notifications and app lifecycle

[FcmService](../lib/services/fcm_service.dart) handles the client side:

- requests notification permission
- initializes flutter_local_notifications
- creates a shared Android notification channel
- shows a local notification for foreground messages
- handles background and terminated notification taps
- routes tap payloads to bill detail or chat screens
- refreshes token registration when the app resumes

### Current notification flow

1. client or Cloud Function writes an in-app notification document
2. `sendPushOnUserNotification` observes the new document
3. FCM push is sent using the stored token
4. the client shows a local notification if the app is foregrounded or if the background handler receives it
5. notification taps route back into the correct expense or chat screen

### Avoiding duplicates

- stable notification IDs
- Firestore doc IDs that are derived from the business action
- `pushSentAt` and `pushFailedAt` metadata
- create-once behavior for bill and reminder side effects

### Chat notifications

Chat notifications are separate from bill notifications:

- new chat messages create in-app notification docs for other house members
- the Cloud Function fans those docs out to FCM
- unread count logic is independent and relies on `house_user_meta`

---

## 9. Payment Proof System

### Current behavior

Payment proofs are currently a PDF-first workflow.

The current user flow is:

1. participant opens bill detail
2. participant chooses to submit proof
3. participant attaches up to 3 PDF files
4. files are uploaded to Storage
5. the participant is marked `paid`
6. proof metadata is written to the participant subdocument
7. the creator receives a review notification
8. the creator approves or rejects the proof

### Storage and metadata

Current attachment metadata includes:

- `fileName`
- `downloadUrl`
- `storagePath`
- `mimeType`
- `kind`
- `sizeBytes`
- `uploadedAt`

This metadata is persisted in the participant document so the detail view can render attachments without guessing the original file source.

### Why PDF-only uploads

PDF-only uploads are intentional for current submissions:

- the format is easier to review consistently
- it keeps the review flow predictable across devices
- it reduces ambiguous image handling and conversion differences
- it gives a more stable archival path for payment evidence

### Approval flow

On approval:

- the participant moves from `paid` to `confirmed`
- the proof status is marked approved
- review metadata is stamped
- the participant gets a confirmation notification
- if everyone is confirmed, the bill can be settled

### Rejection flow

On rejection:

- the participant returns to `pending`
- `paidAt` and `confirmedAt` are cleared
- proof arrays are cleared from the participant document
- proof files are deleted from Storage best-effort
- the participant gets a rejection notification with an optional reason

### Cleanup strategy

- replaced avatar files are deleted best-effort after the new image is stored
- rejected proof attachments are deleted best-effort after the document is rolled back
- storage cleanup never blocks the main UX if the file deletion fails

### Retry strategy

- download URL retrieval retries transient object-not-found states
- uploads are sequential for proof attachments
- cleanup is best-effort and non-blocking

### Security rules

The Storage rules enforce:

- access only for the owner or the relevant participant
- proof uploads only as PDFs in the current path
- content size limits
- self-owned avatar access for profile images

### Backward compatibility

Legacy image proofs remain readable when they already exist in data. The detail view can still render them, even though new uploads are PDF-only.

---

## 10. User System

### Authentication

Authentication is Firebase Auth based.

Current auth behavior:

- sign-up creates the Firebase Auth account
- the Firestore profile doc is created immediately after auth creation
- sign-up signs the user out afterward and returns them to login
- sign-in can recover from a missing profile doc by building a fallback user from Firebase Auth data
- sign-out returns the user to the login screen

### Profiles

The profile system uses `users/{uid}` as the main profile source.

Current profile fields:

- display name / `name`
- `username`
- `profileImageUrl`
- `rating`
- optional `bio` in some read paths

### Username rules

The username rules are strict and intentional:

- lowercase only
- 3 to 20 characters
- letters, numbers, and underscores only
- no spaces
- uniqueness enforced against the `users` collection

AuthService can generate a username from email if none exists yet, and UserService validates updates before saving them.

### Profile pictures

Current avatar workflow:

- choose from gallery or camera
- crop to square
- compress if needed
- upload to Storage
- update Firestore with the new URL and storage path
- delete the previous avatar best-effort

### House membership

House membership is represented by the `members` array on the house document. The house leader is represented by `leaderId`.

Current membership behavior:

- a new house starts with the creator as its sole member
- join requests are separate documents
- the owner adjudicates requests
- house detail shows address only to members
- join-by-invite uses invite codes and membership guards

### Roles and privileges

The current system uses a leader/member split rather than a large role hierarchy.

#### Leader privileges

- create a house
- approve or reject join requests
- update monthly house cost totals
- rename the house chat
- create bills
- approve or reject payment proofs
- confirm all paid participants
- delete the house

#### Member privileges

- view member-only house details
- join via invite or request
- participate in house chat
- receive bill notifications and reminders
- submit payment proof for their own bills
- read their own notifications

### Important caveat

`currentHouseId` is read in join-by-invite logic, but no obvious current write path updates it. That means it should be treated as a legacy or incomplete guard, not as the authoritative membership source.

---

## 11. Chat System

### Current structure

Chat is implemented as:

- `house_chats/{houseId}/messages`
- `house_user_meta/{houseId}_{userId}` for read/unread state

### Realtime listeners

- the message list is streamed in real time
- unread count is streamed independently through house metadata plus message queries
- the chat screen marks the conversation as seen when the stream first loads data

### Ordering

- messages are ordered by `createdAt` ascending
- the UI scrolls to the bottom when new messages arrive
- sender name and timestamp are rendered from the message doc

### Permissions

- only house members and the house leader can read or write chat messages
- unread metadata writes are scoped to the current user and house

### Current limitations

- no edit or delete message actions
- no typing indicators
- no attachments
- no read receipts beyond last-seen metadata
- no pagination yet
- one conversation per house only

### Scalability considerations

- the current namespace keeps chat data partitioned by house
- ordering and unread logic are query-based rather than client-count based
- the current model is compatible with future pagination if message volume grows

### Current surfaces

- [ChatScreen](../lib/screens/chat_screen.dart) is the active house chat screen
- [ChatInboxScreen](../lib/screens/chat_inbox_screen.dart) is an auxiliary house list for opening chats
- [FeedScreen](../lib/screens/feed_screen.dart) and [NotificationsScreen](../lib/screens/notifications_screen.dart) are not the active chat surfaces

---

## 12. UI Principles

The current UI direction is deliberately restrained and production-friendly.

### Visual language

- modern cards
- soft shadows
- rounded surfaces
- readable spacing
- dark green and light green palette
- Material 3 foundations

### Layout principles

- minimal clutter
- information grouped by task
- clear hierarchy for primary actions
- responsive use of width and padding
- empty states that are clean rather than noisy

### Component reuse

The codebase favors reusable UI patterns such as:

- card shells
- pill badges
- info rows
- metric bubbles
- placeholder cards
- reusable avatar fallback patterns

### Future UI consistency rule

Any new UI should look like Roovia, not like a one-off prototype. That means:

- keep the current palette and card language unless a design system migration is explicitly planned
- keep actions obvious and not crowded
- preserve clarity around bills, trust, and status
- make future screens consistent with the current shell and typography

---

## 13. Performance Principles

The codebase shows a few clear performance rules:

- avoid unnecessary global listeners
- keep Firestore streams on visible screens only
- debounce search input
- use targeted queries instead of loading unrelated collections
- reuse cached images for remote avatars and photos
- store computed summaries when they are stable enough to avoid repeated expensive calculations
- use batch writes for coordinated Firestore updates
- use deterministic IDs so retries do not multiply records
- keep Storage usage bounded with file size limits

Current examples:

- search is debounced in [SearchScreen](../lib/screens/search_screen.dart)
- unread counts use a metadata document instead of scanning every message blindly
- avatar loading uses cached network images
- billing writes are batched where compound state changes are needed
- permission and token registration are handled without blocking the UI

### Firestore cost discipline

Roovia should continue to minimize Firestore reads and listeners by default:

- query only the house the user is interacting with
- keep participant details in subcollections rather than large root arrays
- avoid duplicating per-user derived data unless it materially reduces reads
- prefer one stable summary document over many repeated ad hoc reads

### Offline-friendly direction

The code is not a fully offline-first app, but it is structured so that it can remain responsive when data is temporarily unavailable:

- local UI state is used while network actions are in flight
- cached images and last-known Firestore data soften loading states
- failure messages are surfaced rather than silently swallowed

---

## 14. Development Principles

### Architectural rules

- never redesign a working architecture casually
- reuse services instead of duplicating Firebase logic in screens
- keep business logic inside services, not in widget trees
- keep widgets lightweight and presentation-focused
- keep Cloud Functions event-driven
- keep Firestore writes deterministic and auditable
- keep rules, UI, and functions aligned whenever a data path changes
- preserve backward compatibility until old data is actually migrated

### Practical engineering rules

- if a feature touches billing or notifications, validate the full client-to-Cloud-Function flow
- if a feature touches membership, update reads, writes, and rules together
- if a feature touches Storage, update the upload UI and the security rules together
- do not remove legacy field parsing until the database is normalized
- prefer expanding the existing service layer over creating parallel ad hoc helpers

### What the next engineer should keep doing

- keep debug logging where it helps trace payment, auth, and notification flows
- keep timeouts around network operations
- keep defensive fallbacks when reading Firestore docs that may be partially missing
- keep writes deterministic and idempotent where possible

### What should not be rewritten lightly

- the current house membership model
- the deterministic notification architecture
- the Firestore collection names that other systems already depend on
- the service/model separation
- the current Material 3 visual direction

---

## 15. Current Roadmap

### Already completed foundation

The core foundation is already in place:

- auth and profile flow
- house creation and discovery
- invite and join-request flow
- house dashboard and profile surfaces
- house chat
- bill request and settlement flow
- payment proof submission and review
- notifications and reminders
- avatar upload pipeline

### Current major milestone

The current major milestone is the Financial Analytics Dashboard.

Important context:

- the older roadmap document still describes a simpler Phase 1 estimate model
- the live code already stores total monthly house costs and computes per-person estimates at runtime
- that means the financial dashboard should build on the current architecture, not replace it

### Likely next milestones

Only realistic future work should be treated as active roadmap material:

- financial analytics dashboard completion
- analytics polishing
- search improvements
- house activity feed
- settings
- admin tools
- performance optimization
- production polish

### Roadmap interpretation rule

If the older roadmap file and the live code disagree, the code wins for current implementation and this master document wins for architectural intent.

---

## 16. Known Issues

This section is intentionally explicit so a future AI does not waste time rediscovering the same constraints.

### Documentation drift

- [README.md](../README.md) is still generic starter text and does not describe the real product
- [PROJECT_CONTEXT_FOR_CHATGPT.md](legacy-markdown/PROJECT_CONTEXT_FOR_CHATGPT.md) contains older state summaries and should be treated as historical once this master doc exists
- [FUTURE_FEATURES_AND_ROADMAP.md](legacy-markdown/FUTURE_FEATURES_AND_ROADMAP.md) still contains stale financial assumptions from the pre-total-cost phase

### Functional limitations

- house deletion does not cascade to expenses, messages, notifications, or storage objects
- the dashboard members card is still a placeholder
- feed and notifications legacy screens are not the primary production surfaces
- `currentHouseId` is not maintained by a visible write path
- profile `bio` is read in some UI surfaces but is not fully managed by the current service/model layer
- chat has no editing, deleting, typing, or read receipts beyond last-seen tracking

### Temporary or permissive scaffolding

- `house_images` Storage rules are permissive future scaffolding
- `user_notifications` creation is intentionally permissive so client-side lightweight writes work, which means duplicate prevention depends on deterministic IDs rather than hard rule isolation
- some code paths still carry compatibility logic for older field names that should eventually be normalized away

### Technical risks

- unread counts can be timing-sensitive because `lastSeenAt` relies on server timestamps
- notification delivery depends on stored FCM tokens and on the Cloud Functions deployment being healthy
- Storage cleanup is best-effort, so orphaned files can remain if deletion fails
- Firebase options are not configured for every platform target, so non-Android runtime support is incomplete

### Legacy compatibility notes

- legacy image proofs remain readable even though new proof submissions are PDF-only
- old house documents may still use alternate membership or discoverability field names
- profile avatar paths can be read from both new and legacy storage locations

---

## 17. Handoff Notes

This section is written for the next coding AI as lead-architect guidance.

### How to continue safely

- start by understanding the existing service that owns the behavior you want to change
- extend the current model and service layer before adding a new parallel path
- keep Firestore writes deterministic so retries do not duplicate records
- keep Cloud Functions event-driven for anything that crosses user boundaries
- validate the full flow end to end when touching billing, notifications, membership, or Storage

### How to avoid breaking the architecture

- do not move business logic into widgets
- do not create a second notification pipeline
- do not change collection names casually
- do not remove legacy field parsing until migration work is complete
- do not rewrite the house membership model without a migration plan
- do not replace the current push relay with direct client push logic

### Which systems are already production-ready

- auth and profile flow
- house creation, search, and join flows
- house chat and unread metadata
- bill creation and participant settlement state
- payment proof submission and review
- notification document pipeline and push relay
- avatar upload and cleanup

### Which systems are sensitive

- billing state transitions
- payment proof Storage paths
- notification doc IDs and push relay behavior
- house deletion
- unread count timing
- membership writes and invite-code joining

### How new features should be integrated

- if the feature affects cross-user state, add a Firestore document shape first
- if it affects delivery, add or update a Cloud Function second
- if it affects access control, update security rules in the same change set
- if it affects the UI, keep the current visual language and reusable card patterns
- if it affects existing entities, prefer additive fields over replacements

### What should never be rewritten lightly

- the `users`, `houses`, `join_requests`, `house_chats`, `house_user_meta`, `house_expenses`, and `user_notifications` collection names
- the deterministic notification ID strategy
- the service/model split
- the leader/member permission model
- the current Material 3 design language

### Scalability guidance

- keep data partitioned by house and by user
- prefer subcollections for per-participant or per-message data
- keep reminders and push fan-out event-driven
- avoid adding giant root-level arrays for frequently changing data
- preserve the ability to paginate chat and expense histories later

### Final rule for future AI engineers

If a proposed change improves speed but weakens trust, determinism, or recoverability, the change is probably wrong for Roovia.
