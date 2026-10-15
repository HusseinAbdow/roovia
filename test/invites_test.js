// Phase 2D.12 secure invitation backend tests (backend, NOT deployed).
//
// Exercises the ACTUAL joinByInvite transaction in functions/invites.js
// against the Firestore emulator through the Admin SDK (which is what the
// joinByInvite Callable in functions/index.js invokes). Identity forgery is
// structurally impossible: the service accepts no house ID, leader UID, or
// status inputs, and the wrapper derives the UID from Auth context.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-invite-test "node ../test/invites_test.js"
//
const admin = require('firebase-admin');
const assert = require('assert');

const invites = require('../functions/invites');

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'roovia-invite-test' });
}
const db = admin.firestore();

const houseDoc = (overrides = {}) => ({
  houseId: 'inv-house',
  name: 'Invite House',
  leaderId: 'inv-leader',
  members: ['inv-leader'],
  inviteCode: 'ABCDE2',
  discoverable: true,
  city: 'Bartin',
  district: 'Merkez',
  address: '1 Secret Street',
  rentTotal: 10000,
  electricityTotal: 500,
  waterTotal: 300,
  internetTotal: 400,
  maxMembers: 4,
  description: '',
  createdAt: new Date('2026-09-01T10:00:00Z'),
  ...overrides,
});

async function requestCount() {
  return (await db.collection('join_requests').get()).size;
}

async function expectCode(label, expectedCode, operation) {
  try {
    await operation;
  } catch (error) {
    assert.strictEqual(
      error && error.code,
      expectedCode,
      `${label}: expected ${expectedCode}, got ${error && error.code}`,
    );
    console.log(`denied as expected (${expectedCode}): ${label}`);
    return;
  }
  throw new assert.AssertionError({ message: `${label}: expected rejection, but succeeded` });
}

async function run() {
  await db.collection('houses').doc('inv-house').set(houseDoc());
  await db.collection('houses').doc('inv-full').set(
    houseDoc({ houseId: 'inv-full', inviteCode: 'FULL22', members: ['l1', 'm1'], maxMembers: 2 }),
  );
  await db.collection('houses').doc('inv-norm').set(
    houseDoc({ houseId: 'inv-norm', name: 'Norm House', inviteCode: 'NORM22', members: ['l2'] }),
  );

  // Valid invitation creates exactly one pending request with the client
  // schema ({houseId, userId, status, createdAt}) and a minimal response.
  const before = await requestCount();
  const result = await invites.transactJoinByInvite(db, 'inv-user', 'abcde2');
  assert.strictEqual(result.status, 'pending');
  assert.strictEqual(result.houseId, 'inv-house');
  assert.strictEqual(result.houseName, 'Invite House');
  assert.ok(typeof result.requestId === 'string' && result.requestId !== '');
  assert.deepStrictEqual(Object.keys(result).sort(), ['houseId', 'houseName', 'requestId', 'status']);
  assert.strictEqual(await requestCount(), before + 1);
  const stored = (await db.collection('join_requests').doc(result.requestId).get()).data();
  assert.deepStrictEqual(Object.keys(stored).sort(), ['createdAt', 'houseId', 'status', 'userId']);
  assert.strictEqual(stored.userId, 'inv-user');
  assert.strictEqual(stored.status, 'pending');
  assert.strictEqual(stored.houseId, 'inv-house');

  // Normalization matches the client (case/space/dash tolerant).
  const lower = await invites.transactJoinByInvite(db, 'inv-user2', '  norm22 ');
  assert.strictEqual(lower.houseId, 'inv-norm');

  // Invalid invitation (unknown code and deleted/missing house alike).
  await expectCode('unknown code', 'invalid-argument', invites.transactJoinByInvite(db, 'inv-u9', 'ZZZZZ9'));
  await expectCode('missing house', 'invalid-argument', invites.transactJoinByInvite(db, 'inv-u9', 'NOHOUSE'));

  // Invalid input shapes.
  for (const bad of ['', '   ', 'AB', 'A'.repeat(20), 'bad-code!', 'has space here xx', null, 123]) {
    await expectCode(
      `invalid input ${JSON.stringify(bad)}`,
      'invalid-argument',
      invites.transactJoinByInvite(db, 'inv-u9', bad),
    );
  }

  // Unauthenticated caller denied (wrapper derives UID from Auth context).
  await expectCode('unauthenticated', 'unauthenticated', invites.handleJoinByInvite(db, undefined, 'ABCDE2'));
  await expectCode('empty uid', 'unauthenticated', invites.handleJoinByInvite(db, '  ', 'ABCDE2'));

  // Existing member rejected.
  await expectCode(
    'existing member',
    'failed-precondition',
    invites.transactJoinByInvite(db, 'inv-leader', 'ABCDE2'),
  );

  // Membership in another house rejected (both legacy signals).
  await db.collection('users').doc('inv-elsewhere').set({ uid: 'inv-elsewhere', currentHouseId: 'other' });
  await expectCode(
    'currentHouseId membership',
    'failed-precondition',
    invites.transactJoinByInvite(db, 'inv-elsewhere', 'ABCDE2'),
  );
  await db.collection('houses').doc('inv-other').set(houseDoc({ houseId: 'inv-other', inviteCode: 'OTHER2', members: ['inv-roamer'] }));
  await expectCode(
    'array membership',
    'failed-precondition',
    invites.transactJoinByInvite(db, 'inv-roamer', 'ABCDE2'),
  );

  // Full house rejected.
  await expectCode('full house', 'failed-precondition', invites.transactJoinByInvite(db, 'inv-newbie', 'FULL22'));

  // Duplicate pending request rejected.
  await expectCode(
    'duplicate pending',
    'already-exists',
    invites.transactJoinByInvite(db, 'inv-user', 'ABCDE2'),
  );

  // Concurrent duplicate submissions create exactly one request.
  const countBefore = await requestCount();
  const settled = await Promise.allSettled([
    invites.transactJoinByInvite(db, 'inv-racer', 'ABCDE2'),
    invites.transactJoinByInvite(db, 'inv-racer', 'ABCDE2'),
  ]);
  assert.strictEqual(settled.filter((r) => r.status === 'fulfilled').length, 1);
  assert.strictEqual(settled.filter((r) => r.status === 'rejected').length, 1);
  assert.strictEqual(settled.find((r) => r.status === 'rejected').reason.code, 'already-exists');
  assert.strictEqual(await requestCount(), countBefore + 1);

  // Rejected operations created no stray records for strangers.
  assert.strictEqual((await db.collection('join_requests').where('userId', '==', 'inv-u9').get()).size, 0);
  assert.strictEqual((await db.collection('join_requests').where('userId', '==', 'inv-newbie').get()).size, 0);

  // Leader approval compatibility: the backend-created request carries the
  // exact client schema, so the existing leader flow applies unchanged.
  const pendingId = result.requestId;
  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(db.collection('join_requests').doc(pendingId));
    assert.strictEqual(requestSnap.data().status, 'pending');
    const houseRef = db.collection('houses').doc('inv-house');
    const houseSnap = await tx.get(houseRef);
    assert.strictEqual(houseSnap.data().leaderId, 'inv-leader');
    const members = [...houseSnap.data().members, 'inv-user'];
    tx.update(houseRef, { members });
    tx.update(db.collection('join_requests').doc(pendingId), { status: 'accepted' });
  });
  assert.strictEqual((await db.collection('join_requests').doc(pendingId).get()).data().status, 'accepted');
  assert.ok((await db.collection('houses').doc('inv-house').get()).data().members.includes('inv-user'));

  console.log('All invitation backend tests passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
