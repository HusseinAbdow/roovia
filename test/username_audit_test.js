// Phase 2D.7 username audit tool tests (emulator only, read-only).
//
// Seeds synthetic fixtures into the Firestore (+ Auth) emulators and asserts
// the audit in scripts/username_audit.js classifies every migration case
// without writing anything and without leaking private data.
//
// Run with the Firestore + Auth emulators:
//   cd functions && npx firebase-tools emulators:exec --only firestore,auth \
//     --project roovia-audit-test "node ../test/username_audit_test.js"
//
const admin = require('firebase-admin');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const audit = require('../scripts/username_audit');

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: 'roovia-audit-test' });
}
const db = admin.firestore();
const auth = admin.auth();

const PRIVATE = {
  email: 'private.person@example.com',
  fcmToken: 'fcm-secret-token-abc123',
  address: '123 Secret Street, Hidden City',
};

async function seed() {
  const users = db.collection('users');
  const profiles = db.collection('user_profiles');
  const claims = db.collection('usernames');

  await users.doc('au-clean').set({
    uid: 'au-clean',
    name: 'Clean',
    email: PRIVATE.email,
    username: 'au_clean',
  });
  await profiles.doc('au-clean').set({
    uid: 'au-clean',
    name: 'Clean',
    username: 'au_clean',
    profileImageUrl: '',
    bio: '',
  });
  await claims.doc('au_clean').set({ uid: 'au-clean', createdAt: new Date() });

  await users.doc('au-missing').set({ uid: 'au-missing', name: 'No Name' });

  await users.doc('au-invalid').set({
    uid: 'au-invalid',
    name: 'Invalid',
    email: PRIVATE.email,
    username: 'Bad Name!',
  });

  await users.doc('au-dup1').set({ uid: 'au-dup1', username: 'au_dupe' });
  await users.doc('au-dup2').set({
    uid: 'au-dup2',
    username: 'au_dupe',
    fcmToken: PRIVATE.fcmToken,
  });

  await users.doc('au-case1').set({ uid: 'au-case1', username: 'Au_Case' });
  await users.doc('au-case2').set({ uid: 'au-case2', username: 'au_case' });

  await users.doc('au-mirror').set({ uid: 'au-mirror', username: 'au_m1' });
  await profiles.doc('au-mirror').set({
    uid: 'au-mirror',
    name: 'Mirror',
    username: 'au_m2',
    profileImageUrl: '',
    bio: '',
  });

  await users.doc('au-noprof').set({ uid: 'au-noprof', username: 'au_noprof' });

  await users.doc('au-noclaim').set({ uid: 'au-noclaim', username: 'au_noclaim' });
  await profiles.doc('au-noclaim').set({
    uid: 'au-noclaim',
    name: 'No Claim',
    username: 'au_noclaim',
    profileImageUrl: '',
    bio: '',
  });

  await claims.doc('au_orphan').set({ uid: 'au-ghost', createdAt: new Date() });

  await users.doc('au-owner').set({ uid: 'au-owner', username: 'au_ownername' });
  await profiles.doc('au-owner').set({
    uid: 'au-owner',
    name: 'Owner',
    username: 'au_ownername',
    profileImageUrl: '',
    bio: '',
  });
  await claims.doc('au_ownername').set({ uid: 'au-owner', createdAt: new Date() });
  await claims.doc('au_contested').set({ uid: 'au-owner', createdAt: new Date() });
  await users.doc('au-squatter').set({
    uid: 'au-squatter',
    username: 'au_contested',
    address: PRIVATE.address,
  });
  await profiles.doc('au-squatter').set({
    uid: 'au-squatter',
    name: 'Squatter',
    username: 'au_contested',
    profileImageUrl: '',
    bio: '',
  });

  await users.doc('au-noauth').set({ uid: 'au-noauth', username: 'au_noauth' });
  await profiles.doc('au-noauth').set({
    uid: 'au-noauth',
    name: 'No Auth',
    username: 'au_noauth',
    profileImageUrl: '',
    bio: '',
  });
  await claims.doc('au_noauth').set({ uid: 'au-noauth', createdAt: new Date() });

  for (let i = 0; i < 12; i += 1) {
    const id = `au-page-${String(i).padStart(2, '0')}`;
    const name = `au_page_${i}`;
    await users.doc(id).set({ uid: id, username: name });
    await profiles.doc(id).set({ uid: id, name: `Page ${i}`, username: name, profileImageUrl: '', bio: '' });
    await claims.doc(name).set({ uid: id, createdAt: new Date() });
  }

  // Duplicate-completeness stress: 8 accounts share one canonical username
  // (exceeds the backend legacy-guard limit(5) sample size on purpose).
  for (let i = 0; i < 8; i += 1) {
    await users.doc(`au-oct${i}`).set({ uid: `au-oct${i}`, username: 'au_octet' });
  }

  for (const uid of [
    'au-clean',
    'au-missing',
    'au-invalid',
    'au-dup1',
    'au-dup2',
    'au-case1',
    'au-case2',
    'au-mirror',
    'au-noprof',
    'au-noclaim',
    'au-owner',
    'au-squatter',
    ...Array.from({ length: 12 }, (_, i) => `au-page-${String(i).padStart(2, '0')}`),
    ...Array.from({ length: 8 }, (_, i) => `au-oct${i}`),
  ]) {
    await auth.createUser({ uid, email: `${uid}@example.com`, password: 'password123' });
  }
}

