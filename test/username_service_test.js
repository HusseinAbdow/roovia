// Phase 2D.5 trusted username service tests (backend, NOT deployed).
//
// Exercises the ACTUAL service transactions in functions/usernames.js
// against the Firestore emulator through the Admin SDK (which is what the
// Callables in functions/index.js invoke). No mocks: every assertion below
// commits or rejects a real transaction.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-username-test "node ../test/username_service_test.js"
//
const admin = require('firebase-admin');
const assert = require('assert');

const service = require('../functions/usernames');

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'roovia-username-test' });
}
const db = admin.firestore();

async function enableGate() {
  await db.doc(service.GATE_DOC_PATH).set({ enabled: true });
}

async function disableGate() {
  await db.doc(service.GATE_DOC_PATH).delete();
}

async function setGate(value) {
  await db.doc(service.GATE_DOC_PATH).set({ enabled: value });
}

async function readDoc(path) {
  return db.doc(path).get();
}

async function expectCode(label, expectedCode, operation) {
  try {
    await operation;
  } catch (error) {
    assert.strictEqual(
      error && error.code,
      expectedCode,
      `${label}: expected code ${expectedCode}, got ${error && error.code} (${error && error.message})`,
    );
    console.log(`denied as expected (${expectedCode}): ${label}`);
    return;
  }
  throw new assert.AssertionError({
    message: `${label}: expected rejection with ${expectedCode}, but succeeded`,
  });
}

