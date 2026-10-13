// Phase 2D.7 read-only username audit tool (LOCAL, emulator only).
//
// Inspects users/*, user_profiles/* and usernames/* to classify migration
// problems WITHOUT exposing private account information and WITHOUT
// modifying anything. There is intentionally no --dry-run flag: safety is
// structural (emulator-only execution is enforced, and this module contains
// no write, migration, repair, gate-change, or deploy capability).
//
// Privacy model:
//   - Only username-bearing fields are read; emails, tokens, addresses and
//     full documents are never selected or logged.
//   - Reports carry aggregate counts plus STABLE ANONYMIZED identifiers:
//       anon(uid)  = sha256('uid:' + uid)[0:12]
//       print(name)= sha256('username:' + canonical)[0:12] (grouping only)
//     Firebase UIDs are 128-bit random, so truncated hashes are effectively
//     one-way. Limitation: identifiers are deterministic, and tiny anonymity
//     sets (e.g. a lone duplicate pair) let a holder of database access
//     correlate groups. Treat reports as custodian-internal triage material,
//     and never publish them alongside timestamps or auxiliary metadata.
//
// Emulator-only enforcement (fail-closed, checked before any read):
//   1. FIRESTORE_EMULATOR_HOST must be set (proves emulator targeting).
//   2. The project id must not be the production project (roovia-app) and
//      must look like a test/emulator project. Anything else throws before
//      the first read.
//
// Usage (emulator only):
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-audit-test "node ../scripts/username_audit.js"
// The CLI prints the JSON report to stdout and exits non-zero only on
// enforcement or runtime failure, never on dirty findings.

const crypto = require('crypto');

const USERNAME_RE = /^[a-z0-9_]{3,20}$/;
const PRODUCTION_PROJECT_IDS = ['roovia-app'];
const TEST_PROJECT_RE = /^(demo-.+|.+-test|.+-emulator|emulator-.+)$/;

function sha12(prefix, value) {
  return crypto
    .createHash('sha256')
    .update(`${prefix}:${value}`, 'utf8')
    .digest('hex')
    .slice(0, 12);
}

function anonUid(uid) {
  return sha12('uid', uid);
}

function fingerprintUsername(canonical) {
  return sha12('username', canonical);
}

function canonicalUsername(raw) {
  if (typeof raw !== 'string') {
    return '';
  }
  return raw.trim().toLowerCase();
}

function isValidUsername(raw) {
  return USERNAME_RE.test(canonicalUsername(raw));
}

// Throws unless execution provably targets a non-production emulator.
// Reads no data; safe to call first.
function assertEmulatorProject(projectId) {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (typeof host !== 'string' || host.trim() === '') {
    throw new Error(
      'username_audit refused: FIRESTORE_EMULATOR_HOST is not set (emulator-only tool).',
    );
  }
  if (typeof projectId !== 'string' || projectId.trim() === '') {
    throw new Error('username_audit refused: project id is unknown.');
  }
  const normalized = projectId.trim();
  if (PRODUCTION_PROJECT_IDS.includes(normalized)) {
    throw new Error(
      `username_audit refused: project "${normalized}" is a production project.`,
    );
  }
  if (!TEST_PROJECT_RE.test(normalized)) {
    throw new Error(
      `username_audit refused: project "${normalized}" does not look like an emulator/test project.`,
    );
  }
  return normalized;
}

async function* readPages(collectionRef, pageSize) {
  let query = collectionRef.orderBy('__name__').limit(pageSize);
  for (;;) {
    const snapshot = await query.get();
    if (snapshot.empty) {
      return;
    }
    yield snapshot.docs;
    if (snapshot.docs.length < pageSize) {
      return;
    }
    query = collectionRef.orderBy('__name__').startAfter(snapshot.docs[snapshot.docs.length - 1]).limit(pageSize);
  }
}

// Only username-relevant fields are extracted; everything else is ignored.
function pickUsernameFields(data) {
  if (!data || typeof data !== 'object') {
    return { username: '' };
  }
  return { username: typeof data.username === 'string' ? data.username : '' };
}

async function collectUsernames(db, pageSize) {
  const users = new Map();
  const profiles = new Map();
  const claims = new Map();

  for await (const docs of readPages(db.collection('users'), pageSize)) {
    for (const docSnap of docs) {
      users.set(docSnap.id, pickUsernameFields(docSnap.data()));
    }
  }
  for await (const docs of readPages(db.collection('user_profiles'), pageSize)) {
    for (const docSnap of docs) {
      profiles.set(docSnap.id, pickUsernameFields(docSnap.data()));
    }
  }
  for await (const docs of readPages(db.collection('usernames'), pageSize)) {
    for (const docSnap of docs) {
      const data = docSnap.data() || {};
      claims.set(docSnap.id, {
        uid: typeof data.uid === 'string' ? data.uid : '',
      });
    }
  }
  return { users, profiles, claims };
}