async function countDocs(collection) {
  const snapshot = await db.collection(collection).get();
  return snapshot.size;
}

async function run() {
  await seed();

  const usersBefore = await countDocs('users');
  const profilesBefore = await countDocs('user_profiles');
  const claimsBefore = await countDocs('usernames');
  const canaryBefore = (await db.collection('users').doc('au-clean').get()).data();

  const report = await audit.runAudit(db, { auth, pageSize: 5, projectId: 'roovia-audit-test' });

  // Pagination across multiple pages reaches every account.
  assert.strictEqual(report.counts.totalAccounts, 34);
  assert.strictEqual(report.counts.clean, 13);
  assert.strictEqual(report.counts.missingUsername, 2);
  assert.strictEqual(report.counts.invalidUsername, 1);
  assert.strictEqual(report.counts.duplicateUsername, 12);
  assert.strictEqual(report.counts.caseVariantGroups, 1);
  assert.strictEqual(report.counts.mirrorMismatch, 1);
  assert.strictEqual(report.counts.missingPublicProfile, 14);
  assert.strictEqual(report.counts.missingReservation, 15);
  assert.strictEqual(report.counts.orphanReservation, 2);
  assert.strictEqual(report.counts.wrongOwnerReservation, 1);
  assert.strictEqual(report.counts.authLessAccount, 2);
  assert.strictEqual(report.authStatus, 'checked');

  // Duplicate groups carry fingerprints, never raw names.
  assert.strictEqual(report.duplicateGroups.length, 3);
  for (const group of report.duplicateGroups) {
    assert.strictEqual(typeof group.fingerprint, 'string');
    assert.strictEqual(group.fingerprint.length, 12);
    assert.ok(group.memberCount >= 2);
  }

  // Duplicate completeness: all 8 octet sharers are grouped, none missed.
  const octetAnons = new Set(
    Array.from({ length: 8 }, (_, i) => audit.anonUid(`au-oct${i}`)),
  );
  const octetGroup = report.duplicateGroups.find((group) =>
    group.members.every((member) => octetAnons.has(member.anon)),
  );
  assert.ok(octetGroup, 'octet duplicate group present');
  assert.strictEqual(octetGroup.memberCount, 8, 'all 8 sharers grouped');
  assert.strictEqual(octetGroup.members.length, 8, 'no sharer missed');

  const byAnon = new Map(report.review.map((entry) => [entry.anon, entry.issues]));
  const issuesFor = (uid) => byAnon.get(audit.anonUid(uid)) || [];
  const has = (uid, issue) => issuesFor(uid).includes(issue);
  assert.ok(has('au-missing', 'missing-username'), 'missing username classified');
  assert.ok(has('au-invalid', 'invalid-username'), 'invalid username classified');
  assert.ok(has('au-dup1', 'duplicate-username'), 'duplicate classified');
  assert.ok(has('au-oct0', 'duplicate-username'), 'octet sharer classified');
  assert.ok(has('au-oct7', 'duplicate-username'), 'last octet sharer classified');
  assert.ok(has('au-case1', 'duplicate-username'), 'case variant classified');
  assert.ok(has('au-mirror', 'mirror-mismatch'), 'mirror conflict classified');
  assert.ok(has('au-noprof', 'missing-public-profile'), 'missing profile classified');
  assert.ok(has('au-noclaim', 'missing-reservation'), 'missing reservation classified');
  assert.ok(has('au-ghost', 'orphan-reservation'), 'orphan classified');
  assert.ok(has('au-squatter', 'wrong-owner-reservation'), 'wrong owner classified');
  assert.ok(has('au-noauth', 'auth-less-account'), 'auth-less classified');
  assert.ok(!byAnon.has(audit.anonUid('au-clean')), 'clean account needs no review');
  assert.ok(!byAnon.has(audit.anonUid('au-page-03')), 'clean paged account needs no review');

  // Stable anonymized identifiers across runs.
  const second = await audit.runAudit(db, { auth, pageSize: 5, projectId: 'roovia-audit-test' });
  assert.deepStrictEqual(second.review, report.review);

  // No private data in the report: no emails, tokens, addresses, raw uids
  // or raw usernames anywhere in the serialized output.
  const serialized = JSON.stringify(report);
  for (const secret of [PRIVATE.email, PRIVATE.fcmToken, PRIVATE.address]) {
    assert.ok(!serialized.includes(secret), 'report must not contain private field values');
  }
  for (const raw of ['au-clean', 'au-dupe', 'au_contested', 'au_orphan', 'Au_Case', 'Bad Name!']) {
    assert.ok(!serialized.includes(raw), `report must not contain raw identifier ${raw}`);
  }

  // The audit performed no writes: collection sizes and canary unchanged.
  assert.strictEqual(await countDocs('users'), usersBefore);
  assert.strictEqual(await countDocs('user_profiles'), profilesBefore);
  assert.strictEqual(await countDocs('usernames'), claimsBefore);
  assert.deepStrictEqual((await db.collection('users').doc('au-clean').get()).data(), canaryBefore);

  // The audit module contains no Firestore write/migration/deploy capability
  // (patterns are Firestore-specific: crypto Hash.update is not a write).
  const source = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'username_audit.js'), 'utf8');
  for (const pattern of [
    /\.set\(\{/,
    /\.delete\(/,
    /\.create\(/,
    /\)\.(set|update|delete|create)\(/,
    /runTransaction/,
    /writeBatch/,
    /FieldValue/,
    /BulkWriter/,
    /setDoc/,
    /updateDoc/,
    /deleteDoc/,
    /addDoc/,
    /HttpsError/,
    // NOTE: admin.initializeApp (local connection bootstrap in main()) is
    // intentionally not scanned: establishing a client is not a write.
  ]) {
    assert.ok(!pattern.test(source), `audit source must not contain write API ${pattern}`);
  }

  // Production execution is rejected (no reads performed).
  await assert.rejects(
    audit.runAudit(db, { projectId: 'roovia-app' }),
    /production project/,
    'production project rejected',
  );
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {
    await assert.rejects(
      audit.runAudit(db, { projectId: 'roovia-audit-test' }),
      /FIRESTORE_EMULATOR_HOST/,
      'missing emulator host rejected',
    );
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = savedHost;
  }

  // Auth check is optional: skipped gracefully without an auth handle.
  const skipped = await audit.runAudit(db, { pageSize: 5, projectId: 'roovia-audit-test' });
  assert.strictEqual(skipped.authStatus, 'skipped');
  assert.strictEqual(skipped.counts.authLessAccount, 0);

  console.log('All username audit tests passed.');
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
