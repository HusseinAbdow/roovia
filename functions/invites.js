// Phase 2D.12 secure invitation backend (local backend, NOT deployed).
//
// Authenticated Callable joinByInvite replaces client-side invitation-code
// resolution, which today queries private houses and can scan the entire
// collection. The backend resolves the code via the Admin SDK, enforces
// capacity/membership/duplicate rules transactionally, and creates the
// join_requests document. Responses carry only the minimal join context:
// { requestId, houseId, houseName, status }. Address, member lists, invite
// codes, costs, and tokens are never returned, and error messages are
// generic membership states (never private details).
//
// Codes are generated client-side from A-Z2-9 (see HouseService) and stored
// verbatim, so an exact match is complete: there is intentionally NO
// normalized-fallback collection scan. A miss (including deleted houses,
// which no longer exist as documents) is a generic invalid code.
//
// Concurrency: join requests do not consume capacity themselves; the leader
// approval transaction (unchanged client flow) re-checks capacity when
// adding members. Concurrent duplicate submissions serialize in the
// transaction below: exactly one request is created.
//
// No new dependencies: firebase-functions (HttpsError codes),
// firebase-admin/firestore (FieldValue), and the member extraction shared
// with housePublic.js only.

const functions = require('firebase-functions');
const { FieldValue } = require('firebase-admin/firestore');
const { extractMembers } = require('./housePublic');

const INVITE_CODE_RE = /^[A-Z2-9]{4,8}$/;
const JOIN_STATUS_PENDING = 'pending';

function normalizeInviteCode(raw) {
  if (typeof raw !== 'string') {
    return '';
  }
  return raw.trim().toUpperCase().replace(/\s+/g, '').replace(/-/g, '');
}

function validateInviteCode(raw) {
  const normalized = normalizeInviteCode(raw);
  if (!INVITE_CODE_RE.test(normalized)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid code.');
  }
  return normalized;
}

function requireUid(authUid) {
  if (typeof authUid !== 'string' || authUid.trim() === '') {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required.');
  }
  return authUid.trim();
}

function asPositiveInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(1, Math.trunc(value));
  }
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return Math.max(1, parsed);
    }
  }
  return 1;
}

function currentHouseIdOf(userSnap) {
  if (!userSnap || userSnap.exists !== true) {
    return '';
  }
  const value = (userSnap.data() || {}).currentHouseId;
  return typeof value === 'string' ? value.trim() : '';
}

// Transactional invite resolution + join-request creation. All state checks
// and the write happen atomically, so concurrent duplicate submissions
// produce exactly one pending request.
async function transactJoinByInvite(db, uid, rawCode) {
  const caller = requireUid(uid);
  const code = validateInviteCode(rawCode);

  return db.runTransaction(async (tx) => {
    const resolved = await tx.get(
      db.collection('houses').where('inviteCode', '==', code).limit(1),
    );
    if (resolved.empty) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid code.');
    }
    const houseSnap = resolved.docs[0];
    const houseId = houseSnap.id;
    const house = houseSnap.data() || {};
    const members = extractMembers(house);
    const maxMembers = asPositiveInt(house.maxMembers);

    if (members.includes(caller)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'User is already a member of this house.',
      );
    }
    if (members.length >= maxMembers) {
      throw new functions.https.HttpsError('failed-precondition', 'House is full.');
    }

    const userSnap = await tx.get(db.collection('users').doc(caller));
    if (currentHouseIdOf(userSnap) !== '') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'User is already in another house.',
      );
    }
    const membership = await tx.get(
      db.collection('houses').where('members', 'array-contains', caller).limit(1),
    );
    if (!membership.empty) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'User is already in another house.',
      );
    }

    const pending = await tx.get(
      db
        .collection('join_requests')
        .where('houseId', '==', houseId)
        .where('userId', '==', caller)
        .where('status', '==', JOIN_STATUS_PENDING)
        .limit(1),
    );
    if (!pending.empty) {
      throw new functions.https.HttpsError(
        'already-exists',
        'A pending request already exists for this house.',
      );
    }

    const requestRef = db.collection('join_requests').doc();
    tx.set(requestRef, {
      houseId,
      userId: caller,
      status: JOIN_STATUS_PENDING,
      createdAt: FieldValue.serverTimestamp(),
    });

    const name = typeof house.name === 'string' ? house.name : '';
    return { requestId: requestRef.id, houseId, houseName: name, status: JOIN_STATUS_PENDING };
  });
}

// Callable-facing handler: UID is derived by the wrapper from
// context.auth.uid and never accepted from client data.
async function handleJoinByInvite(db, authUid, rawCode) {
  return transactJoinByInvite(db, requireUid(authUid), rawCode);
}

module.exports = {
  normalizeInviteCode,
  validateInviteCode,
  transactJoinByInvite,
  handleJoinByInvite,
};