async function collectAuthUids(auth) {
  if (!auth || typeof auth.listUsers !== 'function') {
    return null;
  }
  const uids = new Set();
  let pageToken;
  for (;;) {
    const result = await auth.listUsers(1000, pageToken);
    for (const user of result.users || []) {
      if (user && user.uid) {
        uids.add(user.uid);
      }
    }
    if (!result.pageToken) {
      return uids;
    }
    pageToken = result.pageToken;
  }
}

// Pure classification over collected maps (no I/O, no private data).
function classify(collected, authUids) {
  const { users, profiles, claims } = collected;
  const counts = {
    totalAccounts: 0,
    clean: 0,
    missingUsername: 0,
    invalidUsername: 0,
    duplicateUsername: 0,
    caseVariantGroups: 0,
    mirrorMismatch: 0,
    missingPublicProfile: 0,
    missingReservation: 0,
    orphanReservation: 0,
    wrongOwnerReservation: 0,
    authLessAccount: 0,
  };
  const review = [];
  const duplicateGroups = [];

  // canonical -> [{ uid, source }] across both mirror collections.
  const holdersByCanonical = new Map();
  const registerHolder = (canonical, uid, source) => {
    if (canonical === '') {
      return;
    }
    if (!holdersByCanonical.has(canonical)) {
      holdersByCanonical.set(canonical, []);
    }
    holdersByCanonical.get(canonical).push({ uid, source });
  };
  for (const [uid, fields] of users) {
    registerHolder(canonicalUsername(fields.username), uid, 'users');
  }
  for (const [uid, fields] of profiles) {
    registerHolder(canonicalUsername(fields.username), uid, 'user_profiles');
  }

  const duplicateCanonicals = new Map();
  for (const [canonical, holders] of holdersByCanonical) {
    const distinctUids = [...new Set(holders.map((holder) => holder.uid))];
    if (distinctUids.length > 1) {
      duplicateCanonicals.set(canonical, { holders, distinctUids });
    }
  }

  const accountUids = new Set([...users.keys(), ...profiles.keys()]);
  const claimOwnerUids = new Set();
  for (const claim of claims.values()) {
    if (claim.uid !== '') {
      accountUids.add(claim.uid);
      claimOwnerUids.add(claim.uid);
    }
  }
  counts.totalAccounts = accountUids.size;

  // Reservation-side findings (owner-absent or misaligned claims).
  const orphanDetails = [];
  const wrongOwnerDetails = [];
  for (const [name, claim] of claims) {
    const canonical = canonicalUsername(name);
    const hasOwnerDocs = users.has(claim.uid) || profiles.has(claim.uid);
    const ownerUsers = users.get(claim.uid);
    const ownerProfiles = profiles.get(claim.uid);
    const referenced =
      (ownerUsers && canonicalUsername(ownerUsers.username) === canonical) ||
      (ownerProfiles && canonicalUsername(ownerProfiles.username) === canonical);
    if (!hasOwnerDocs || !referenced) {
      orphanDetails.push({ name, claim });
    }
    const holders = holdersByCanonical.get(canonical) || [];
    const foreignHolders = holders.filter((holder) => holder.uid !== claim.uid);
    if (foreignHolders.length > 0) {
      wrongOwnerDetails.push({ name, claim, foreignHolders });
    }
  }
  const orphanNames = new Set(orphanDetails.map((detail) => detail.name));
  const wrongOwnerNames = new Set(wrongOwnerDetails.map((detail) => detail.name));

  for (const [canonical, group] of duplicateCanonicals) {
    const rawVariants = new Set(
      group.holders.map((holder) => {
        const fields =
          holder.source === 'users' ? users.get(holder.uid) : profiles.get(holder.uid);
        return (fields && fields.username ? fields.username : '').trim();
      }),
    );
    duplicateGroups.push({
      fingerprint: fingerprintUsername(canonical),
      memberCount: group.distinctUids.length,
      members: group.distinctUids.map((uid) => ({ anon: anonUid(uid) })),
      rawVariantCount: rawVariants.size,
    });
  }
  counts.caseVariantGroups = duplicateGroups.filter(
    (group) => group.rawVariantCount > 1,
  ).length;

  for (const uid of accountUids) {
    const issues = [];
    const usersFields = users.get(uid);
    const profilesFields = profiles.get(uid);
    const rawUsers = usersFields ? usersFields.username : '';
    const rawProfiles = profilesFields ? profilesFields.username : '';
    const hasUsersName = rawUsers.trim() !== '';
    const hasProfilesName = rawProfiles.trim() !== '';

    if (!hasUsersName && !hasProfilesName) {
      issues.push('missing-username');
    } else {
      if ((hasUsersName && !isValidUsername(rawUsers)) || (hasProfilesName && !isValidUsername(rawProfiles))) {
        issues.push('invalid-username');
      }
      const canonicals = new Set(
        [canonicalUsername(rawUsers), canonicalUsername(rawProfiles)].filter((c) => c !== ''),
      );
      for (const canonical of canonicals) {
        if (duplicateCanonicals.has(canonical)) {
          issues.push('duplicate-username');
          break;
        }
      }
      if (hasUsersName && hasProfilesName && rawUsers.trim() !== rawProfiles.trim()) {
        issues.push('mirror-mismatch');
      }
      if (hasUsersName && !profilesFields) {
        issues.push('missing-public-profile');
      }
      for (const canonical of canonicals) {
        if (!isValidUsername(canonical)) {
          continue;
        }
        const claim = claims.get(canonical);
        if (!claim) {
          issues.push('missing-reservation');
          break;
        }
        if (claim.uid !== uid) {
          issues.push('wrong-owner-reservation');
          break;
        }
      }
    }

    for (const detail of orphanDetails) {
      if (detail.claim.uid === uid) {
        issues.push('orphan-reservation');
        break;
      }
    }

    if (
      authUids !== null &&
      !authUids.has(uid) &&
      (users.has(uid) || profiles.has(uid) || claimOwnerUids.has(uid))
    ) {
      issues.push('auth-less-account');
    }

    const uniqueIssues = [...new Set(issues)];
    for (const issue of uniqueIssues) {
      switch (issue) {
        case 'missing-username':
          counts.missingUsername += 1;
          break;
        case 'invalid-username':
          counts.invalidUsername += 1;
          break;
        case 'duplicate-username':
          counts.duplicateUsername += 1;
          break;
        case 'mirror-mismatch':
          counts.mirrorMismatch += 1;
          break;
        case 'missing-public-profile':
          counts.missingPublicProfile += 1;
          break;
        case 'missing-reservation':
          counts.missingReservation += 1;
          break;
        case 'orphan-reservation':
          counts.orphanReservation += 1;
          break;
        case 'wrong-owner-reservation':
          counts.wrongOwnerReservation += 1;
          break;
        case 'auth-less-account':
          counts.authLessAccount += 1;
          break;
        default:
          break;
      }
    }
    if (uniqueIssues.length === 0) {
      counts.clean += 1;
    } else {
      review.push({ anon: anonUid(uid), issues: uniqueIssues });
    }
  }

  review.sort((left, right) => (left.anon < right.anon ? -1 : left.anon > right.anon ? 1 : 0));
  duplicateGroups.sort((left, right) => (left.fingerprint < right.fingerprint ? -1 : 1));

  return { counts, duplicateGroups, review, orphanNames: orphanNames.size, wrongOwnerNames: wrongOwnerNames.size };
}

