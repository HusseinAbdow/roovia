// Firestore rules tests for the Phase 2D.2 public-data security foundation.
//
// New collections (no application migration yet):
//   user_profiles/{uid}  -> public directory (signed-in read, self write,
//                           strict allowlist, no rating, no sensitive keys;
//                           username '' allowed as unclaimed sentinel 2D.13D)
//   house_public/{id}    -> discovery summaries (signed-in read, NO client
//                           writes; backend sync required - see below)
//   usernames/{name}     -> reservation map (evaluated, NOT enabled: client
//                           writes stay denied to prevent unlimited squatting.
//                           Safe use needs atomic batch with user_profiles via
//                           getAfter() plus client dual-write support from the
//                           next checkpoint.)
//
// Preserved (regression guards in this file):
//   users/{uid}, houses/{houseId} permissions are unchanged.
//
// Backend notes (do NOT implement here):
//   house_public must mirror authoritative houses/{houseId} via a trusted
//   backend (Cloud Function onWrite houses -> house_public). Rules cannot
//   force atomic dual-writes or cascading deletes, so client writes stay
//   denied even for well-formed shapes.
//   usernames needs an atomic claim+profile batch (getAfter both ways) once
//   clients dual-write; until then standalone claims stay denied.
//
// Run with the Firestore emulator:
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-rules-test "node ../test/firestore_rules/privacy_rules_test.js"
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
} = require('firebase/firestore');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const RULES = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

const USER_A = 'user-a';
const USER_B = 'user-b';

const validProfile = (uid, overrides = {}) => ({
  uid,
  name: 'Test User',
  username: 'test_user',
  profileImageUrl: 'https://example.com/a.png',
  bio: 'Hello Roovia',
  updatedAt: new Date('2026-10-01T10:00:00Z'),
  ...overrides,
});

const validHousePublic = (overrides = {}) => ({
  houseId: 'house-1',
  name: 'Sun House',
  city: 'Bartin',
  district: 'Merkez',
  description: 'Near campus',
  rentTotal: 12000,
  electricityTotal: 800,
  waterTotal: 400,
  internetTotal: 500,
  maxMembers: 4,
  memberCount: 2,
  discoverable: true,
  updatedAt: new Date('2026-10-01T10:00:00Z'),
  ...overrides,
});

