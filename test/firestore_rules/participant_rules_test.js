// Firestore rules tests for the participants privacy boundary.
//
// Verifies that:
//   - a normal member can read ONLY their own participant document
//   - a normal member CANNOT read another member's participant document
//   - the house leader can read ALL participant documents
//   - a member can update their own participant document to status "paid"
//   - a member cannot update another participant document
//   - leader participant operations (update/create/delete) remain valid
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-rules-test "node ../test/firestore_rules/participant_rules_test.js"
//
const { initializeTestEnvironment, assertSucceeds, assertFails } = require(
  '@firebase/rules-unit-testing',
);
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } = require(
  'firebase/firestore',
);
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const RULES = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

const LEADER = 'leader-1';
const MEMBER_A = 'member-a';
const MEMBER_B = 'member-b';
const OUTSIDER = 'outsider-1';

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
    const expense = {
      houseId: 'house-1',
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
    };
    const participant = (uid) => ({
      userId: uid,
      amountOwed: 100,
      status: 'pending',
      paymentProofRevision: 0,
    });
    await setDoc(doc(admin, 'houses', 'house-1'), house);
    await setDoc(doc(admin, 'house_expenses', 'expense-1'), expense);
    for (const uid of [LEADER, MEMBER_A, MEMBER_B]) {
      await setDoc(doc(admin, 'house_expenses', 'expense-1', 'participants', uid), participant(uid));
    }
  });
}

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
    await assertSucceeds(getDoc(doc(memberA, 'house_expenses/expense-1/participants/member-a')));

    // 2. Member CANNOT read another member's participant document.
    await assertFails(getDoc(doc(memberA, 'house_expenses/expense-1/participants/member-b')));
    await assertFails(getDoc(doc(memberB, 'house_expenses/expense-1/participants/member-a')));

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

    // 4. Member can update their own participant to paid.
    await assertSucceeds(
      updateDoc(doc(memberA, 'house_expenses/expense-1/participants/member-a'), {
        status: 'paid',
      }),
    );

    // 5. Member cannot update another participant document.
    await assertFails(
      updateDoc(doc(memberA, 'house_expenses/expense-1/participants/member-b'), {
        status: 'paid',
      }),
    );

    // 6. Member cannot write a non-"paid" status on their own document.
    await assertFails(
      updateDoc(doc(memberA, 'house_expenses/expense-1/participants/member-a'), {
        status: 'confirmed',
      }),
    );

    // 7. Leader participant operations remain valid.
    await assertSucceeds(
      updateDoc(doc(leader, 'house_expenses/expense-1/participants/member-b'), {
        status: 'confirmed',
      }),
    );
    await assertSucceeds(deleteDoc(doc(leader, 'house_expenses/expense-1/participants/member-b')));
    await assertSucceeds(
      setDoc(doc(leader, 'house_expenses/expense-1/participants/member-b'), {
        userId: MEMBER_B,
        amountOwed: 100,
        status: 'pending',
      }),
    );

    // 8. Outsider (not in the house) cannot read other members' participants.
    // (Reading a document with their own UID is allowed by design, since a
    // participant document ID is a user ID.)
    await assertFails(getDoc(doc(outsider, 'house_expenses/expense-1/participants/member-a')));

    console.log('All participant rules tests passed.');
  } finally {
    await env.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
