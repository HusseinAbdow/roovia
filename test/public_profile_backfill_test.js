// Phase 2D.13E public-profile backfill tests (emulator only).
//
// Seeds synthetic fixtures into the Firestore emulator and asserts the
// backfill in scripts/public_profile_backfill.js:
//   - preserves valid legacy usernames verbatim,
//   - creates profiles with the unclaimed sentinel username '' for missing,
//     empty, and invalid legacy usernames (never skipping the user, never
//     inventing a name),
//   - reports (never corrects) duplicate legacy usernames,
//   - never overwrites existing profiles,
//   - never copies private fields,
//   - is idempotent across repeated applies,
//   - performs zero writes in dry-run mode,
//   - emits only rules-acceptable schemas (proven against the emulator with
//     the committed firestore.rules via an authenticated client probe),
//   - refuses production/unsafe configurations.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-backfill-test "node ../test/public_profile_backfill_test.js"
//
const admin = require('firebase-admin');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const backfill = require('../scripts/public_profile_backfill');

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'roovia-backfill-test' });
}
const db = admin.firestore();

const PRIVATE = {
  email: 'backfill.private@example.com',
  fcmToken: 'fcm-backfill-secret-xyz',
  storagePath: 'users/bb-valid/profile/avatar_1.jpg',
  houseId: 'house-secret-001',
};

const LONG_URL = `https://cdn.example/${'p'.repeat(2100)}.png`;

async function seed() {
  const users = db.collection('users');
  const profiles = db.collection('user_profiles');

  await users.doc('bb-valid').set({
    uid: 'bb-valid',
    name: 'Ada Valid',
    email: PRIVATE.email,
    username: 'bb_valid',
    profileImageUrl: 'https://cdn.example/ada.png',
    fcmToken: PRIVATE.fcmToken,
    profileImageStoragePath: PRIVATE.storagePath,
    currentHouseId: PRIVATE.houseId,
  });

  await users.doc('bb-existing').set({
    uid: 'bb-existing',
    name: 'Changed Since',
    email: PRIVATE.email,
    username: 'bb_changed',
    profileImageUrl: 'https://cdn.example/changed.png',
  });
  await profiles.doc('bb-existing').set({
    uid: 'bb-existing',
    name: 'Keep Me',
    username: 'bb_keep',
    profileImageUrl: 'https://cdn.example/keep.png',
    bio: 'held profile',
    updatedAt: new Date('2026-01-01T00:00:00Z'),
  });

  await users.doc('bb-noname').set({
    uid: 'bb-noname',
    name: '   ',
    email: PRIVATE.email,
    username: 'bb_noname',
  });

  await users.doc('bb-badname').set({
    uid: 'bb-badname',
    name: 'Bad',
    email: PRIVATE.email,
    username: 'Bad Name!',
  });

  await users.doc('bb-nouser').set({ uid: 'bb-nouser', name: 'No Username' });

  await users.doc('bb-empty').set({ uid: 'bb-empty', name: 'Empty Name', username: '' });

  await users.doc('bb-badurl').set({
    uid: 'bb-badurl',
    name: 'Eve Long',
    username: 'bb_badurl',
    profileImageUrl: LONG_URL,
  });

  await users.doc('bb-dup1').set({ uid: 'bb-dup1', name: 'Dupe One', username: 'bb_dupe' });
  await users.doc('bb-dup2').set({
    uid: 'bb-dup2',
    name: 'Dupe Two',
    username: 'bb_dupe',
    fcmToken: PRIVATE.fcmToken,
  });

  await users.doc('bb-upper').set({ uid: 'bb-upper', name: 'Upper', username: 'Bb_Upper' });
}

async function countDocs(collection) {
  return (await db.collection(collection).get()).size;
}

