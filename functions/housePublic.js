// Phase 2D.10 trusted house-public projection (local backend, NOT deployed).
//
// Maintains house_public/{houseId} discovery summaries from the
// authoritative houses/{houseId} documents. Clients must never write
// house_public directly (Firestore rules deny all client writes); this
// Admin-SDK projection is the only writer.
//
// Public schema (explicit allowlist, actual repository field names):
//   houseId, name, city, district, description,
//   rentTotal, electricityTotal, waterTotal, internetTotal,
//   maxMembers, memberCount, discoverable, updatedAt, sourceUpdatedAt
// Explicitly NEVER copied: address, inviteCode (and invite_code/code
// variants), members (and memberIds/users/userIds variants),
// leaderId (and ownerId/adminId/leader_id variants), chatName,
// createdAt, join requests, financial transaction records, unknown fields.
//
// Compatibility notes (mirror lib/models/house_model.dart + HouseService):
//   - district falls back to the legacy `area` key, as House.fromMap does.
//   - memberCount derives from the first list found among the member-key
//     variants, as _extractMembers does.
//   - a missing discoverable flag normalizes to true, as _extractDiscoverable
//     and House.fromMap do (legacy houses predate the flag).
//   - sourceUpdatedAt republishes the private doc's updatedAt/createdAt for
//     staleness ordering only; it carries no account or location data.
//
// Ordering: Firestore delivers per-document events in order, but redelivery
// and interleaved create/delete cycles are possible. Every decision below
// compares the incoming source time against the stored sourceUpdatedAt, so a
// stale event can neither overwrite newer data, resurrect a removed summary,
// nor delete a summary that a newer house version already refreshed.
//
// No new dependencies: firebase-functions (trigger registration lives in
// index.js) and firebase-admin/firestore (FieldValue) only.

const { FieldValue } = require('firebase-admin/firestore');

const MEMBER_KEYS = ['members', 'memberIds', 'users', 'userIds'];

function asString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function asDouble(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function asInt(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(1, Math.trunc(value));
  }
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return Math.max(1, parsed);
    }
  }
  return fallback;
}

function extractMembers(raw) {
  for (const key of MEMBER_KEYS) {
    const candidate = raw[key];
    if (Array.isArray(candidate)) {
      return candidate
        .map((item) => (item === null || item === undefined ? '' : String(item).trim()))
        .filter((id) => id !== '');
    }
  }
  return [];
}

function extractDiscoverable(raw) {
  const candidates = [raw.discoverable, raw.isDiscoverable, raw.public];
  for (const candidate of candidates) {
    if (typeof candidate === 'boolean') {
      return candidate;
    }
    if (typeof candidate === 'string') {
      const normalized = candidate.trim().toLowerCase();
      if (normalized === 'true') {
        return true;
      }
      if (normalized === 'false') {
        return false;
      }
    }
  }
  return true;
}

function toMillis(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  return null;
}

function sourceTime(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  return toMillis(raw.updatedAt) ?? toMillis(raw.createdAt);
}

function buildPublicSummary(houseId, raw) {
  const members = extractMembers(raw);
  const district = asString(raw.district) !== '' ? asString(raw.district) : asString(raw.area);
  return {
    houseId: asString(raw.houseId) !== '' ? asString(raw.houseId) : String(houseId),
    name: asString(raw.name),
    city: asString(raw.city),
    district,
    description: asString(raw.description),
    rentTotal: asDouble(raw.rentTotal),
    electricityTotal: asDouble(raw.electricityTotal),
    waterTotal: asDouble(raw.waterTotal),
    internetTotal: asDouble(raw.internetTotal),
    maxMembers: asInt(raw.maxMembers, 1),
    memberCount: members.length,
    discoverable: extractDiscoverable(raw),
    updatedAt: FieldValue.serverTimestamp(),
    sourceUpdatedAt: sourceTime(raw),
  };
}

// Handles one houses/{houseId} write event by projecting CURRENT committed
// state inside a transaction. Event snapshots are intentionally ignored:
// deriving from current truth (not delivery order) makes every outcome safe
// regardless of redelivery, reordering, or delete/recreate interleavings.
// The transaction is pure read-current-then-write, so SDK retries re-derive
// the same outcome and concurrent updates converge to the latest commit.
async function handleHouseWrite(db, houseId) {
  const id = String(houseId);
  const houseRef = db.collection('houses').doc(id);
  const publicRef = db.collection('house_public').doc(id);

  return db.runTransaction(async (tx) => {
    const houseSnap = await tx.get(houseRef);
    const publicSnap = await tx.get(publicRef);

    if (houseSnap.exists !== true) {
      if (publicSnap.exists !== true) {
        return { houseId: id, status: 'already-removed' };
      }
      tx.delete(publicRef);
      return { houseId: id, status: 'removed' };
    }

    const current = houseSnap.data() || {};
    if (!extractDiscoverable(current)) {
      if (publicSnap.exists !== true) {
        return { houseId: id, status: 'already-hidden' };
      }
      tx.delete(publicRef);
      return { houseId: id, status: 'hidden' };
    }

    tx.set(publicRef, buildPublicSummary(id, current));
    return { houseId: id, status: publicSnap.exists === true ? 'updated' : 'created' };
  });
}

module.exports = {
  MEMBER_KEYS,
  buildPublicSummary,
  handleHouseWrite,
  extractDiscoverable,
  extractMembers,
};
