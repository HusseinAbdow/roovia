# Project context for ChatGPT

## Payment rejection red-screen crash (fixed 2026-09-26)

- Root cause: `_promptRejectionReason()` in `lib/screens/expense_detail_screen.dart`
  created a `TextEditingController` and disposed it immediately after `showDialog`
  returned. The dialog route is still animating out at that point, so its
  `TextField` re-registered a listener on the disposed controller during the
  exit animation (`_AnimatedState.didUpdateWidget` → `addListener` →
  `debugAssertNotDisposed`). Primary error: "A TextEditingController was used
  after being disposed" at `expense_detail_screen.dart:87` (the dialog
  `TextField`). The reported `_dependents.isEmpty` assertion and "build dirty
  widget in the wrong build scope" were secondary cascade errors. Verified with
  a real-device reproduction and the `flutter run` stack trace.
- Fix (UI-only, same file): the dialog is now a small `_RejectionReasonDialog`
  `StatefulWidget` that creates the controller in `initState`-style (`late
  final`) and disposes it in its own `dispose()` (after unmount). Reject/Approve
  callbacks also resolve `ScaffoldMessenger` only after `mounted` checks instead
  of capturing it across `await`. No change to the payment state machine,
  Firestore/Storage rules, Cloud Functions, models, or PDF-only upload.
- Verified: `flutter analyze` clean; `flutter test` 46 passed + 1 legacy
  `widget_test.dart` failure (unchanged baseline); on-device owner
  reject-with-reason (x2), dialog Cancel, reopen/reject-again, member rejected
  view + resubmit + awaiting-review, and owner approve all pass with no red
  screen; Firestore transitions confirmed
  (`paid+submitted` → `pending+rejected` → `paid+submitted` → `confirmed+approved`).