function serializedHasNoSecrets(report) {
  const serialized = JSON.stringify(report);
  for (const secret of [PRIVATE.email, PRIVATE.fcmToken, PRIVATE.storagePath, PRIVATE.houseId]) {
    assert.ok(!serialized.includes(secret), 'report must not contain private field values');
  }
  for (const raw of [
    'bb-valid',
    'bb-existing',
    'bb-noname',
    'bb-badname',
    'bb-nouser',
    'bb-empty',
    'bb-badurl',
    'bb-dup1',
    'bb-dup2',
    'bb-upper',
    'bb_valid',
    'bb_keep',
    'bb_changed',
    'bb_noname',
    'Bad Name!',
    'bb_dupe',
    'Bb_Upper',
    'Ada Valid',
    LONG_URL,
  ]) {
    assert.ok(!serialized.includes(raw), `report must not contain raw identifier ${raw}`);
  }
}

function assertAllowlistedProfile(data, uid) {
  assert.deepStrictEqual(
    Object.keys(data).sort(),
    ['bio', 'name', 'profileImageUrl', 'uid', 'updatedAt', 'username'],
    `${uid} profile must contain exactly the approved fields`,
  );
  assert.strictEqual(data.uid, uid);
  assert.ok(data.updatedAt && typeof data.updatedAt.toDate === 'function', 'updatedAt is a timestamp');
  for (const key of ['email', 'fcmToken', 'profileImageStoragePath', 'currentHouseId']) {
    assert.ok(!(key in data), `private key ${key} must never be copied`);
  }
}

