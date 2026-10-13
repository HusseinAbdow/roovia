// Phase 2D.5 trusted username service (local backend, NOT deployed).
//
// Authority: usernames/{normalizedUsername} documents are the single source
// of truth for username ownership. Clients must never decide uniqueness via
// availability queries; all claims and renames go through the transactions
// below (exposed via authenticated Callables in index.js).
//
// Fail-closed migration gate: every operation first requires the Firestore
// document config/usernameService to exist with {enabled: true}. The gate is
// absent/false in production until the existing-user audit/backfill lands,
// so any accidental deployment denies all claims instead of risking legacy
// collisions. There is intentionally no environment-variable or default-on
// bypass, and no Auth onCreate trigger yet.
//
// Legacy guard: inside the same transaction, the service scans the legacy
// mirrors (users/*, user_profiles/*) for the requested username. A holder
// with a different UID denies the claim, so an unmigrated legacy username
// can never be taken by a new claimant.
//
// No new dependencies: firebase-functions (HttpsError codes) and
// firebase-admin/firestore (FieldValue) only.

const functions = require('firebase-functions');
const { FieldValue } = require('firebase-admin/firestore');

const USERNAME_RE = /^[a-z0-9_]{3,20}$/;
const GATE_DOC_PATH = 'config/usernameService';
// Bounded legacy-holder scan size. Reads stay small and predictable; a full
// result page proves nothing about the remainder, so reaching it rejects the
// operation instead (fail closed). Never raise this to "fix" a rejection:
// crowded names need manual migration triage, not a bigger sample.
const LEGACY_SCAN_LIMIT = 5;

function normalizeUsername(raw) {
  if (typeof raw !== 'string') {
    return '';
  }
  return raw.trim().toLowerCase();
}

function validateUsername(raw) {
  const normalized = normalizeUsername(raw);
  if (!USERNAME_RE.test(normalized)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Username must be 3 to 20 characters: lowercase letters, numbers, or underscore.',
    );
  }
  return normalized;
}

function requireUid(authUid) {
  if (typeof authUid !== 'string' || authUid.trim() === '') {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }
  return authUid.trim();
}

async function isGateEnabled(db) {
  const snapshot = await db.doc(GATE_DOC_PATH).get();
  return snapshot.exists === true && snapshot.data() !== undefined && snapshot.data().enabled === true;
}

async function requireGate(db) {
  if (!(await isGateEnabled(db))) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Username service is disabled until the existing-user migration completes.',
    );
  }
}

function ownerOf(docSnapshot) {
  if (!docSnapshot || docSnapshot.exists !== true) {
    return '';
  }
  const data = docSnapshot.data() || {};
  if (typeof data.uid === 'string' && data.uid !== '') {
    return data.uid;
  }
  return docSnapshot.id;
}

