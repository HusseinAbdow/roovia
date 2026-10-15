// Phase 2D.10 trusted house-public projection tests (backend, NOT deployed).
//
// Exercises the ACTUAL projection handler in functions/housePublic.js
// against the Firestore emulator through the Admin SDK (which is what the
// syncHousePublic trigger in functions/index.js invokes). The handler reads
// CURRENT committed house state inside a transaction and ignores event
// payloads, so ordering cases are driven with real document lifecycles:
// stale/redelivered triggers are plain re-invocations after the truth has
// moved on. The final section verifies via security rules that clients
// cannot write house_public directly.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-house-test "node ../test/house_public_test.js"
//
const admin = require('firebase-admin');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const { handleHouseWrite } = require('../functions/housePublic');

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'roovia-house-test' });
}
const db = admin.firestore();

const PUBLIC_KEYS = [
  'houseId',
  'name',
  'city',
  'district',
  'description',
  'rentTotal',
  'electricityTotal',
  'waterTotal',
  'internetTotal',
  'maxMembers',
  'memberCount',
  'discoverable',
  'updatedAt',
  'sourceUpdatedAt',
].sort();

const FORBIDDEN_KEYS = [
  'address',
  'inviteCode',
  'invite_code',
  'code',
  'members',
  'memberIds',
  'users',
  'userIds',
  'leaderId',
  'ownerId',
  'adminId',
  'leader_id',
  'chatName',
  'createdAt',
];

const privateHouse = (overrides = {}) => ({
  houseId: 'hp-1',
  name: 'Sun House',
  chatName: 'Sun House Chat',
  leaderId: 'leader-1',
  members: ['leader-1', 'member-a'],
  inviteCode: 'ABCDE',
  discoverable: true,
  city: 'Bartin',
  district: 'Merkez',
  address: '123 Secret Street',
  rentTotal: 12000,
  electricityTotal: 800,
  waterTotal: 400,
  internetTotal: 500,
  maxMembers: 4,
  description: 'Near campus',
  createdAt: new Date('2026-09-01T10:00:00Z'),
  updatedAt: new Date('2026-10-01T10:00:00Z'),
  ...overrides,
});

async function seedHouse(houseId, data) {
  await db.collection('houses').doc(houseId).set(data);
}

async function removeHouse(houseId) {
  await db.collection('houses').doc(houseId).delete();
}

async function readPublic(houseId) {
  return db.collection('house_public').doc(houseId).get();
}

function assertPublicOnly(data) {
  assert.deepStrictEqual(Object.keys(data).sort(), PUBLIC_KEYS);
  for (const key of FORBIDDEN_KEYS) {
    assert.strictEqual(data[key], undefined, `forbidden field ${key} leaked`);
  }
}

