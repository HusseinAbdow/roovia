// Phase 2D.13B public-profile backfill tests (emulator only).
//
// Seeds synthetic fixtures into the Firestore emulator and asserts the
// backfill in scripts/public_profile_backfill.js:
//   - creates only missing user_profiles/{uid} with allowlisted fields,
//   - never overwrites existing profiles,
//   - never copies private fields,
//   - skips (never invents) missing/invalid usernames,
//   - reports (never corrects) duplicate legacy usernames,
//   - is idempotent across repeated applies,
//   - performs zero writes in dry-run mode,
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

async function run() {
  await seed();

  const existingBefore = (await db.collection('user_profiles').doc('bb-existing').get()).data();
  assert.ok(existingBefore, 'existing fixture profile seeded');

  // 1. Dry-run by default: classifies everything, writes nothing.
  const dry = await backfill.runBackfill(db, { pageSize: 3, projectId: 'roovia-backfill-test' });
  assert.strictEqual(dry.mode, 'dry-run');
  assert.strictEqual(dry.counts.usersScanned, 9);
  assert.strictEqual(dry.counts.profilesPreExisting, 1);
  assert.strictEqual(dry.counts.planned, 5);
  assert.strictEqual(dry.counts.created, 0);
  assert.strictEqual(dry.counts.skippedExisting, 1);
  assert.strictEqual(dry.counts.skippedMissingUsername, 1);
  assert.strictEqual(dry.counts.skippedInvalidUsername, 2);
  assert.strictEqual(dry.counts.nameDefaulted, 1);
  assert.strictEqual(dry.counts.imageUrlDefaulted, 1);
  assert.strictEqual(dry.counts.duplicateGroupCount, 1);
  assert.strictEqual(dry.counts.duplicateMemberCount, 2);
  assert.strictEqual(dry.plannedAnons.length, 5);
  assert.strictEqual(dry.createdAnons.length, 0);
  assert.strictEqual(await countDocs('user_profiles'), 1, 'dry-run performs zero writes');
  serializedHasNoSecrets(dry);

  // Duplicate group is reported with fingerprints, never raw names.
  assert.strictEqual(dry.duplicateGroups.length, 1);
  const group = dry.duplicateGroups[0];
  assert.strictEqual(group.fingerprint, backfill.fingerprintUsername('bb_dupe'));
  assert.strictEqual(group.memberCount, 2);
  assert.deepStrictEqual(
    group.members.map((m) => m.anon).sort(),
    [backfill.anonUid('bb-dup1'), backfill.anonUid('bb-dup2')].sort(),
  );

  // Skip reasons use the documented vocabulary.
  const reasons = new Map(dry.skipped.map((entry) => [entry.anon, entry.reason]));
  assert.strictEqual(reasons.get(backfill.anonUid('bb-existing')), 'existing-profile');
  assert.strictEqual(reasons.get(backfill.anonUid('bb-nouser')), 'missing-username');
  assert.strictEqual(reasons.get(backfill.anonUid('bb-badname')), 'invalid-username');
  assert.strictEqual(reasons.get(backfill.anonUid('bb-upper')), 'invalid-username');

  // 2. Explicit --apply writes exactly the missing, valid profiles.
  const applied = await backfill.runBackfill(db, {
    apply: true,
    pageSize: 3,
    projectId: 'roovia-backfill-test',
  });
  assert.strictEqual(applied.mode, 'apply');
  assert.strictEqual(applied.counts.created, 5);
  assert.strictEqual(applied.createdAnons.length, 5);
  assert.strictEqual(await countDocs('user_profiles'), 6);
  serializedHasNoSecrets(applied);

  // 3. Created profiles contain ONLY allowlisted keys with correct values.
  const valid = (await db.collection('user_profiles').doc('bb-valid').get()).data();
  assert.deepStrictEqual(Object.keys(valid).sort(), [
    'bio',
    'name',
    'profileImageUrl',
    'uid',
    'updatedAt',
    'username',
  ]);
  assert.strictEqual(valid.uid, 'bb-valid');
  assert.strictEqual(valid.name, 'Ada Valid');
  assert.strictEqual(valid.username, 'bb_valid');
  assert.strictEqual(valid.profileImageUrl, 'https://cdn.example/ada.png');
  assert.strictEqual(valid.bio, '');
  assert.ok(valid.updatedAt, 'updatedAt set');
  for (const key of ['email', 'fcmToken', 'profileImageStoragePath', 'currentHouseId']) {
    assert.ok(!(key in valid), `private key ${key} must never be copied`);
  }

  const noname = (await db.collection('user_profiles').doc('bb-noname').get()).data();
  assert.strictEqual(noname.name, 'Member', 'missing name falls back to Member');
  assert.strictEqual(noname.username, 'bb_noname');

  const badurl = (await db.collection('user_profiles').doc('bb-badurl').get()).data();
  assert.strictEqual(badurl.profileImageUrl, '', 'overlong image URL falls back to empty');
  assert.strictEqual(badurl.username, 'bb_badurl');

  // Duplicates are preserved as-is (reported, not corrected).
  assert.strictEqual(
    (await db.collection('user_profiles').doc('bb-dup1').get()).data().username,
    'bb_dupe',
  );
  assert.strictEqual(
    (await db.collection('user_profiles').doc('bb-dup2').get()).data().username,
    'bb_dupe',
  );

  // Skipped records produced no profiles.
  for (const uid of ['bb-badname', 'bb-nouser', 'bb-upper']) {
    assert.strictEqual(
      (await db.collection('user_profiles').doc(uid).get()).exists,
      false,
      `${uid} must not gain a profile`,
    );
  }

  // 4. Existing profiles are never overwritten.
  assert.deepStrictEqual(
    (await db.collection('user_profiles').doc('bb-existing').get()).data(),
    existingBefore,
  );

  // 5. Second apply converges to zero writes (idempotent).
  const second = await backfill.runBackfill(db, {
    apply: true,
    pageSize: 100,
    projectId: 'roovia-backfill-test',
  });
  assert.strictEqual(second.counts.planned, 0);
  assert.strictEqual(second.counts.created, 0);
  assert.strictEqual(second.counts.skippedExisting, 6);
  assert.strictEqual(await countDocs('user_profiles'), 6);
  assert.deepStrictEqual(
    (await db.collection('user_profiles').doc('bb-existing').get()).data(),
    existingBefore,
  );

  // 6. CLI defaults to dry-run; --apply is explicit.
  assert.strictEqual(backfill.parseArgs([]).apply, false);
  assert.strictEqual(backfill.parseArgs(['--apply']).apply, true);

  // 7. Production and unsafe configurations are rejected (no reads performed).
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

  // 8. Source safety: create-only writes, emulator gate, explicit apply.
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
