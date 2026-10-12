// Firestore rules tests for the user_notifications authorization boundary.
//
// The only legitimate client producers are the seven ExpenseService flows
// (bill creation, payment submission, approval, settlement, rejection,
// batch confirmation, batch settlement). Every legitimate client document
// carries fromUserId == sender, a client-allowlisted type, a real expenseId
// whose houseId matches, and a sender/recipient relationship backed by the
// expense creator and participant documents. Server-only types
// (chat_message, bill_due_soon, bill_due_tomorrow, bill_overdue_reminder)
// are written via Admin SDK and must never be client-creatable.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-rules-test "node ../test/firestore_rules/notification_rules_test.js"
//
const { initializeTestEnvironment, assertSucceeds, assertFails } = require(
  '@firebase/rules-unit-testing',
);
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  serverTimestamp,
} = require('firebase/firestore');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const RULES = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

const LEADER = 'leader-1';
const MEMBER_A = 'member-a';
const MEMBER_B = 'member-b';
const OUTSIDER = 'outsider-1';
const HOUSE = 'house-1';

const pendingParticipant = (uid) => ({
  userId: uid,
  amountOwed: 100,
  status: 'pending',
  paymentProofRevision: 0,
});

const paidParticipant = (uid) => ({
  userId: uid,
  amountOwed: 100,
  status: 'paid',
  paidAt: new Date('2026-09-10T10:00:00Z'),
  paymentProofStatus: 'submitted',
  paymentProofRevision: 1,
  paymentProofNote: 'Bank transfer ref 123',
  paymentProofs: [
    {
      fileName: 'receipt.pdf',
      downloadUrl: 'https://example.com/receipt.pdf',
      storagePath: 'bills/expense-x/payments/member-a/proofs/1_0_1_receipt.pdf',
      mimeType: 'application/pdf',
      kind: 'pdf',
      sizeBytes: 1234,
      uploadedAt: new Date('2026-09-10T10:00:00Z'),
    },
  ],
  paymentProofSubmittedAt: new Date('2026-09-10T10:00:00Z'),
  paymentProofReviewedAt: null,
  paymentProofReviewReason: null,
});

const confirmedParticipant = (uid) => ({
  userId: uid,
  amountOwed: 100,
  status: 'confirmed',
  paidAt: new Date('2026-09-10T10:00:00Z'),
  confirmedAt: new Date('2026-09-12T10:00:00Z'),
  paymentProofStatus: 'approved',
  paymentProofRevision: 1,
  paymentProofReviewedAt: new Date('2026-09-12T10:00:00Z'),
  paymentProofReviewReason: null,
});

const rejectedParticipant = (uid) => ({
  userId: uid,
  amountOwed: 100,
  status: 'pending',
  paidAt: null,
  confirmedAt: null,
  paymentProofStatus: 'rejected',
  paymentProofRevision: 1,
  paymentProofNote: null,
  paymentProofs: [],
  paymentProofSubmittedAt: new Date('2026-09-10T10:00:00Z'),
  paymentProofReviewedAt: new Date('2026-09-12T10:00:00Z'),
  paymentProofReviewReason: 'Blurry image',
});

const expenseDoc = (overrides = {}) => ({
  houseId: HOUSE,
  title: 'Electricity',
  category: 'electricity',
  description: '',
  dueDate: new Date('2026-10-01'),
  reference: '',
  totalAmount: 300,
  perPersonAmount: 100,
  createdBy: LEADER,
  createdAt: new Date('2026-09-01'),
  status: 'pending',
  ...overrides,
});

/// Realistic client payloads mirroring ExpenseService exactly.
const billCreatedPayload = (expenseId, fromUserId) => ({
  title: 'New House Bill',
  body: 'Leader created Electricity • ₺300.00 due October 1',
  createdAt: serverTimestamp(),
  read: false,
  type: 'expense_request',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  billTitle: 'Electricity',
  billAmount: 300,
  dueDate: new Date('2026-10-01'),
});

