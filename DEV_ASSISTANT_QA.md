# Developer Q&A

## Assistant Behavior Rules

1. **Not a decision maker** — Provides suggestions only when relevant. Does NOT define project priorities.
2. **Respects current phase** — Current phase: **UX Consolidation** (Home Dashboard, Profile, Navigation). Do NOT suggest Phase 2 systems unless explicitly requested.
3. **Suggestions only when justified:**
   - Clear pattern issues detected
   - Scalability concerns identified
   - Bugs or architectural risks present
4. **Avoid unnecessary suggestions** — Do NOT suggest features outside scope or repeat known roadmap items.
5. **Questions only when needed:**
   - Data structure ambiguity exists
   - Decision impacts multiple systems
6. **Do not answer your own questions in this file.** Add the question, wait for the user's response, then update or replace it.
7. **Keep the file current.** If a question or suggestion is answered, resolved, or replaced, clear the old item first and add only the new active item.
8. **Keep suggestions concise and actionable.**

---

## Current Project Status (as of 2026-05-02)

### Phase 1: Core Foundation ✅ COMPLETE
- User authentication & profile system fully functional
- House creation, search, and membership workflows implemented
- Real-time group chat for houses operational
- Join request approval/rejection system working
- Dashboard with navigation and quick actions

### Current Phase: UX Consolidation 🎨
- Focus: Improving Home Dashboard, Profile System, and Navigation UX
- Goals: Refine visual hierarchy, enhance user flows, stabilize interactions

### Syntax Status
- **main.dart**: FIXED (no syntax errors)
- All services and screens: CLEAN

---

## Active Questions

- None right now. Add only new questions that still need the user's input.

## Active Answers

- If a question is answered in conversation or by editing this file, replace it with the updated answer and remove stale entries.

### Unread Message Debug Scan

**Q: When exactly is `markChatAsSeen` called?**
**A:** It is called in `initState()` inside [lib/screens/chat_screen.dart](lib/screens/chat_screen.dart), immediately after `_loadCurrentUser()`. It is not called from a `StreamBuilder`, and it is not tied to rebuilds.

**Q: What is the exact value of `lastSeenAt` when the user opens or leaves chat?**
**A:** When the user opens chat, `lastSeenAt` is written with `FieldValue.serverTimestamp()` through `markChatAsSeen`. When the user leaves chat, `lastSeenAt` is not updated. When a new message arrives, `lastSeenAt` does not change unless the user opens the chat again.

**Q: How is `createdAt` stored in messages?**
**A:** Messages are created with `FieldValue.serverTimestamp()` in [lib/services/chat_service.dart](lib/services/chat_service.dart). Yes, `createdAt` can be null initially in Firestore while the server timestamp resolves.

**Q: How does `getUnreadMessageCount` compare timestamps?**
**A:** It queries `house_chats/{houseId}/messages` and counts documents where `createdAt > lastSeenAt`. If `lastSeenAt` is null or missing, it currently treats the chat as fully unread and listens to all messages.

**Q: Can `lastSeenAt` be updated before messages load?**
**A:** Yes. `markChatAsSeen` runs in `initState()`, so the meta write can happen before the chat messages finish loading.

**Q: Where is the bug likely happening?**
**A:** The likely issue is timing around `FieldValue.serverTimestamp()` and the unread query. The `lastSeenAt` meta write and the message stream can race, and null/initial timestamps can make the unread count unstable or incorrect.

**Q: What debug logs should be added next?**
**A:** Log `lastSeenAt` when reading `house_user_meta`, and log each `message.createdAt` inside the unread count stream so the timestamp comparison can be verified directly.

---

## Development Notes

### Ready to Build
- Expense tracking backend (service layer already structured)
- Payment splitting logic
- Real-time expense notifications
- Filtering by estimated costs in search

### Important Constraints
- Do NOT add fake/inaccurate data
- Financial UI must label estimates clearly until real tracking is in place
- Keep backend calculations strict (sum monthly totals, divide by members)
- Profile/house search UI should remain stable through Phase 2 transition

### Gotchas to Watch
1. Chat Firestore rules use multiple field names for backwards compatibility (`members`, `memberIds`, `users`, `userIds`)
2. Per-person costs are computed at runtime, not stored—this is intentional for Phase 2 migration
3. Profile images use fallback avatars when Storage fails silently
4. Firebase is Android-only in firebase_options.dart (other platforms not configured)

---

## Suggestions

- Reminder: this section is for active suggestions only. When one is no longer relevant, remove it before adding a replacement.

### Current Phase Focus
1. **Home Dashboard UX** - Improve visual hierarchy and navigation clarity
2. **Profile System Refinement** - Enhance user experience for profile viewing/editing
3. **Navigation Stability** - Ensure smooth transitions between screens

### Deferred (Phase 2)
- **Expense tracking** — Scheduled for Phase 2
- **Chat notifications** — Scheduled for Phase 2
- **Payment tracking** — Scheduled for Phase 2
- **User ratings/reviews** — Scheduled for Phase 2

**Note:** Phase 2 features will only be considered after UI/UX stabilization is complete.

### Code Quality
- Architecture is solid; maintain current patterns
- Watch for redundant navigation logic as Dashboard evolves
- Firestore rules remain stable; no changes needed for current phase