async function runAudit(db, options = {}) {
  const pageSize = options.pageSize && options.pageSize > 0 ? Math.floor(options.pageSize) : 100;
  const settingsProject =
    db && db._settings && typeof db._settings.projectId === 'string' ? db._settings.projectId : '';
  const projectId =
    (typeof options.projectId === 'string' && options.projectId.trim() !== ''
      ? options.projectId.trim()
      : '') ||
    settingsProject ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT ||
    'unknown';
  assertEmulatorProject(projectId);

  const collected = await collectUsernames(db, pageSize);
  const authUids = await collectAuthUids(options.auth || null);
  const { counts, duplicateGroups, review } = classify(collected, authUids);

  return {
    projectId: projectId || 'unknown',
    pageSize,
    authStatus: authUids === null ? 'skipped' : 'checked',
    counts,
    duplicateGroups,
    review,
  };
}

async function main() {
  const admin = require('firebase-admin');
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'roovia-audit-test' });
  }
  const db = admin.firestore();
  let auth = null;
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    auth = admin.auth();
  }
  const report = await runAudit(db, {
    auth,
    pageSize: 100,
    projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || undefined,
  });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`username_audit failed: ${error && error.message ? error.message : error}`);
    process.exitCode = 1;
  });
}

module.exports = {
  runAudit,
  classify,
  assertEmulatorProject,
  anonUid,
  fingerprintUsername,
  canonicalUsername,
  isValidUsername,
};