async function run() {
  await seed();

  const existingBefore = (await db.collection('user_profiles').doc('bb-existing').get()).data();
  assert.ok(existingBefore, 'existing fixture profile seeded');

  // 10. Dry-run by default: classifies everything, writes nothing.
  const dry = await backfill.runBackfill(db, { pageSize: 3, projectId: 'roovia-backfill-test' });
  assert.strictEqual(dry.mode, 'dry-run');
  assert.strictEqual(dry.counts.usersScanned, 10);
  assert.strictEqual(dry.counts.profilesPreExisting, 1);
  assert.strictEqual(dry.counts.planned, 9);
  assert.strictEqual(dry.counts.created, 0);
  assert.strictEqual(dry.counts.skippedExisting, 1);
  assert.strictEqual(dry.counts.usernameUnclaimed, 4);
  assert.strictEqual(dry.counts.unclaimedMissingUsername, 2);
  assert.strictEqual(dry.counts.unclaimedInvalidUsername, 2);
  assert.strictEqual(dry.counts.nameDefaulted, 1);
  assert.strictEqual(dry.counts.imageUrlDefaulted, 1);
  assert.strictEqual(dry.counts.duplicateGroupCount, 1);
  assert.strictEqual(dry.counts.duplicateMemberCount, 2);
  assert.strictEqual(dry.plannedAnons.length, 9);
  assert.strictEqual(dry.createdAnons.length, 0);
  assert.strictEqual(await countDocs('user_profiles'), 1, 'dry-run performs zero writes');
  serializedHasNoSecrets(dry);

  // Duplicate group is reported with fingerprints, never raw names.
  // Ownership stays unresolved: both members remain planned, no reservation.
  assert.strictEqual(dry.duplicateGroups.length, 1);
  const group = dry.duplicateGroups[0];
  assert.strictEqual(group.fingerprint, backfill.fingerprintUsername('bb_dupe'));
  assert.strictEqual(group.memberCount, 2);
  assert.deepStrictEqual(
    group.members.map((m) => m.anon).sort(),
    [backfill.anonUid('bb-dup1'), backfill.anonUid('bb-dup2')].sort(),
  );

  // The report distinguishes missing, invalid, and duplicate usernames with
  // anonymized identifiers only: missing/invalid appear in usernameIssues,
  // duplicates appear in duplicateGroups, skips only cover existing profiles.
  const issues = new Map(dry.usernameIssues.map((entry) => [entry.anon, entry.issue]));
  assert.strictEqual(dry.usernameIssues.length, 4);
  assert.strictEqual(issues.get(backfill.anonUid('bb-nouser')), 'missing-username');
  assert.strictEqual(issues.get(backfill.anonUid('bb-empty')), 'missing-username');
  assert.strictEqual(issues.get(backfill.anonUid('bb-badname')), 'invalid-username');
  assert.strictEqual(issues.get(backfill.anonUid('bb-upper')), 'invalid-username');
  assert.ok(!issues.has(backfill.anonUid('bb-valid')), 'valid username needs no issue entry');
  assert.ok(!issues.has(backfill.anonUid('bb-dup1')), 'duplicates are group-reported, not issue-listed');
  assert.strictEqual(dry.skipped.length, 1);
  assert.strictEqual(dry.skipped[0].reason, 'existing-profile');

  // 11. Explicit --apply creates exactly the missing profiles.
  const applied = await backfill.runBackfill(db, {
    apply: true,
    pageSize: 3,
    projectId: 'roovia-backfill-test',
  });
  assert.strictEqual(applied.mode, 'apply');
  assert.strictEqual(applied.counts.created, 9);
  assert.strictEqual(applied.createdAnons.length, 9);
  assert.strictEqual(await countDocs('user_profiles'), 10);
  serializedHasNoSecrets(applied);

  // 1. Valid username preserved with the existing public-field behavior.
  const valid = (await db.collection('user_profiles').doc('bb-valid').get()).data();
  assertAllowlistedProfile(valid, 'bb-valid');
  assert.strictEqual(valid.name, 'Ada Valid');
  assert.strictEqual(valid.username, 'bb_valid');
  assert.strictEqual(valid.profileImageUrl, 'https://cdn.example/ada.png');
  assert.strictEqual(valid.bio, '');

  // 2/5. Missing and empty legacy usernames create profiles with username ''.
  for (const uid of ['bb-nouser', 'bb-empty']) {
    const profile = (await db.collection('user_profiles').doc(uid).get()).data();
    assertAllowlistedProfile(profile, uid);
    assert.strictEqual(profile.username, '', `${uid} carries the unclaimed sentinel`);
  }
  assert.strictEqual(
    (await db.collection('user_profiles').doc('bb-nouser').get()).data().name,
    'No Username',
    'display name preserved alongside sentinel',
  );

  // 3/4. Invalid uppercase and malformed usernames create profiles with
  // username '' (never lowercased, never repaired).
  const upper = (await db.collection('user_profiles').doc('bb-upper').get()).data();
  assertAllowlistedProfile(upper, 'bb-upper');
  assert.strictEqual(upper.username, '');
  assert.strictEqual(upper.name, 'Upper');
  const badname = (await db.collection('user_profiles').doc('bb-badname').get()).data();
  assertAllowlistedProfile(badname, 'bb-badname');
  assert.strictEqual(badname.username, '');
  assert.strictEqual(badname.name, 'Bad');

  // 6. Duplicate valid usernames are reported, preserved, and unresolved.
  assert.strictEqual(
    (await db.collection('user_profiles').doc('bb-dup1').get()).data().username,
    'bb_dupe',
  );
  assert.strictEqual(
    (await db.collection('user_profiles').doc('bb-dup2').get()).data().username,
    'bb_dupe',
  );
  assert.ok(
    (applied.notes.join(' ').includes('ownership') &&
      applied.notes.join(' ').includes('no reservations')) ||
      applied.notes.join(' ').includes('unresolved'),
    'report flags duplicates as ownership-unresolved without reservations',
  );

  // 7. Missing display name uses the safe fallback.
  const noname = (await db.collection('user_profiles').doc('bb-noname').get()).data();
  assert.strictEqual(noname.name, 'Member', 'missing name falls back to Member');
  assert.strictEqual(noname.username, 'bb_noname');

  // 8. Invalid avatar uses the safe fallback.
  const badurl = (await db.collection('user_profiles').doc('bb-badurl').get()).data();
  assert.strictEqual(badurl.profileImageUrl, '', 'overlong image URL falls back to empty');
  assert.strictEqual(badurl.username, 'bb_badurl');

  // 9. Existing public profiles are unchanged.
  assert.deepStrictEqual(
    (await db.collection('user_profiles').doc('bb-existing').get()).data(),
    existingBefore,
  );

  // 12. Second apply converges to zero writes (idempotent).
  const second = await backfill.runBackfill(db, {
    apply: true,
    pageSize: 100,
    projectId: 'roovia-backfill-test',
  });
  assert.strictEqual(second.counts.planned, 0);
  assert.strictEqual(second.counts.created, 0);
  assert.strictEqual(second.counts.usernameUnclaimed, 0);
  assert.strictEqual(second.counts.skippedExisting, 10);
  assert.strictEqual(await countDocs('user_profiles'), 10);
  assert.deepStrictEqual(
    (await db.collection('user_profiles').doc('bb-existing').get()).data(),
    existingBefore,
  );

  // 15. Emulator Firestore rules accept the generated schemas: an
  // authenticated owner can write the exact sentinel shape the backfill
  // emits, while an invalid username is still rejected by the same rules.
  const { initializeTestEnvironment, assertSucceeds, assertFails } = require(
    '@firebase/rules-unit-testing',
  );
  const { doc, setDoc } = require('firebase/firestore');
  const RULES = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  const env = await initializeTestEnvironment({
    projectId: 'roovia-backfill-test',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
  });
  try {
    const probe = env.authenticatedContext('bb-probe').firestore();
    await assertSucceeds(
      setDoc(doc(probe, 'user_profiles/bb-probe'), {
        uid: 'bb-probe',
        name: 'Probe',
        username: '',
        profileImageUrl: '',
        bio: '',
        updatedAt: new Date(),
      }),
    );
    const badProbe = env.authenticatedContext('bb-probe-bad').firestore();
    await assertFails(
      setDoc(doc(badProbe, 'user_profiles/bb-probe-bad'), {
        uid: 'bb-probe-bad',
        name: 'Probe Bad',
        username: 'Bad!',
        profileImageUrl: '',
        bio: '',
        updatedAt: new Date(),
      }),
    );
  } finally {
    await env.cleanup();
  }

  // CLI defaults to dry-run; --apply is explicit.
  assert.strictEqual(backfill.parseArgs([]).apply, false);
  assert.strictEqual(backfill.parseArgs(['--apply']).apply, true);

  // Production and unsafe configurations are rejected (no reads performed).
  await assert.rejects(
    backfill.runBackfill(db, { apply: true, projectId: 'roovia-app' }),
    /production project/,
    'production project rejected',
  );
  await assert.rejects(
    backfill.runBackfill(db, { apply: true, projectId: 'some-random-project' }),
    /does not look like an emulator/,
    'non-test project rejected',
  );
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {
    await assert.rejects(
      backfill.runBackfill(db, { apply: true, projectId: 'roovia-backfill-test' }),
      /FIRESTORE_EMULATOR_HOST/,
      'missing emulator host rejected',
    );
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = savedHost;
  }

  // Source safety: create-only writes, emulator gate, explicit apply, and no
  // reservation or username-service activation capability.
  // (Firestore doc writes use .doc(...).<op>(...); Map.set/add do not match.)
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'scripts', 'public_profile_backfill.js'),
    'utf8',
  );
  assert.ok(/\.doc\([^)]*\)\.create\(/.test(source), 'writes use create() only');
  for (const pattern of [
    /\.doc\([^)]*\)\.set\(/,
    /\.doc\([^)]*\)\.update\(/,
    /\.doc\([^)]*\)\.delete\(/,
    /FieldValue\.delete/,
    /runTransaction/,
    /deleteUser/,
    /usernames.*\.create\(/,
    /claimUsername/,
    /changeUsername/,
    /usernameService/,
  ]) {
    assert.ok(!pattern.test(source), `backfill source must not contain ${pattern}`);
  }
  assert.ok(source.includes('FIRESTORE_EMULATOR_HOST'), 'emulator gate present');
  assert.ok(source.includes('--apply'), 'explicit apply flag present');
  assert.ok(
    source.includes('PRIVATE_KEYS_NEVER_COPIED'),
    'private-field exclusion list present',
  );

  console.log('All public profile backfill tests passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