async function run() {
  await enableGate();

  // Unauthenticated claim denied (callable handler derives UID from Auth).
  await expectCode(
    'unauthenticated claim',
    'unauthenticated',
    service.handleClaimUsername(db, undefined, 'nope_name'),
  );
  await expectCode(
    'unauthenticated change',
    'unauthenticated',
    service.handleChangeUsername(db, '', 'nope_name'),
  );

  // First valid claim creates the reservation plus profile mirrors.
  const first = await service.claimUsername(db, 'be-u1', 'be_first');
  assert.strictEqual(first.username, 'be_first');
  assert.strictEqual(first.status, 'claimed');
  assert.strictEqual((await readDoc('usernames/be_first')).data().uid, 'be-u1');
  assert.strictEqual((await readDoc('user_profiles/be-u1')).data().username, 'be_first');
  assert.strictEqual((await readDoc('users/be-u1')).data().username, 'be_first');

  // Normalization is consistent: surrounding case/whitespace canonicalizes.
  const normed = await service.claimUsername(db, 'be-u2', '  Be_Norm2 ');
  assert.strictEqual(normed.username, 'be_norm2');
  assert.strictEqual((await readDoc('usernames/be_norm2')).data().uid, 'be-u2');

  // Duplicate username denied; loser leaves no trace.
  await expectCode(
    'duplicate username claim',
    'already-exists',
    service.claimUsername(db, 'be-u3', 'be_first'),
  );
  assert.strictEqual((await readDoc('user_profiles/be-u3')).exists, false);
  assert.strictEqual((await readDoc('users/be-u3')).exists, false);

  // Cross-user claim denied (name owned by another UID).
  await expectCode(
    'cross-user claim',
    'already-exists',
    service.changeUsername(db, 'be-u3', 'be_first'),
  );

  // Invalid usernames denied.
  for (const bad of ['', 'ab', 'a'.repeat(21), 'bad-name!', 'has space', 123, null]) {
    await expectCode(
      `invalid username ${JSON.stringify(bad)}`,
      'invalid-argument',
      service.claimUsername(db, 'be-bad', bad),
    );
  }

  // Concurrent claims: exactly one owner, loser rolled back.
  const raceResults = await Promise.allSettled([
    service.claimUsername(db, 'be-r1', 'be_race'),
    service.claimUsername(db, 'be-r2', 'be_race'),
  ]);
  const raceWins = raceResults.filter((r) => r.status === 'fulfilled');
  const raceLosses = raceResults.filter((r) => r.status === 'rejected');
  assert.strictEqual(raceWins.length, 1, 'exactly one concurrent claim wins');
  assert.strictEqual(raceLosses.length, 1, 'exactly one concurrent claim loses');
  assert.strictEqual(raceLosses[0].reason && raceLosses[0].reason.code, 'already-exists');
  const raceOwner = (await readDoc('usernames/be_race')).data().uid;
  assert.ok(raceOwner === 'be-r1' || raceOwner === 'be-r2', 'single race owner');
  const raceLoser = raceOwner === 'be-r1' ? 'be-r2' : 'be-r1';
  assert.strictEqual((await readDoc(`user_profiles/${raceLoser}`)).exists, false);
  assert.strictEqual((await readDoc(`users/${raceLoser}`)).exists, false);
  console.log(`concurrent claims: owner=${raceOwner}, loser clean`);

  // Repeated identical claim is idempotent, not a duplicate write.
  const repeat = await service.claimUsername(db, 'be-u1', 'be_first');
  assert.strictEqual(repeat.status, 'already-owned');
  assert.strictEqual(repeat.username, 'be_first');

  // Valid rename releases the previous reservation atomically.
  const renamed = await service.changeUsername(db, 'be-u1', 'be_second');
  assert.strictEqual(renamed.username, 'be_second');
  assert.strictEqual(renamed.status, 'renamed');
  assert.strictEqual((await readDoc('usernames/be_first')).exists, false);
  assert.strictEqual((await readDoc('usernames/be_second')).data().uid, 'be-u1');
  assert.strictEqual((await readDoc('user_profiles/be-u1')).data().username, 'be_second');
  assert.strictEqual((await readDoc('users/be-u1')).data().username, 'be_second');

  // Rename to an occupied username denied with full rollback.
  await expectCode(
    'rename to occupied username',
    'already-exists',
    service.changeUsername(db, 'be-u1', 'be_norm2'),
  );
  assert.strictEqual((await readDoc('usernames/be_second')).data().uid, 'be-u1');
  assert.strictEqual((await readDoc('user_profiles/be-u1')).data().username, 'be_second');
  assert.strictEqual((await readDoc('usernames/be_norm2')).data().uid, 'be-u2');

  // Reclaiming a released username works for another user.
  const reclaim = await service.claimUsername(db, 'be-u4', 'be_first');
  assert.strictEqual(reclaim.status, 'claimed');
  assert.strictEqual((await readDoc('usernames/be_first')).data().uid, 'be-u4');

  // Legacy collision: an unmigrated users/* holder blocks new claims...
  await db.collection('users').doc('be-legacy').set({
    uid: 'be-legacy',
    name: 'Legacy User',
    email: 'legacy@example.com',
    username: 'be_legacy',
  });
  await expectCode(
    'legacy username collision',
    'already-exists',
    service.claimUsername(db, 'be-u5', 'be_legacy'),
  );
  assert.strictEqual((await readDoc('usernames/be_legacy')).exists, false);
  // ...but the legacy owner themselves can still claim it.
  const legacyOwn = await service.claimUsername(db, 'be-legacy', 'be_legacy');
  assert.strictEqual(legacyOwn.username, 'be_legacy');

  // Missing reservation with a legacy-named profile: rename adopts cleanly
  // (no stale claim to release, new claim created).
  await db.collection('user_profiles').doc('be-noclaim').set({
    uid: 'be-noclaim',
    name: 'No Claim',
    username: 'be_oldname',
    profileImageUrl: '',
    bio: '',
  });
  const adopted = await service.changeUsername(db, 'be-noclaim', 'be_newname');
  assert.strictEqual(adopted.username, 'be_newname');
  assert.strictEqual((await readDoc('usernames/be_newname')).data().uid, 'be-noclaim');

  // Legacy case 2: username lives ONLY in user_profiles (no users doc).
  await db.collection('user_profiles').doc('be-dironly').set({
    uid: 'be-dironly',
    name: 'Dir Only',
    username: 'be_dironly',
    profileImageUrl: '',
    bio: '',
  });
  await expectCode(
    'directory-only legacy collision',
    'already-exists',
    service.claimUsername(db, 'be-u6', 'be_dironly'),
  );
  assert.strictEqual((await readDoc('usernames/be_dironly')).exists, false);
  const dirOwn = await service.claimUsername(db, 'be-dironly', 'be_dironly');
  assert.strictEqual(dirOwn.username, 'be_dironly');

  // Legacy case 3: same username in BOTH collections for the SAME uid.
  await db.collection('users').doc('be-both').set({ uid: 'be-both', username: 'be_both' });
  await db.collection('user_profiles').doc('be-both').set({
    uid: 'be-both',
    name: 'Both Docs',
    username: 'be_both',
    profileImageUrl: '',
    bio: '',
  });
  const bothOwn = await service.claimUsername(db, 'be-both', 'be_both');
  assert.strictEqual(bothOwn.username, 'be_both');
  assert.strictEqual((await readDoc('usernames/be_both')).data().uid, 'be-both');

  // Legacy case 4: same username in both collections for DIFFERENT uids.
  await db.collection('users').doc('be-split-a').set({ uid: 'be-split-a', username: 'be_split' });
  await db.collection('user_profiles').doc('be-split-b').set({
    uid: 'be-split-b',
    name: 'Split B',
    username: 'be_split',
    profileImageUrl: '',
    bio: '',
  });
  await expectCode(
    'split-holder collision denies third party',
    'already-exists',
    service.claimUsername(db, 'be-u7', 'be_split'),
  );
  assert.strictEqual((await readDoc('usernames/be_split')).exists, false);

  // Legacy case 5: two legacy users share one username -> fail closed for
  // both (neither can be distinguished as the owner; needs audit triage).
  await db.collection('users').doc('be-dup1').set({ uid: 'be-dup1', username: 'be_dupe' });
  await db.collection('users').doc('be-dup2').set({ uid: 'be-dup2', username: 'be_dupe' });
  await expectCode(
    'shared legacy name denies first sharer',
    'already-exists',
    service.claimUsername(db, 'be-dup1', 'be_dupe'),
  );
  await expectCode(
    'shared legacy name denies second sharer',
    'already-exists',
    service.claimUsername(db, 'be-dup2', 'be_dupe'),
  );
  assert.strictEqual((await readDoc('usernames/be_dupe')).exists, false);

  // Legacy case 6: caller disagrees across mirrors (users=A, profiles=B).
  // A fresh claim converges both mirrors with no orphan reservations.
  await db.collection('users').doc('be-messy').set({ uid: 'be-messy', username: 'be_messya' });
  await db.collection('user_profiles').doc('be-messy').set({
    uid: 'be-messy',
    name: 'Messy',
    username: 'be_messyb',
    profileImageUrl: '',
    bio: '',
  });
  const converged = await service.claimUsername(db, 'be-messy', 'be_fresh');
  assert.strictEqual(converged.username, 'be_fresh');
  assert.strictEqual((await readDoc('users/be-messy')).data().username, 'be_fresh');
  assert.strictEqual((await readDoc('user_profiles/be-messy')).data().username, 'be_fresh');
  assert.strictEqual((await readDoc('usernames/be_messya')).exists, false);
  assert.strictEqual((await readDoc('usernames/be_messyb')).exists, false);

  // Mirror-name release: a caller-owned claim for the PRIVATE-doc name is
  // released on rename even when the directory points elsewhere.
  await db.doc('usernames/be_privname').set({ uid: 'be-priv', createdAt: new Date() });
  await db.collection('users').doc('be-priv').set({ uid: 'be-priv', username: 'be_privname' });
  await db.collection('user_profiles').doc('be-priv').set({
    uid: 'be-priv',
    name: 'Priv',
    username: 'be_dirname',
    profileImageUrl: '',
    bio: '',
  });
  const privRename = await service.changeUsername(db, 'be-priv', 'be_final');
  assert.strictEqual(privRename.status, 'renamed');
  assert.strictEqual((await readDoc('usernames/be_privname')).exists, false);
  assert.strictEqual((await readDoc('usernames/be_final')).data().uid, 'be-priv');
  assert.strictEqual((await readDoc('users/be-priv')).data().username, 'be_final');
  assert.strictEqual((await readDoc('user_profiles/be-priv')).data().username, 'be_final');

  // Legacy case 7: reservation exists but user/profile are missing
  // (orphaned claim). Strangers stay denied; the owner re-adopts cleanly
  // with mirrors recreated.
  await db.doc('usernames/be_orphan').set({ uid: 'be-ghost', createdAt: new Date() });
  await expectCode(
    'orphaned claim denies stranger',
    'already-exists',
    service.claimUsername(db, 'be-u8', 'be_orphan'),
  );
  const readopt = await service.claimUsername(db, 'be-ghost', 'be_orphan');
  assert.strictEqual(readopt.status, 'already-owned');
  assert.strictEqual((await readDoc('user_profiles/be-ghost')).data().username, 'be_orphan');
  assert.strictEqual((await readDoc('users/be-ghost')).data().username, 'be_orphan');

  // Truncation guard: bounded legacy scans fail closed instead of
  // approving on a partial sample. Four holders are still decided by the
  // ownership loop; five or more (a full result page) is rejected even
  // when every sampled holder looks harmless.
  for (let i = 0; i < 4; i += 1) {
    await db.collection('users').doc(`be-t4-${i}`).set({ uid: `be-t4-${i}`, username: 'be_trunc4' });
  }
  await expectCode(
    'four legacy holders denied by ownership',
    'already-exists',
    service.claimUsername(db, 'be-t4-new', 'be_trunc4'),
  );
  assert.strictEqual((await readDoc('usernames/be_trunc4')).exists, false);
  assert.strictEqual((await readDoc('user_profiles/be-t4-new')).exists, false);
  assert.strictEqual((await readDoc('users/be-t4-new')).exists, false);

  for (let i = 0; i < 5; i += 1) {
    await db.collection('users').doc(`be-t5-${i}`).set({ uid: `be-t5-${i}`, username: 'be_trunc5' });
  }
  await expectCode(
    'full legacy page fails closed',
    'failed-precondition',
    service.claimUsername(db, 'be-t5-new', 'be_trunc5'),
  );
  assert.strictEqual((await readDoc('usernames/be_trunc5')).exists, false);
  assert.strictEqual((await readDoc('user_profiles/be-t5-new')).exists, false);
  assert.strictEqual((await readDoc('users/be-t5-new')).exists, false);

  // Conflicting holders beyond the query limit stay protected: seven
  // holders can never all be sampled, so the claim is rejected and no
  // ownership change occurs.
  for (let i = 0; i < 7; i += 1) {
    await db.collection('users').doc(`be-t7-${i}`).set({ uid: `be-t7-${i}`, username: 'be_trunc7' });
  }
  await expectCode(
    'beyond-limit holders fail closed',
    'failed-precondition',
    service.claimUsername(db, 'be-t7-new', 'be_trunc7'),
  );
  assert.strictEqual((await readDoc('usernames/be_trunc7')).exists, false);
  assert.strictEqual((await readDoc('user_profiles/be-t7-new')).exists, false);
  assert.strictEqual((await readDoc('users/be-t7-new')).exists, false);

  // Both legacy collections are guarded: five holders in user_profiles
  // alone also fails closed.
  for (let i = 0; i < 5; i += 1) {
    await db.collection('user_profiles').doc(`be-tp5-${i}`).set({
      uid: `be-tp5-${i}`,
      name: `Trunc ${i}`,
      username: 'be_truncp5',
      profileImageUrl: '',
      bio: '',
    });
  }
  await expectCode(
    'directory-side full page fails closed',
    'failed-precondition',
    service.claimUsername(db, 'be-tp5-new', 'be_truncp5'),
  );
  assert.strictEqual((await readDoc('usernames/be_truncp5')).exists, false);

  // Split holdings stay caught by the ownership loop even though neither
  // collection reaches the truncation limit.
  for (let i = 0; i < 3; i += 1) {
    await db.collection('users').doc(`be-ts-${i}`).set({ uid: `be-ts-${i}`, username: 'be_truncs' });
    await db.collection('user_profiles').doc(`be-ts-p${i}`).set({
      uid: `be-ts-p${i}`,
      name: `Split ${i}`,
      username: 'be_truncs',
      profileImageUrl: '',
      bio: '',
    });
  }
  await expectCode(
    'split-collection holders denied',
    'already-exists',
    service.claimUsername(db, 'be-ts-new', 'be_truncs'),
  );
  assert.strictEqual((await readDoc('usernames/be_truncs')).exists, false);

  // Migration gate fail-closed: missing gate denies without writing.
  await disableGate();
  await expectCode(
    'gate missing denies claim',
    'failed-precondition',
    service.claimUsername(db, 'be-g1', 'be_gated'),
  );
  assert.strictEqual((await readDoc('usernames/be_gated')).exists, false);
  assert.strictEqual((await readDoc('user_profiles/be-g1')).exists, false);

  // Migration gate fail-closed: explicit false denies as well.
  await setGate(false);
  await expectCode(
    'gate false denies change',
    'failed-precondition',
    service.changeUsername(db, 'be-u1', 'be_third'),
  );
  assert.strictEqual((await readDoc('user_profiles/be-u1')).data().username, 'be_second');

  await enableGate();
  console.log('All username service tests passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