const submittedPayload = (expenseId, fromUserId) => ({
  title: 'Payment proof uploaded',
  body: 'Member uploaded payment proof for Electricity',
  details: '1 proof file uploaded',
  createdAt: serverTimestamp(),
  read: false,
  type: 'payment_proof_submitted',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  userName: 'Member',
  billTitle: 'Electricity',
  billAmount: 100,
  paymentProofRevision: 1,
  paymentProofCount: 1,
  paymentProofNote: 'Bank transfer ref 123',
});

const approvedPayload = (expenseId, fromUserId) => ({
  title: 'Payment proof approved',
  body: 'Your payment proof for Electricity was approved',
  createdAt: serverTimestamp(),
  read: false,
  type: 'payment_proof_approved',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  userName: 'Member',
  billTitle: 'Electricity',
  billAmount: 100,
  paymentProofRevision: 1,
  paymentProofCount: 1,
});

const rejectedPayload = (expenseId, fromUserId) => ({
  title: 'Payment proof rejected',
  body: 'Your payment proof for Electricity was rejected: Blurry image',
  createdAt: serverTimestamp(),
  read: false,
  type: 'payment_proof_rejected',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  userName: 'Member',
  billTitle: 'Electricity',
  paymentProofRevision: 1,
  paymentProofReviewReason: 'Blurry image',
});

const confirmedPayload = (expenseId, fromUserId) => ({
  title: 'Payment confirmed',
  body: 'Your ₺100.00 payment for Electricity was confirmed',
  createdAt: serverTimestamp(),
  read: false,
  type: 'payment_confirmed',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  billTitle: 'Electricity',
  billAmount: 100,
});

const settledPayload = (expenseId, fromUserId) => ({
  title: 'Bill settled',
  body: 'Electricity is settled • ₺300.00 total',
  createdAt: serverTimestamp(),
  read: false,
  type: 'bill_paid',
  houseId: HOUSE,
  expenseId,
  fromUserId,
  billTitle: 'Electricity',
  billAmount: 300,
});

async function seedData(env) {
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'houses', HOUSE), {
      houseId: HOUSE,
      name: 'Test House',
      leaderId: LEADER,
      members: [LEADER, MEMBER_A, MEMBER_B],
      inviteCode: 'code',
      discoverable: true,
    });

    // [expenseId, expenseOverrides, {uid: participantData}]
    const fixtures = [
      ['expense-bill', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A), [MEMBER_B]: pendingParticipant(MEMBER_B) }],
      ['expense-sub', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-appr', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-rej', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-conf', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-set', { status: 'confirmed' }, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: confirmedParticipant(MEMBER_A), [MEMBER_B]: confirmedParticipant(MEMBER_B) }],
      ['expense-chat', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-arb', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-replay', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-spam1', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-spam2', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-spam3', {}, { [LEADER]: confirmedParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A) }],
    ];

    for (const [expenseId, overrides, participants] of fixtures) {
      await setDoc(doc(admin, 'house_expenses', expenseId), expenseDoc(overrides));
      for (const [uid, data] of Object.entries(participants)) {
        await setDoc(doc(admin, 'house_expenses', expenseId, 'participants', uid), data);
      }
    }

    // Admin-seeded inbox documents for privacy tests (bypass rules).
    await setDoc(doc(admin, 'user_notifications', MEMBER_A, 'notifications', 'seed-1'), {
      title: 'Seeded',
      body: 'seed',
      createdAt: new Date('2026-09-01'),
      read: false,
      type: 'expense_request',
      houseId: HOUSE,
      expenseId: 'expense-bill',
      fromUserId: LEADER,
    });
    await setDoc(doc(admin, 'user_notifications', MEMBER_B, 'notifications', 'seed-1'), {
      title: 'Seeded',
      body: 'seed',
      createdAt: new Date('2026-09-01'),
      read: false,
      type: 'expense_request',
      houseId: HOUSE,
      expenseId: 'expense-bill',
      fromUserId: LEADER,
    });
  });
}