async function seedData(env) {
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'user_profiles', USER_A), validProfile(USER_A));
    await setDoc(doc(admin, 'house_public', 'house-1'), validHousePublic());
    await setDoc(doc(admin, 'usernames', 'takenname'), {
      uid: USER_B,
      updatedAt: new Date('2026-10-01T10:00:00Z'),
    });
    // Regression fixtures: existing collections keep working.
    await setDoc(doc(admin, 'users', USER_A), {
      uid: USER_A,
      name: 'Test User',
      email: 'a@example.com',
      username: 'test_user',
      profileImageUrl: '',
      rating: 0,
    });
    await setDoc(doc(admin, 'houses', 'house-1'), {
      houseId: 'house-1',
      name: 'Sun House',
      leaderId: USER_A,
      members: [USER_A],
      inviteCode: 'ABCDE',
      discoverable: true,
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

const profileDoc = (db, uid) => doc(db, `user_profiles/${uid}`);
const housePublicDoc = (db, hid) => doc(db, `house_public/${hid}`);
const usernameDoc = (db, name) => doc(db, `usernames/${name}`);

async function run() {
  const env = await initializeTestEnvironment({
    projectId: 'roovia-rules-test',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
  });

  try {
    await seedData(env);

    const userA = env.authenticatedContext(USER_A).firestore();
    const userB = env.authenticatedContext(USER_B).firestore();
    const unauth = env.unauthenticatedContext().firestore();

    // ---------- USER PROFILES: reads ----------
    await assertSucceeds(getDoc(profileDoc(userA, USER_A)));
    await assertSucceeds(getDoc(profileDoc(userB, USER_A)));
    await assertSucceeds(getDocs(collection(userA, 'user_profiles')));
    await expectDenied('unauth profile get', getDoc(profileDoc(unauth, USER_A)));
    await expectDenied('unauth profile list', getDocs(collection(unauth, 'user_profiles')));

    // ---------- USER PROFILES: legitimate self writes ----------
    await assertSucceeds(setDoc(profileDoc(userB, USER_B), validProfile(USER_B)));
    await assertSucceeds(updateDoc(profileDoc(userA, USER_A), { name: 'New Name' }));
    await assertSucceeds(updateDoc(profileDoc(userA, USER_A), { bio: '' }));

    // ---------- USER PROFILES: cross-user ----------
    await expectDenied(
      'cross-user profile create',
      setDoc(profileDoc(userA, 'user-cross'), validProfile('user-cross')),
    );
    await expectDenied(
      'cross-user profile update',
      updateDoc(profileDoc(userA, USER_B), { name: 'Hijacked' }),
    );

    // ---------- USER PROFILES: ownership ----------
    const ownerCtx = env.authenticatedContext('user-owner').firestore();
    await expectDenied(
      'profile create with mismatched uid field',
      setDoc(profileDoc(ownerCtx, 'user-owner'), validProfile('someone-else')),
    );
    await expectDenied(
      'profile update changes uid field',
      updateDoc(profileDoc(userA, USER_A), { uid: USER_B }),
    );

    // ---------- USER PROFILES: sensitive / unknown fields ----------
    const sensitiveCases = {
      email: 'a@example.com',
      fcmToken: 'tok123',
      fcmTokenUpdatedAt: new Date('2026-10-01T10:00:00Z'),
      currentHouseId: 'house-1',
      profileImageStoragePath: 'users/user-a/profile/x.jpg',
      amountOwed: 100,
      balance: 50,
      rating: 4.5,
      isAdmin: true,
      foo: 'bar',
    };
    for (const [key, value] of Object.entries(sensitiveCases)) {
      await expectDenied(
        `profile update with forbidden field ${key}`,
        updateDoc(profileDoc(userA, USER_A), { [key]: value }),
      );
    }
    const sensCtx = env.authenticatedContext('user-sens').firestore();
    await expectDenied(
      'profile create with sensitive field email',
      setDoc(profileDoc(sensCtx, 'user-sens'), validProfile('user-sens', { email: 'x@y.z' })),
    );
    await expectDenied(
      'profile create with unknown field',
      setDoc(profileDoc(sensCtx, 'user-sens'), validProfile('user-sens', { foo: 'bar' })),
    );

    // ---------- USER PROFILES: types / lengths ----------
    const invalidCreates = {
      'empty name': validProfile('user-v1', { name: '' }),
      'oversized name': validProfile('user-v2', { name: 'x'.repeat(81) }),
      'uppercase username': validProfile('user-v3', { username: 'Test_User' }),
      'short username': validProfile('user-v4', { username: 'ab' }),
      'long username': validProfile('user-v5', { username: 'a'.repeat(21) }),
      'bad username chars': validProfile('user-v6', { username: 'bad-name!' }),
      'non-string avatar': validProfile('user-v7', { profileImageUrl: 123 }),
      'oversized avatar': validProfile('user-v8', { profileImageUrl: 'https://e.com/' + 'x'.repeat(2049) }),
      'oversized bio': validProfile('user-v9', { bio: 'x'.repeat(501) }),
      'non-string bio': validProfile('user-v10', { bio: 7 }),
      'missing updatedAt': (() => {
        const p = validProfile('user-v11');
        delete p.updatedAt;
        return p;
      })(),
      'string updatedAt': validProfile('user-v12', { updatedAt: 'now' }),
    };
    for (const [label, payload] of Object.entries(invalidCreates)) {
      const ctx = env.authenticatedContext(payload.uid).firestore();
      await expectDenied(`profile create invalid: ${label}`, setDoc(profileDoc(ctx, payload.uid), payload));
    }

    // ---------- 2D.13D: unclaimed username sentinel (username == '') ----------
    // A public profile may exist without a claimed username. '' asserts no
    // name, holds no reservation, and changes nothing else about the contract:
    // ownership, allowlist, lengths, auth, and delete rules all still apply.
    const emptyCtx = env.authenticatedContext('user-empty').firestore();

    // 1. Owner can create a valid public profile with username: ''.
    await assertSucceeds(
      setDoc(profileDoc(emptyCtx, 'user-empty'), validProfile('user-empty', { username: '' })),
    );

    // 2. Owner can update permitted public fields while username remains ''.
    await assertSucceeds(
      updateDoc(profileDoc(emptyCtx, 'user-empty'), { name: 'Still No Handle' }),
    );
    await assertSucceeds(updateDoc(profileDoc(emptyCtx, 'user-empty'), { bio: 'Filling in later' }));
    await assertSucceeds(
      updateDoc(profileDoc(emptyCtx, 'user-empty'), {
        profileImageUrl: 'https://example.com/b.png',
      }),
    );

    // The sentinel does not lock the owner out of a later valid username.
    await assertSucceeds(
      updateDoc(profileDoc(emptyCtx, 'user-empty'), { username: 'now_claimed' }),
    );
    await assertSucceeds(updateDoc(profileDoc(emptyCtx, 'user-empty'), { username: '' }));

    // 3. Valid nonempty usernames still work.
    const validCtx = env.authenticatedContext('user-valid2').firestore();
    await assertSucceeds(
      setDoc(
        profileDoc(validCtx, 'user-valid2'),
        validProfile('user-valid2', { username: 'another_ok' }),
      ),
    );

    // 4. Invalid nonempty usernames are rejected (rules do not trim).
    const badNames = ['has space', ' a', 'a ', 'UPPER', 'ab', 'a'.repeat(21), 'bad-name!'];
    for (let i = 0; i < badNames.length; i += 1) {
      const uid = `user-bad${i}`;
      const ctx = env.authenticatedContext(uid).firestore();
      await expectDenied(
        `invalid nonempty username ${JSON.stringify(badNames[i])}`,
        setDoc(profileDoc(ctx, uid), validProfile(uid, { username: badNames[i] })),
      );
    }

    // 5. Missing username field is rejected.
    const missingCtx = env.authenticatedContext('user-nousername').firestore();
    const missingPayload = validProfile('user-nousername');
    delete missingPayload.username;
    await expectDenied(
      'profile create with missing username field',
      setDoc(profileDoc(missingCtx, 'user-nousername'), missingPayload),
    );

    // 6. Another user cannot modify the sentinel profile.
    await expectDenied(
      'cross-user update of sentinel profile',
      updateDoc(profileDoc(userB, 'user-empty'), { name: 'Hijacked' }),
    );
    await expectDenied(
      'cross-user overwrite of sentinel profile',
      setDoc(profileDoc(userB, 'user-empty'), validProfile('user-empty', { username: '' })),
    );

    // 7. Unauthenticated writes are rejected.
    await expectDenied(
      'unauth profile create',
      setDoc(profileDoc(unauth, 'user-anon'), validProfile('user-anon', { username: '' })),
    );
    await expectDenied(
      'unauth profile update',
      updateDoc(profileDoc(unauth, 'user-empty'), { name: 'Anon' }),
    );
    await expectDenied('unauth profile delete', deleteDoc(profileDoc(unauth, 'user-empty')));

    // 8. Extra private fields are rejected even alongside the sentinel.
    const sneakCtx = env.authenticatedContext('user-sneak').firestore();
    await expectDenied(
      'sentinel create with private email field',
      setDoc(
        profileDoc(sneakCtx, 'user-sneak'),
        validProfile('user-sneak', { username: '', email: 'sneak@example.com' }),
      ),
    );
    await expectDenied(
      'sentinel update with private field',
      updateDoc(profileDoc(emptyCtx, 'user-empty'), { fcmToken: 'tok' }),
    );

    // 9. Client writes to usernames remain denied (reservation authority untouched).
    await expectDenied(
      'username claim still denied for clients',
      setDoc(usernameDoc(emptyCtx, 'fresh_claim'), {
        uid: 'user-empty',
        updatedAt: new Date('2026-10-01T10:00:00Z'),
      }),
    );

    // 10. Sentinel profile deletion remains denied.
    await expectDenied(
      'self sentinel profile delete',
      deleteDoc(profileDoc(emptyCtx, 'user-empty')),
    );
    await expectDenied(
      'cross-user sentinel profile delete',
      deleteDoc(profileDoc(userB, 'user-empty')),
    );

    // 11. Private users/houses rules unchanged.
    await expectDenied(
      'cross-user users update',
      updateDoc(doc(userB, 'users', USER_A), { name: 'Hijacked' }),
    );
    await expectDenied(
      'unauth users update',
      updateDoc(doc(unauth, 'users', USER_A), { name: 'Anon' }),
    );
    await expectDenied('cross-user users delete', deleteDoc(doc(userB, 'users', USER_A)));

    // ---------- USER PROFILES: delete ----------
    await expectDenied('self profile delete', deleteDoc(profileDoc(userA, USER_A)));
    await expectDenied('cross-user profile delete', deleteDoc(profileDoc(userA, USER_B)));

    // ---------- HOUSE PUBLIC: reads ----------
    await assertSucceeds(getDoc(housePublicDoc(userA, 'house-1')));
    await assertSucceeds(getDocs(collection(userA, 'house_public')));
    await expectDenied('unauth house_public get', getDoc(housePublicDoc(unauth, 'house-1')));
    await expectDenied('unauth house_public list', getDocs(collection(unauth, 'house_public')));

    // ---------- HOUSE PUBLIC: client writes denied ----------
    await expectDenied(
      'house_public client create (valid shape)',
      setDoc(housePublicDoc(userA, 'house-new'), validHousePublic({ houseId: 'house-new' })),
    );
    await expectDenied(
      'house_public client update',
      updateDoc(housePublicDoc(userA, 'house-1'), { name: 'Edited' }),
    );
    await expectDenied('house_public client delete', deleteDoc(housePublicDoc(userA, 'house-1')));

    // Sensitive / invalid shapes are rejected (writes denied regardless;
    // backend sync must enforce the allowlist when it lands).
    const sensitiveHouses = {
      address: 'Exact street 12',
      inviteCode: 'ABCDE',
      members: [USER_A],
      leaderId: USER_A,
      secretSetting: true,
    };
    for (const [key, value] of Object.entries(sensitiveHouses)) {
      await expectDenied(
        `house_public create with forbidden field ${key}`,
        setDoc(housePublicDoc(userA, `house-${key}`), validHousePublic({ houseId: `house-${key}`, [key]: value })),
      );
    }
    await expectDenied(
      'house_public create with unknown field',
      setDoc(housePublicDoc(userA, 'house-unknown'), validHousePublic({ houseId: 'house-unknown', foo: 'bar' })),
    );
    await expectDenied(
      'house_public create with wrong type',
      setDoc(
        housePublicDoc(userA, 'house-badtype'),
        validHousePublic({ houseId: 'house-badtype', memberCount: 'two' }),
      ),
    );

    // ---------- USERNAMES: reads / denied writes ----------
    await assertSucceeds(getDoc(usernameDoc(userA, 'takenname')));
    await expectDenied('unauth username get', getDoc(usernameDoc(unauth, 'takenname')));
    await expectDenied('unauth username claim', setDoc(usernameDoc(unauth, 'squat1'), { uid: 'anon' }));
    await expectDenied(
      'standalone username squat',
      setDoc(usernameDoc(userA, 'squat-by-a'), { uid: USER_A, updatedAt: new Date() }),
    );
    await expectDenied(
      'cross-user username claim',
      setDoc(usernameDoc(userA, 'evil-claim'), { uid: USER_B, updatedAt: new Date() }),
    );
    await expectDenied(
      'duplicate username claim',
      setDoc(usernameDoc(userA, 'takenname'), { uid: USER_A, updatedAt: new Date() }),
    );
    await expectDenied(
      'username update',
      updateDoc(usernameDoc(userB, 'takenname'), { uid: USER_A }),
    );
    await expectDenied('username delete', deleteDoc(usernameDoc(userB, 'takenname')));

    // ---------- REGRESSION: existing collections unchanged ----------
    await assertSucceeds(getDoc(doc(userA, 'users', USER_A)));
    await assertSucceeds(getDoc(doc(userB, 'users', USER_A)));
    await expectDenied('unauth users read', getDoc(doc(unauth, 'users', USER_A)));
    await assertSucceeds(getDoc(doc(userA, 'houses', 'house-1')));
    await assertSucceeds(getDoc(doc(userB, 'houses', 'house-1')));
    await expectDenied('unauth houses read', getDoc(doc(unauth, 'houses', 'house-1')));

    if (permittedBypasses.length > 0) {
      console.log(
        `\nSECURITY HOLES OPEN (${permittedBypasses.length}):\n- ${permittedBypasses.join('\n- ')}`,
      );
    } else {
      console.log('All public-data authorization attacks denied.');
    }
    assert.strictEqual(
      permittedBypasses.length,
      0,
      `Public-data bypasses permitted: ${permittedBypasses.join('; ')}`,
    );

    console.log('All privacy rules tests passed.');
  } finally {
    await env.cleanup();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