async function run() {
  // 1. Create publishes current summary.
  await seedHouse('hp-1', privateHouse());
  const created = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(created.status, 'created');
  const summary = (await readPublic('hp-1')).data();
  assert.strictEqual(summary.name, 'Sun House');
  assert.strictEqual(summary.city, 'Bartin');
  assert.strictEqual(summary.district, 'Merkez');
  assert.strictEqual(summary.memberCount, 2);
  assert.strictEqual(summary.maxMembers, 4);
  assert.strictEqual(summary.discoverable, true);

  // 2 + 12 (privacy). Exact allowlist, no private fields.
  assertPublicOnly(summary);

  // 3 + 8. Update publishes latest summary (name and costs).
  await seedHouse(
    'hp-1',
    privateHouse({ name: 'Sun House 2', rentTotal: 15000, updatedAt: new Date('2026-10-02T10:00:00Z') }),
  );
  const updated = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(updated.status, 'updated');
  const summary2 = (await readPublic('hp-1')).data();
  assert.strictEqual(summary2.name, 'Sun House 2');
  assert.strictEqual(summary2.rentTotal, 15000);
  assertPublicOnly(summary2);

  // 7. Member count changes reflected.
  await seedHouse(
    'hp-1',
    privateHouse({
      name: 'Sun House 2',
      members: ['leader-1', 'member-a', 'member-b'],
      updatedAt: new Date('2026-10-03T10:00:00Z'),
    }),
  );
  await handleHouseWrite(db, 'hp-1');
  assert.strictEqual((await readPublic('hp-1')).data().memberCount, 3);

  // 4. Delete removes summary; repeat is a no-op.
  await removeHouse('hp-1');
  const removed = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(removed.status, 'removed');
  assert.strictEqual((await readPublic('hp-1')).exists, false);
  const alreadyRemoved = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(alreadyRemoved.status, 'already-removed');

  // 5. discoverable=false removes summary; repeats stay hidden.
  await seedHouse('hp-1', privateHouse({ updatedAt: new Date('2026-10-04T10:00:00Z') }));
  await handleHouseWrite(db, 'hp-1');
  await seedHouse('hp-1', privateHouse({ discoverable: false }));
  const hidden = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(hidden.status, 'hidden');
  assert.strictEqual((await readPublic('hp-1')).exists, false);

  // 7 (second half). Redelivered old update events after discoverable=false
  // cannot restore the summary: the handler sees current truth, not payloads.
  for (let i = 0; i < 3; i += 1) {
    const replay = await handleHouseWrite(db, 'hp-1');
    assert.ok(replay.status === 'hidden' || replay.status === 'already-hidden');
  }
  assert.strictEqual((await readPublic('hp-1')).exists, false);

  // 6. discoverable=true restores summary.
  await seedHouse('hp-1', privateHouse({ discoverable: true }));
  const restored = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(restored.status, 'created');
  assert.strictEqual((await readPublic('hp-1')).exists, true);

  // 6 (second half). Old update event after deletion cannot recreate: with
  // the house gone, re-invocation converges to removed and stays gone.
  await removeHouse('hp-1');
  await handleHouseWrite(db, 'hp-1');
  const replayAfterDelete = await handleHouseWrite(db, 'hp-1');
  assert.strictEqual(replayAfterDelete.status, 'already-removed');
  assert.strictEqual((await readPublic('hp-1')).exists, false);

  // 8. Old delete event after house recreation cannot remove the current
  // valid summary: the handler republishes living truth instead.
  await seedHouse('hp-1', privateHouse({ name: 'Recreated', updatedAt: new Date('2026-10-06T10:00:00Z') }));
  const afterRecreate = await handleHouseWrite(db, 'hp-1');
  assert.ok(afterRecreate.status === 'created' || afterRecreate.status === 'updated');
  const recreated = (await readPublic('hp-1')).data();
  assert.strictEqual(recreated.name, 'Recreated');
  assertPublicOnly(recreated);

  // 9. Concurrent updates converge to current committed state.
  await seedHouse('hp-1', privateHouse({ name: 'Concurrent', members: ['a', 'b', 'c', 'd'] }));
  const concurrent = await Promise.all([
    handleHouseWrite(db, 'hp-1'),
    handleHouseWrite(db, 'hp-1'),
    handleHouseWrite(db, 'hp-1'),
  ]);
  for (const result of concurrent) {
    assert.ok(result.status === 'updated' || result.status === 'created');
  }
  const converged = (await readPublic('hp-1')).data();
  assert.strictEqual(converged.name, 'Concurrent');
  assert.strictEqual(converged.memberCount, 4);
  assertPublicOnly(converged);

  // 10. Repeated events are idempotent in effect.
  const repeatPayload = privateHouse({ houseId: 'hp-idem', updatedAt: new Date('2026-10-06T10:00:00Z') });
  await seedHouse('hp-idem', repeatPayload);
  const first = await handleHouseWrite(db, 'hp-idem');
  const repeat = await handleHouseWrite(db, 'hp-idem');
  assert.strictEqual(first.status, 'created');
  assert.strictEqual(repeat.status, 'updated');
  const idem = (await readPublic('hp-idem')).data();
  assert.strictEqual(idem.name, 'Sun House');
  assert.strictEqual(idem.memberCount, 2);
  assertPublicOnly(idem);

  // Malformed optional data handled safely (never publishes privates).
  await seedHouse('hp-malformed', {
    houseId: 'hp-malformed',
    name: 123,
    city: null,
    address: 'must not leak',
    inviteCode: 'must not leak',
    members: 'not-a-list',
    memberIds: ['x1'],
    leaderId: 'must not leak',
    rentTotal: { nested: 'object' },
    electricityTotal: '800',
    maxMembers: '4',
    discoverable: 'yes-unknown-value',
  });
  await handleHouseWrite(db, 'hp-malformed');
  const malformed = (await readPublic('hp-malformed')).data();
  assertPublicOnly(malformed);
  assert.strictEqual(malformed.name, '');
  assert.strictEqual(malformed.memberCount, 1);
  assert.strictEqual(malformed.rentTotal, 0);
  assert.strictEqual(malformed.electricityTotal, 800);
  assert.strictEqual(malformed.maxMembers, 4);
  assert.strictEqual(malformed.discoverable, true);

  // Legacy `area` key feeds district, as House.fromMap does.
  await seedHouse('hp-area', { houseId: 'hp-area', area: 'Kurucesme' });
  await handleHouseWrite(db, 'hp-area');
  assert.strictEqual((await readPublic('hp-area')).data().district, 'Kurucesme');

  // 11. Clients cannot directly write house_public (rules layer).
  const { initializeTestEnvironment, assertSucceeds, assertFails } = require(
    '@firebase/rules-unit-testing',
  );
  const {
    doc: tdoc,
    getDoc: tget,
    setDoc: tset,
    updateDoc: tupdate,
    deleteDoc: tdelete,
    getDocs: tlist,
    collection: tcoll,
  } = require('firebase/firestore');
  const RULES = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  const rulesEnv = await initializeTestEnvironment({
    projectId: 'roovia-house-test',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
  });
  try {
    await rulesEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await tset(tdoc(adminDb, 'house_public', 'hp-rules'), { houseId: 'hp-rules', name: 'Seed' });
    });
    const authed = rulesEnv.authenticatedContext('some-user').firestore();
    const anon = rulesEnv.unauthenticatedContext().firestore();
    await assertSucceeds(tget(tdoc(authed, 'house_public', 'hp-rules')));
    await assertSucceeds(tlist(tcoll(authed, 'house_public')));
    await assertFails(tget(tdoc(anon, 'house_public', 'hp-rules')));
    await assertFails(
      tset(tdoc(authed, 'house_public', 'hp-client'), { houseId: 'hp-client', name: 'Sneaky' }),
    );
    await assertFails(tupdate(tdoc(authed, 'house_public', 'hp-rules'), { name: 'Edited' }));
    await assertFails(tdelete(tdoc(authed, 'house_public', 'hp-rules')));
  } finally {
    await rulesEnv.cleanup();
  }
  console.log('All house-public projection tests passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