// Non-aborting denial probe: records PERMITTED vs denied so a vulnerable
// ruleset reports every hole in one run instead of aborting at the first.
const permittedBypasses = [];
async function expectDenied(label, operation) {
  try {
    await operation;
    permittedBypasses.push(label);
    console.log(`VULNERABLE (permitted): ${label}`);
  } catch (error) {
    console.log(`denied (safe): ${label}`);
  }
}

const inboxDoc = (db, uid, nid) => doc(db, `user_notifications/${uid}/notifications/${nid}`);
const participantDoc = (db, expenseId, uid) =>
  doc(db, `house_expenses/${expenseId}/participants/${uid}`);

async function run() {
  const env = await initializeTestEnvironment({
    projectId: 'roovia-rules-test',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
  });

  try {
    await seedData(env);

    const memberA = env.authenticatedContext(MEMBER_A).firestore();
    const memberB = env.authenticatedContext(MEMBER_B).firestore();
    const leader = env.authenticatedContext(LEADER).firestore();
    const outsider = env.authenticatedContext(OUTSIDER).firestore();

    // --- Legitimate client notifications (must ALL succeed) ---

    // Bill creation: owner notifies a participant member.
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-bill_member-a_bill_created'),
        billCreatedPayload('expense-bill', LEADER),
      ),
    );

    // Payment submission: payer notifies the expense creator.
    await assertSucceeds(
      setDoc(
        inboxDoc(memberA, LEADER, 'expense-sub_member-a_payment_proof_submitted_1'),
        submittedPayload('expense-sub', MEMBER_A),
      ),
    );

    // Owner approval: creator notifies the participant. Mirrors the real
    // flow ordering: the participant approve-update commits first, so the
    // state pins observe the post-transition document.
    await assertSucceeds(
      updateDoc(participantDoc(leader, 'expense-appr', MEMBER_A), {
        status: 'confirmed',
        confirmedAt: serverTimestamp(),
        paymentProofStatus: 'approved',
        paymentProofReviewedAt: serverTimestamp(),
        paymentProofReviewReason: null,
      }),
    );
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-appr_member-a_payment_proof_approved_1'),
        approvedPayload('expense-appr', LEADER),
      ),
    );

    // Owner rejection: creator notifies the participant. Same ordering:
    // the reject-update commits first.
    await assertSucceeds(
      updateDoc(participantDoc(leader, 'expense-rej', MEMBER_A), {
        status: 'pending',
        paidAt: null,
        confirmedAt: null,
        paymentProofStatus: 'rejected',
        paymentProofReviewedAt: serverTimestamp(),
        paymentProofReviewReason: 'Blurry image',
        paymentProofNote: null,
        paymentProofs: [],
      }),
    );
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-rej_member-a_payment_proof_rejected_1'),
        rejectedPayload('expense-rej', LEADER),
      ),
    );

    // Batch payment confirmation: creator notifies the participant after
    // the confirm-update commits.
    await assertSucceeds(
      updateDoc(participantDoc(leader, 'expense-conf', MEMBER_A), {
        status: 'confirmed',
        confirmedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-conf_member-a_payment_confirmed_batch'),
        confirmedPayload('expense-conf', LEADER),
      ),
    );

    // Bill settlement: creator notifies a participant of a confirmed bill.
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-set_member-a_bill_settled'),
        settledPayload('expense-set', LEADER),
      ),
    );

    // --- Unauthorized operations (must ALL be denied) ---

    // 1. Arbitrary recipient: leader targets an outsider who is not a
    // participant of the expense.
    await expectDenied(
      'notification to arbitrary recipient',
      setDoc(
        inboxDoc(leader, OUTSIDER, 'expense-arb_outsider-1_bill_created'),
        billCreatedPayload('expense-arb', LEADER),
      ),
    );

    // 2. Forged sender: the creator signs as someone else. Every other
    // envelope field is valid, isolating the fromUserId pin. Uses a fresh
    // document ID so the write evaluates as create (a set() on an existing
    // ID would evaluate as update, which is owner-only by design).
    await expectDenied(
      'notification with forged fromUserId',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-bill_member-a_bill_created_sender'), {
        ...billCreatedPayload('expense-bill', MEMBER_A),
      }),
    );

    // 3. Fake payment approval by a non-owner.
    await expectDenied(
      'fake payment approval by non-owner',
      setDoc(
        inboxDoc(memberA, MEMBER_B, 'expense-bill_member-b_payment_proof_approved_1'),
        approvedPayload('expense-bill', MEMBER_A),
      ),
    );

    // 4. Wrong-house expense reference (fresh ID: create path).
    await expectDenied(
      'notification with wrong-house reference',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-bill_member-a_bill_created_house'), {
        ...billCreatedPayload('expense-bill', LEADER),
        houseId: 'house-2',
      }),
    );

    // 5. Missing expense reference.
    await expectDenied(
      'notification with missing expense reference',
      setDoc(inboxDoc(leader, MEMBER_A, 'no-such-expense_member-a_bill_created'), {
        ...billCreatedPayload('no-such-expense', LEADER),
        expenseId: 'no-such-expense',
      }),
    );

    // 6. Client-created server-only chat notification.
    await expectDenied(
      'client-created chat_message notification',
      setDoc(inboxDoc(memberA, MEMBER_B, 'house-1_msg-1_member-b'), {
        title: 'New chat message',
        body: 'Member: hello',
        createdAt: serverTimestamp(),
        read: false,
        type: 'chat_message',
        houseId: HOUSE,
        expenseId: 'expense-chat',
        fromUserId: MEMBER_A,
        messageId: 'msg-1',
        senderId: MEMBER_A,
        senderName: 'Member',
        messageText: 'hello',
      }),
    );

    // 7. Client-created server-only reminder notification.
    await expectDenied(
      'client-created reminder notification',
      setDoc(inboxDoc(memberA, MEMBER_B, 'expense-chat_member-b_bill_due_soon'), {
        title: 'Bill due soon',
        body: 'Electricity bill is due in 3 days.',
        createdAt: serverTimestamp(),
        read: false,
        type: 'bill_due_soon',
        houseId: HOUSE,
        expenseId: 'expense-chat',
        fromUserId: MEMBER_A,
      }),
    );

    // 8. Unknown notification type.
    await expectDenied(
      'notification with unknown type',
      setDoc(inboxDoc(memberA, MEMBER_B, 'expense-chat_member-b_lottery'), {
        title: 'You won',
        body: 'Claim now',
        createdAt: serverTimestamp(),
        read: false,
        type: 'lottery_win',
        houseId: HOUSE,
        expenseId: 'expense-chat',
        fromUserId: MEMBER_A,
      }),
    );

    // 9. Forged delivery metadata (FCM relay markers are server-only).
    // Fresh ID so the write evaluates as create.
    await expectDenied(
      'notification with forged pushSentAt',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-bill_member-a_bill_created_meta'), {
        ...billCreatedPayload('expense-bill', LEADER),
        pushSentAt: new Date('2026-09-01'),
      }),
    );

    // 10. Arbitrary document ID outside the deterministic format.
    await expectDenied(
      'notification with arbitrary document ID',
      setDoc(
        inboxDoc(leader, MEMBER_A, 'totally-arbitrary-id'),
        billCreatedPayload('expense-bill', LEADER),
      ),
    );

    // 11. Forged financial value (billAmount differs from the expense).
    // Fresh ID so the write evaluates as create.
    await expectDenied(
      'notification with forged billAmount',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-bill_member-a_bill_created_amount'), {
        ...billCreatedPayload('expense-bill', LEADER),
        billAmount: 1,
      }),
    );

    // --- Notification ID / replay behavior (spam surface) ---
    //
    // Legitimate IDs are exactly `{expenseId}_{userId}_{kind}` with the
    // kind suffixes in ExpenseService._notificationDocId call sites. These
    // probes measure what ID variation the rules tolerate; every extra
    // accepted ID is an extra push an authorized sender can emit.

    // 1. Same expense+type under a second ID (first ID is legitimate).
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-spam1_member-a_bill_created'),
        billCreatedPayload('expense-spam1', LEADER),
      ),
    );
    await expectDenied(
      'second notification ID for same expense+type',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-spam1_member-a_bill_created_again'), {
        ...billCreatedPayload('expense-spam1', LEADER),
      }),
    );

    // 2. Same payment revision under multiple IDs.
    await assertSucceeds(
      setDoc(
        inboxDoc(memberA, LEADER, 'expense-spam2_member-a_payment_proof_submitted_1'),
        submittedPayload('expense-spam2', MEMBER_A),
      ),
    );
    await expectDenied(
      'same revision under a second notification ID',
      setDoc(
        inboxDoc(memberA, LEADER, 'expense-spam2_member-a_payment_proof_submitted_1_copy'),
        submittedPayload('expense-spam2', MEMBER_A),
      ),
    );

    // 3. Recreation after the recipient deletes the original. The recipient
    // deleted their own copy, so a re-notify is treated as legitimate and
    // is expected to succeed (accepted residual, not a bypass).
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-spam3_member-a_bill_created'),
        billCreatedPayload('expense-spam3', LEADER),
      ),
    );
    await assertSucceeds(deleteDoc(inboxDoc(memberA, MEMBER_A, 'expense-spam3_member-a_bill_created')));
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-spam3_member-a_bill_created'),
        billCreatedPayload('expense-spam3', LEADER),
      ),
    );

    // 4. Another participant's ID in the filename suffix (delivery still
    // targets this inbox; the suffix is cosmetic, but must be exact).
    await expectDenied(
      'notification with another participant ID in suffix',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-spam1_member-b_bill_created'), {
        ...billCreatedPayload('expense-spam1', LEADER),
      }),
    );

    // 5. Valid-looking notification with an unrelated suffix.
    await expectDenied(
      'notification with unrelated suffix',
      setDoc(inboxDoc(leader, MEMBER_A, 'expense-spam1_garbage_suffix'), {
        ...billCreatedPayload('expense-spam1', LEADER),
      }),
    );

    // --- Inbox privacy (pre-existing behavior, regression guards) ---

    // Cross-user inbox reads are denied.
    await assertFails(getDoc(inboxDoc(memberA, MEMBER_B, 'seed-1')));
    // Cross-user notification modifications are denied.
    await assertFails(updateDoc(inboxDoc(memberA, MEMBER_B, 'seed-1'), { read: true }));

    // Sender cannot rewrite a delivered notification (update is owner-only).
    await assertSucceeds(
      setDoc(
        inboxDoc(leader, MEMBER_A, 'expense-replay_member-a_bill_created'),
        billCreatedPayload('expense-replay', LEADER),
      ),
    );
    await assertFails(
      updateDoc(inboxDoc(leader, MEMBER_A, 'expense-replay_member-a_bill_created'), {
        body: 'edited after delivery',
      }),
    );

    // Own inbox read/list succeed.
    await assertSucceeds(getDoc(inboxDoc(memberA, MEMBER_A, 'seed-1')));
    await assertSucceeds(
      getDocs(collection(memberA, 'user_notifications/member-a/notifications')),
    );

    // Own read/unread updates succeed; own deletion succeeds.
    await assertSucceeds(updateDoc(inboxDoc(memberA, MEMBER_A, 'seed-1'), { read: true }));
    await assertSucceeds(deleteDoc(inboxDoc(memberA, MEMBER_A, 'seed-1')));

    if (permittedBypasses.length > 0) {
      console.log(
        `\nSECURITY HOLES OPEN (${permittedBypasses.length}):\n- ${permittedBypasses.join('\n- ')}`,
      );
    } else {
      console.log('All notification authorization attacks denied.');
    }
    assert.strictEqual(
      permittedBypasses.length,
      0,
      `Notification bypasses permitted: ${permittedBypasses.join('; ')}`,
    );

    console.log('All notification rules tests passed.');
  } finally {
    await env.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