// Mirrors the granted username onto the caller's profile documents inside
// the caller's transaction. Creates a shape-complete directory profile when
// the caller has none yet (display name falls back to the private doc).
function mirrorUsername(tx, db, uid, username, usersSnap, profilesSnap) {
  const usersData = usersSnap && usersSnap.exists === true ? usersSnap.data() || {} : {};
  const profilesData =
    profilesSnap && profilesSnap.exists === true ? profilesSnap.data() || {} : {};
  const displayName =
    typeof profilesData.name === 'string' && profilesData.name.trim() !== ''
      ? profilesData.name
      : typeof usersData.name === 'string' && usersData.name.trim() !== ''
        ? usersData.name
        : 'Member';

  tx.set(
    db.collection('users').doc(uid),
    { uid, username },
    { merge: true },
  );

  if (profilesSnap && profilesSnap.exists === true) {
    tx.set(
      db.collection('user_profiles').doc(uid),
      { uid, username, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  } else {
    tx.set(db.collection('user_profiles').doc(uid), {
      uid,
      name: displayName,
      username,
      profileImageUrl:
        typeof usersData.profileImageUrl === 'string' ? usersData.profileImageUrl : '',
      bio: '',
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

// Core transactional claim-or-rename. Both exported operations share it so
// rename can never bypass the claim checks and a repeated request is a
// no-op success instead of a duplicate write.
async function transactUsername(db, uid, rawUsername) {
  const caller = requireUid(uid);
  const username = validateUsername(rawUsername);
  await requireGate(db);

  return db.runTransaction(async (tx) => {
    const claimRef = db.collection('usernames').doc(username);
    const claimSnap = await tx.get(claimRef);

    if (claimSnap.exists === true) {
      if ((claimSnap.data() || {}).uid !== caller) {
        throw new functions.https.HttpsError('already-exists', 'That username is already taken.');
      }
      const usersSnap = await tx.get(db.collection('users').doc(caller));
      const profilesSnap = await tx.get(db.collection('user_profiles').doc(caller));
      mirrorUsername(tx, db, caller, username, usersSnap, profilesSnap);
      return { username, status: 'already-owned' };
    }

    // Legacy guard: no unmigrated holder may own this name. A full result
    // page may omit conflicting holders beyond the limit, so a full page
    // rejects the operation instead of approving on a partial sample.
    for (const collection of ['users', 'user_profiles']) {
      const matches = await tx.get(
        db.collection(collection).where('username', '==', username).limit(LEGACY_SCAN_LIMIT),
      );
      if (matches.size >= LEGACY_SCAN_LIMIT) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'That username needs manual migration review before it can be claimed.',
        );
      }
      for (const candidate of matches.docs) {
        if (ownerOf(candidate) !== caller) {
          throw new functions.https.HttpsError(
            'already-exists',
            'That username belongs to an existing account.',
          );
        }
      }
    }

    const usersSnap = await tx.get(db.collection('users').doc(caller));
    const profilesSnap = await tx.get(db.collection('user_profiles').doc(caller));
    const profileName =
      profilesSnap.exists === true && typeof (profilesSnap.data() || {}).username === 'string'
        ? profilesSnap.data().username
        : '';
    const usersName =
      usersSnap.exists === true && typeof (usersSnap.data() || {}).username === 'string'
        ? usersSnap.data().username
        : '';

    // Release every caller-owned reservation the mirrors still point at.
    // Checking both mirrors matters: legacy accounts can disagree across
    // documents, and releasing only the directory name would orphan a
    // caller-owned claim for the private-doc name on every rename.
    let status = 'claimed';
    const priors = [...new Set([profileName, usersName])].filter(
      (prior) => prior !== '' && prior !== username,
    );
    for (const prior of priors) {
      const oldSnap = await tx.get(db.collection('usernames').doc(prior));
      if (oldSnap.exists !== true) {
        continue;
      }
      if ((oldSnap.data() || {}).uid !== caller) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Current username is owned by another account; contact support.',
        );
      }
      tx.delete(db.collection('usernames').doc(prior));
      status = 'renamed';
    }

    tx.set(claimRef, { uid: caller, createdAt: FieldValue.serverTimestamp() });
    mirrorUsername(tx, db, caller, username, usersSnap, profilesSnap);
    return { username, status };
  });
}

async function claimUsername(db, uid, rawUsername) {
  return transactUsername(db, uid, rawUsername);
}

async function changeUsername(db, uid, rawUsername) {
  return transactUsername(db, uid, rawUsername);
}

// Callable-facing handlers: UID is derived by the wrapper from
// context.auth.uid and never accepted from client data.
async function handleClaimUsername(db, authUid, rawUsername) {
  return claimUsername(db, requireUid(authUid), rawUsername);
}

async function handleChangeUsername(db, authUid, rawUsername) {
  return changeUsername(db, requireUid(authUid), rawUsername);
}

module.exports = {
  GATE_DOC_PATH,
  normalizeUsername,
  validateUsername,
  isGateEnabled,
  claimUsername,
  changeUsername,
  handleClaimUsername,
  handleChangeUsername,
};
