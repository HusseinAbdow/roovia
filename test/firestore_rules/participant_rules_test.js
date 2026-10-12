// Firestore rules tests for the participants privacy + financial-integrity boundary.
//
// Read boundary (preserved):
//   - a normal member can read ONLY their own participant document
//   - a normal member CANNOT read another member's participant document
//   - the house leader can read ALL participant documents
//   - members CANNOT list the participants collection (rules are not filters)
//   - leader participant operations (update/create/delete) remain valid
//
// Financial-integrity boundary (Phase 2B):
//   The only legitimate ordinary-member write is the complete markAsPaid
//   submission payload from lib/services/expense_service.dart (pending -> paid
//   with the 9 submission keys). Members must NOT be able to smuggle
//   amountOwed / userId / confirmedAt / approval metadata alongside
//   status == "paid", downgrade confirmed -> paid, or rewrite paid -> paid.
//
// NOTE on the old bare {status: "paid"} test: status-only submission is NOT a
// legitimate supported operation. markAsPaid ALWAYS writes the full 9-key
// payload (status, paidAt, paymentProofStatus, paymentProofRevision,
// paymentProofNote, paymentProofs, paymentProofSubmittedAt,
// paymentProofReviewedAt, paymentProofReviewReason). The old test is replaced
// by the complete-payload test below plus an explicit bare-update denial test
// that documents the strict submission contract.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-rules-test "node ../test/firestore_rules/participant_rules_test.js"
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

const pendingParticipant = (uid) => ({
  userId: uid,
  amountOwed: 100,
  status: 'pending',
  paymentProofRevision: 0,
});

