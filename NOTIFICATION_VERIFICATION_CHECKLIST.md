# Notification & Reminder Verification Checklist

Use this checklist to verify the existing push notification and reminder system after deployment or device changes.

## 1. App Foreground
- [ ] Sign in on the device/emulator.
- [ ] Confirm the app saves `users/{userId}.fcmToken` in Firestore.
- [ ] Create a new expense/bill.
- [ ] Confirm the in-app notification document appears under `user_notifications/{userId}/notifications`.
- [ ] Confirm a foreground local notification appears immediately.
- [ ] Tap the foreground notification and confirm it opens the correct expense detail screen.

## 2. App Background
- [ ] Put the app in the background.
- [ ] Trigger a new notification doc.
- [ ] Confirm an Android system notification appears.
- [ ] Tap it and confirm it opens the correct expense detail screen.

## 3. App Terminated
- [ ] Force stop or swipe away the app.
- [ ] Trigger a notification doc from another account or test flow.
- [ ] Confirm the push notification appears while the app is closed.
- [ ] Tap it and confirm the app launches into the correct expense detail screen.

## 4. Two-Emulator Test
- [ ] Use Emulator A for the signed-in owner.
- [ ] Use Emulator B for the participant.
- [ ] Verify both users have valid `fcmToken` values.
- [ ] Create a bill on Emulator A.
- [ ] Confirm Emulator B receives the notification in app, background, and terminated states.

## 5. Real Device Test
- [ ] Test on a physical Android device with Google Play services.
- [ ] Confirm notification permission is granted.
- [ ] Confirm `fcmToken` saves successfully.
- [ ] Verify push arrives while app is backgrounded and terminated.

## 6. Bill Created
- [ ] Create a bill with at least one pending member.
- [ ] Confirm only pending members receive reminders/notifications.
- [ ] Confirm deterministic notification docs are created once per target.

## 7. Member Paid
- [ ] Mark one participant as paid.
- [ ] Confirm the creator receives the payment-submitted notification.
- [ ] Confirm no duplicate notification is created for the same action.

## 8. Owner Confirmed
- [ ] Confirm the paid participant from the owner flow.
- [ ] Confirm the participant receives a payment-confirmed notification.
- [ ] Confirm the expense status updates correctly.

## 9. Reminder Sent
- [ ] Set a due date 3 days ahead.
- [ ] Confirm the due-soon reminder is sent once.
- [ ] Set a due date 1 day ahead.
- [ ] Confirm the due-tomorrow reminder is sent once.

## 10. Overdue Reminder
- [ ] Set an expense past due.
- [ ] Confirm overdue reminders are sent only to pending members.
- [ ] Confirm reminders stop after the bill is confirmed.
- [ ] Confirm throttling prevents spam within the configured gap.

## Expected Firestore Paths
- `users/{userId}.fcmToken`
- `users/{userId}.fcmTokenUpdatedAt`
- `user_notifications/{userId}/notifications/{notifId}`
- `house_expenses/{expenseId}`
- `house_expenses/{expenseId}/participants/{userId}`

## Expected Cloud Function Behavior
- `sendPushOnUserNotification` relays notification docs to FCM.
- `processBillReminders` scans upcoming and overdue bills.
- Invalid tokens are removed when FCM returns token-not-registered errors.