const paidParticipant = (uid, revision = 1) => ({
  userId: uid,
  amountOwed: 100,
  status: 'paid',
  paidAt: new Date('2026-09-10T10:00:00Z'),
  paymentProofStatus: 'submitted',
  paymentProofRevision: revision,
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

const expenseDoc = (houseId = 'house-1') => ({
  houseId,
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
});

/// Complete legitimate member submission payload, mirroring
/// ExpenseService.markAsPaid exactly (9 keys).
const legitSubmitPayload = (revision = 1, note = 'Bank transfer ref 123') => ({
  status: 'paid',
  paidAt: serverTimestamp(),
  paymentProofStatus: 'submitted',
  paymentProofRevision: revision,
  paymentProofNote: note,
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
  paymentProofSubmittedAt: serverTimestamp(),
  paymentProofReviewedAt: null,
  paymentProofReviewReason: null,
});

async function seedData(env) {
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    const house = {
      houseId: 'house-1',
      name: 'Test House',
      leaderId: LEADER,
      members: [LEADER, MEMBER_A, MEMBER_B],
      inviteCode: 'code',
      discoverable: true,
    };
    await setDoc(doc(admin, 'houses', 'house-1'), house);

    const fixtures = [
      // [expenseId, {uid: participantData}]
      ['expense-1', { [LEADER]: pendingParticipant(LEADER), [MEMBER_A]: pendingParticipant(MEMBER_A), [MEMBER_B]: pendingParticipant(MEMBER_B) }],
      ['expense-legit', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-amt', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-uid', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-forgestatus', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-forgeconf', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-forgereviewed', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-forgereason', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-downgrade', { [MEMBER_A]: confirmedParticipant(MEMBER_A) }],
      ['expense-rewrite', { [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-approve', { [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-reject', { [MEMBER_A]: paidParticipant(MEMBER_A) }],
      ['expense-resubmit', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
      ['expense-settle', { [MEMBER_A]: paidParticipant(MEMBER_A), [MEMBER_B]: paidParticipant(MEMBER_B) }],
      ['expense-bare', { [MEMBER_A]: pendingParticipant(MEMBER_A) }],
    ];

    for (const [expenseId, participants] of fixtures) {
      await setDoc(doc(admin, 'house_expenses', expenseId), expenseDoc());
      for (const [uid, data] of Object.entries(participants)) {
        await setDoc(doc(admin, 'house_expenses', expenseId, 'participants', uid), data);
      }
    }
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

const participantRef = (db, expenseId, uid) =>
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

    // 1. Member can read their own participant document.
    await assertSucceeds(getDoc(participantRef(memberA, 'expense-1', MEMBER_A)));

    // 2. Member CANNOT read another member's participant document.
    await assertFails(getDoc(participantRef(memberA, 'expense-1', MEMBER_B)));
    await assertFails(getDoc(participantRef(memberB, 'expense-1', MEMBER_A)));

    // 2b. Member CANNOT list the participants collection: rules are not
    // filters — an unfiltered LIST is denied because it could return other
    // members' participant documents. (Members must read their own document
    // by ID instead, which the UI does.)
    await assertFails(memberA.collection('house_expenses/expense-1/participants').get());

    // 3. Leader can read all participant documents (direct + collection).
    for (const uid of [LEADER, MEMBER_A, MEMBER_B]) {
      await assertSucceeds(getDoc(doc(leader, 'house_expenses/expense-1/participants', uid)));
    }
    const leaderView = await assertSucceeds(
      getDocs(collection(leader, 'house_expenses/expense-1/participants')),
    );
    assert.strictEqual(leaderView.size, 3);

    // 9. Legitimate member submission uses the complete real payload.
    await assertSucceeds(
      updateDoc(participantRef(memberA, 'expense-legit', MEMBER_A), legitSubmitPayload(1)),
    );

    // --- Unauthorized financial modifications (must ALL be denied) ---

    // 1. Modify amountOwed while setting status=paid.
    await expectDenied(
      'member modifies amountOwed with status=paid',
      updateDoc(participantRef(memberA, 'expense-amt', MEMBER_A), {
        status: 'paid',
        amountOwed: 1,
      }),
    );

    // 2. Modify userId while setting status=paid.
    await expectDenied(
      'member modifies userId with status=paid',
      updateDoc(participantRef(memberA, 'expense-uid', MEMBER_A), {
        status: 'paid',
        userId: MEMBER_B,
      }),
    );

    // 3. Forge paymentProofStatus=approved.
    await expectDenied(
      'member forges paymentProofStatus=approved',
      updateDoc(participantRef(memberA, 'expense-forgestatus', MEMBER_A), {
        status: 'paid',
        paymentProofStatus: 'approved',
      }),
    );

    // 4. Forge confirmedAt.
    await expectDenied(
      'member forges confirmedAt',
      updateDoc(participantRef(memberA, 'expense-forgeconf', MEMBER_A), {
        status: 'paid',
        confirmedAt: new Date('2026-09-12T10:00:00Z'),
      }),
    );

    // 5. Forge paymentProofReviewedAt.
    await expectDenied(
      'member forges paymentProofReviewedAt',
      updateDoc(participantRef(memberA, 'expense-forgereviewed', MEMBER_A), {
        status: 'paid',
        paymentProofReviewedAt: new Date('2026-09-12T10:00:00Z'),
      }),
    );

    // 6. Forge paymentProofReviewReason.
    await expectDenied(
      'member forges paymentProofReviewReason',
      updateDoc(participantRef(memberA, 'expense-forgereason', MEMBER_A), {
        status: 'paid',
        paymentProofReviewReason: 'verified by owner',
      }),
    );

    // 7. Downgrade confirmed -> paid.
    await expectDenied(
      'member downgrades confirmed->paid',
      updateDoc(participantRef(memberA, 'expense-downgrade', MEMBER_A), {
        status: 'paid',
      }),
    );

    // 8. Rewrite already-paid submission (paid -> paid with amount change).
    await expectDenied(
      'member rewrites paid->paid with amountOwed change',
      updateDoc(participantRef(memberA, 'expense-rewrite', MEMBER_A), {
        status: 'paid',
        amountOwed: 1,
      }),
    );

    // Bare status-only update is not a supported client operation and must
    // be denied under the strict submission contract.
    await expectDenied(
      'member bare status-only update',
      updateDoc(participantRef(memberA, 'expense-bare', MEMBER_A), {
        status: 'paid',
      }),
    );

    // 13. Member cannot modify another participant document.
    await assertFails(
      updateDoc(participantRef(memberA, 'expense-1', MEMBER_B), {
        status: 'paid',
      }),
    );

    // 6 (original). Member cannot write a non-"paid" status on their own document.
    await assertFails(
      updateDoc(participantRef(memberA, 'expense-1', MEMBER_A), {
        status: 'confirmed',
      }),
    );

    // 10. Owner approves a payment (paid -> confirmed review payload).
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-approve', MEMBER_A), {
        status: 'confirmed',
        confirmedAt: serverTimestamp(),
        paymentProofStatus: 'approved',
        paymentProofReviewedAt: serverTimestamp(),
        paymentProofReviewReason: null,
      }),
    );

    // 11. Owner rejects a payment (paid -> pending review payload).
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-reject', MEMBER_A), {
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

    // 12. Member resubmits after rejection (pending -> paid again).
    await assertSucceeds(
      updateDoc(participantRef(memberA, 'expense-resubmit', MEMBER_A), legitSubmitPayload(1)),
    );
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-resubmit', MEMBER_A), {
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
      updateDoc(
        participantRef(memberA, 'expense-resubmit', MEMBER_A),
        legitSubmitPayload(2, ''),
      ),
    );

    // 14. Owner settlement of paid participants remains permitted.
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-settle', MEMBER_A), {
        status: 'confirmed',
        confirmedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-settle', MEMBER_B), {
        status: 'confirmed',
        confirmedAt: serverTimestamp(),
      }),
    );

    // 7 (original). Leader participant operations remain valid.
    await assertSucceeds(
      updateDoc(participantRef(leader, 'expense-1', MEMBER_B), {
        status: 'confirmed',
      }),
    );
    await assertSucceeds(deleteDoc(participantRef(leader, 'expense-1', MEMBER_B)));
    await assertSucceeds(
      setDoc(participantRef(leader, 'expense-1', MEMBER_B), {
        userId: MEMBER_B,
        amountOwed: 100,
        status: 'pending',
      }),
    );

    // 8. Outsider (not in the house) cannot read other members' participants.
    // (Reading a document with their own UID is allowed by design, since a
    // participant document ID is a user ID.)
    await assertFails(getDoc(participantRef(outsider, 'expense-1', MEMBER_A)));

    if (permittedBypasses.length > 0) {
      console.log(
        `\nSECURITY HOLES OPEN (${permittedBypasses.length}):\n- ${permittedBypasses.join('\n- ')}`,
      );
    } else {
      console.log('All member financial-integrity attacks denied.');
    }
    assert.strictEqual(
      permittedBypasses.length,
      0,
      `Member bypasses permitted: ${permittedBypasses.join('; ')}`,
    );

    console.log('All participant rules tests passed.');
  } finally {
    await env.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
