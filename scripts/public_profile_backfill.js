// Phase 2D.13B public-profile backfill foundation (LOCAL, emulator only).
//
// Admin-only tool that creates missing user_profiles/{uid} documents from
// private users/{uid} documents. The client migration and the private-user
// rules lockdown happen in later checkpoints; this tool changes no app
// behavior and never touches production data.
//
// What it does:
//   - Reads users/* with bounded pagination.
//   - Creates the allowlisted public shape for UIDs that have no
//     user_profiles/{uid} document yet.
//   - Reports (anonymized) every skipped record and every legacy duplicate
//     username group WITHOUT correcting them.
//
// What it never does:
//   - Overwrite, update, or delete any existing document (create-only).
//   - Copy private fields (email, FCM tokens, storage paths, membership
//     pointers, invite codes, rating).
//   - Generate usernames from email or invent usernames in any other way.
//   - Establish global username uniqueness (duplicates are reported as-is).
//
// Safety model (fail-closed, checked before any read):
//   1. FIRESTORE_EMULATOR_HOST must be set (proves emulator targeting).
//   2. The project id must not be a production project (roovia-app) and must
//      look like a test/emulator project. Anything else throws before the
//      first read.
//   3. Dry-run is the default: without an explicit --apply flag the tool
//      reads, classifies, and reports, but performs zero writes.
//
// Privacy model:
//   - Only public-shape fields are extracted; emails, tokens, addresses and
//     full documents are never selected or logged.
//   - Reports carry aggregate counts plus STABLE ANONYMIZED identifiers:
//       anon(uid)  = sha256('uid:' + uid)[0:12]
//       print(name)= sha256('username:' + canonical)[0:12] (grouping only)
//
// Usage (emulator only):
//   cd functions && npx firebase-tools emulators:exec --only firestore \
//     --project roovia-backfill-test "node ../scripts/public_profile_backfill.js [--apply] [--page-size N]"
//
// The CLI prints the JSON report to stdout and exits non-zero only on
// enforcement or runtime failure, never on dirty findings.
//
// No new dependencies: Node built-ins (crypto) plus firebase-admin (already
// a functions dependency) only.

const crypto = require('crypto');

// Mirrors firestore.rules validPublicProfile().
const USERNAME_RE = /^[a-z0-9_]{3,20}$/;
const PUBLIC_PROFILE_KEYS = ['uid', 'name', 'username', 'profileImageUrl', 'bio', 'updatedAt'];

// Private users/* keys that must NEVER be copied. Listed here so reviewers
// can audit the extraction function against them.
const PRIVATE_KEYS_NEVER_COPIED = [
  'email',
  'fcmToken',
  'fcmTokenUpdatedAt',
  'profileImageStoragePath',
  'profileImageUpdatedAt',
  'currentHouseId',
  'rating',
  'inviteCode',
];

const PRODUCTION_PROJECT_IDS = ['roovia-app'];
const TEST_PROJECT_RE = /^(demo-.+|.+-test|.+-emulator|emulator-.+)$/;

const FALLBACK_DISPLAY_NAME = 'Member';
const MAX_NAME_LENGTH = 80;
const MAX_IMAGE_URL_LENGTH = 2048;
const DEFAULT_PAGE_SIZE = 100;
const MAX_PAGE_SIZE = 500;
const WRITE_BATCH_LIMIT = 400;

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

// Throws unless execution provably targets a non-production emulator.
// Reads no data; safe to call first.
function assertEmulatorProject(projectId) {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (typeof host !== 'string' || host.trim() === '') {
    throw new Error(
      'public_profile_backfill refused: FIRESTORE_EMULATOR_HOST is not set (emulator-only tool).',
    );
  }
  if (typeof projectId !== 'string' || projectId.trim() === '') {
    throw new Error('public_profile_backfill refused: project id is unknown.');
  }
  const normalized = projectId.trim();
  if (PRODUCTION_PROJECT_IDS.includes(normalized)) {
    throw new Error(
      `public_profile_backfill refused: project "${normalized}" is a production project.`,
    );
  }
  if (!TEST_PROJECT_RE.test(normalized)) {
    throw new Error(
      `public_profile_backfill refused: project "${normalized}" does not look like an emulator/test project.`,
    );
  }
  return normalized;
}

function parseArgs(argv) {
  const args = Array.isArray(argv) ? argv : [];
  let apply = false;
  let pageSize = DEFAULT_PAGE_SIZE;
  let projectId = '';
  for (let i = 0; i < args.length; i += 1) {
    const token = args[i];
    if (token === '--apply') {
      apply = true;
    } else if (token === '--page-size' || token === '--pageSize') {
      const next = args[i + 1];
      const parsed = Number.parseInt(next, 10);
      if (Number.isFinite(parsed)) {
        pageSize = parsed;
      }
      i += 1;
    } else if (token === '--project' || token === '--projectId') {
      projectId = typeof args[i + 1] === 'string' ? args[i + 1] : '';
      i += 1;
    } else if (token === '--help' || token === '-h') {
      return { help: true, apply: false, pageSize: DEFAULT_PAGE_SIZE, projectId: '' };
    }
  }
  if (!Number.isFinite(pageSize) || pageSize <= 0) {
    pageSize = DEFAULT_PAGE_SIZE;
  }
  pageSize = Math.min(Math.floor(pageSize), MAX_PAGE_SIZE);
  return { help: false, apply, pageSize, projectId };
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
    query = collectionRef
      .orderBy('__name__')
      .startAfter(snapshot.docs[snapshot.docs.length - 1])
      .limit(pageSize);
  }
}

// Extracts ONLY the public-shape source fields. Every other key of the
// private document (email, tokens, storage paths, membership pointers) is
// ignored here and can never reach a profile write.
function pickPublicSource(data) {
  if (!data || typeof data !== 'object') {
    return { name: '', username: '', profileImageUrl: '' };
  }
  return {
    name: typeof data.name === 'string' ? data.name : '',
    username: typeof data.username === 'string' ? data.username : '',
    profileImageUrl: typeof data.profileImageUrl === 'string' ? data.profileImageUrl : '',
  };
}

// Pure constructor for one public profile. Usernames are preserved verbatim
// when (and only when) they already satisfy the rules regex; missing or
// invalid usernames are skipped, never generated or repaired. Display names
// may fall back to 'Member' (rules-legal); image URLs fall back to ''.
function buildPublicProfile(uid, picked) {
  const source = {
    name: typeof picked.name === 'string' ? picked.name : '',
    username: typeof picked.username === 'string' ? picked.username : '',
    profileImageUrl: typeof picked.profileImageUrl === 'string' ? picked.profileImageUrl : '',
  };
  const username = source.username.trim();
  if (username === '') {
    return { status: 'skip', reason: 'missing-username' };
  }
  if (!USERNAME_RE.test(username)) {
    return { status: 'skip', reason: 'invalid-username' };
  }

  let nameDefaulted = false;
  let name = source.name.trim();
  if (name === '') {
    name = FALLBACK_DISPLAY_NAME;
    nameDefaulted = true;
  } else if (name.length > MAX_NAME_LENGTH) {
    name = name.slice(0, MAX_NAME_LENGTH);
    nameDefaulted = true;
  }

  let imageUrlDefaulted = false;
  let profileImageUrl = source.profileImageUrl.trim();
  if (profileImageUrl.length > MAX_IMAGE_URL_LENGTH) {
    profileImageUrl = '';
    imageUrlDefaulted = true;
  }

  return {
    status: 'ready',
    fields: { uid, name, username, profileImageUrl, bio: '' },
    nameDefaulted,
    imageUrlDefaulted,
  };
}

function resolveServerTimestamp(injected) {
  if (typeof injected === 'function') {
    return injected;
  }
  try {
    // eslint-disable-next-line global-require
    const { FieldValue } = require('firebase-admin/firestore');
    return () => FieldValue.serverTimestamp();
  } catch (error) {
    throw new Error(
      'public_profile_backfill requires firebase-admin (functions dependency) for server timestamps.',
    );
  }
}

async function collectUsers(db, pageSize) {
  const users = new Map();
  for await (const docs of readPages(db.collection('users'), pageSize)) {
    for (const docSnap of docs) {
      // The document ID is the canonical uid; a conflicting data.uid field
      // (if any) is ignored so a stale mirror can never rename a profile.
      users.set(docSnap.id, pickPublicSource(docSnap.data()));
    }
  }
  return users;
}

async function collectProfileIds(db, pageSize) {
  const ids = new Set();
  for await (const docs of readPages(db.collection('user_profiles'), pageSize)) {
    for (const docSnap of docs) {
      ids.add(docSnap.id);
    }
  }
  return ids;
}

function findDuplicateGroups(users) {
  const holdersByCanonical = new Map();
  for (const [uid, picked] of users) {
    const canonical = canonicalUsername(picked.username);
    if (canonical === '') {
      continue;
    }
    if (!holdersByCanonical.has(canonical)) {
      holdersByCanonical.set(canonical, []);
    }
    holdersByCanonical.get(canonical).push(uid);
  }
  const groups = [];
  for (const [canonical, uids] of holdersByCanonical) {
    const distinct = [...new Set(uids)];
    if (distinct.length > 1) {
      groups.push({
        fingerprint: fingerprintUsername(canonical),
        memberCount: distinct.length,
        members: distinct.map((uid) => ({ anon: anonUid(uid) })),
      });
    }
  }
  groups.sort((left, right) => (left.fingerprint < right.fingerprint ? -1 : 1));
  return groups;
}

// Creates one missing profile. Uses create() (never set/update) so a
// concurrently created profile fails instead of being overwritten; the
// caller reclassifies such races as skipped-existing on re-run.
async function createProfile(db, uid, fields, serverTimestamp) {
  const payload = {
    uid: fields.uid,
    name: fields.name,
    username: fields.username,
    profileImageUrl: fields.profileImageUrl,
    bio: fields.bio,
    updatedAt: serverTimestamp(),
  };
  const unexpected = Object.keys(payload).filter((key) => !PUBLIC_PROFILE_KEYS.includes(key));
  if (unexpected.length > 0) {
    throw new Error(`public_profile_backfill refused: unexpected key ${unexpected.join(',')}`);
  }
  await db.collection('user_profiles').doc(uid).create(payload);
}

async function writeMissing(db, planned, serverTimestamp) {
  let created = 0;
  let batches = 0;
  const createdAnons = [];
  const raced = [];
  for (let i = 0; i < planned.length; i += WRITE_BATCH_LIMIT) {
    const chunk = planned.slice(i, i + WRITE_BATCH_LIMIT);
    const batch = db.batch();
    for (const item of chunk) {
      batch.create(db.collection('user_profiles').doc(item.uid), {
        uid: item.fields.uid,
        name: item.fields.name,
        username: item.fields.username,
        profileImageUrl: item.fields.profileImageUrl,
        bio: item.fields.bio,
        updatedAt: serverTimestamp(),
      });
    }
    batches += 1;
    try {
      await batch.commit();
      created += chunk.length;
      for (const item of chunk) {
        createdAnons.push(anonUid(item.uid));
      }
    } catch (error) {
      // A chunk can fail when a profile appeared since the pre-scan
      // (concurrent writer). Fall back to per-document creates so one race
      // does not block the rest; already-exists races are reclassified.
      for (const item of chunk) {
        try {
          await createProfile(db, item.uid, item.fields, serverTimestamp);
          created += 1;
          createdAnons.push(anonUid(item.uid));
        } catch (single) {
          const code = single && single.code;
          if (code === 6 || code === 'already-exists' || code === 'ALREADY_EXISTS') {
            raced.push(item.uid);
          } else {
            throw single;
          }
        }
      }
    }
  }
  return { created, batches, createdAnons: createdAnons.sort(), raced };
}

async function runBackfill(db, options = {}) {
  const pageSize =
    options.pageSize && options.pageSize > 0
      ? Math.min(Math.floor(options.pageSize), MAX_PAGE_SIZE)
      : DEFAULT_PAGE_SIZE;
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

  const apply = options.apply === true;
  const serverTimestamp = apply ? resolveServerTimestamp(options.serverTimestamp) : null;

  const users = await collectUsers(db, pageSize);
  const profileIds = await collectProfileIds(db, pageSize);

  const counts = {
    usersScanned: users.size,
    profilesPreExisting: profileIds.size,
    planned: 0,
    created: 0,
    writeBatches: 0,
    skippedExisting: 0,
    skippedMissingUsername: 0,
    skippedInvalidUsername: 0,
    nameDefaulted: 0,
    imageUrlDefaulted: 0,
    duplicateGroupCount: 0,
    duplicateMemberCount: 0,
  };
  const skipped = [];
  const planned = [];
  const plannedAnons = [];

  for (const [uid, picked] of users) {
    if (profileIds.has(uid)) {
      counts.skippedExisting += 1;
      skipped.push({ anon: anonUid(uid), reason: 'existing-profile' });
      continue;
    }
    const built = buildPublicProfile(uid, picked);
    if (built.status === 'skip') {
      if (built.reason === 'missing-username') {
        counts.skippedMissingUsername += 1;
      } else {
        counts.skippedInvalidUsername += 1;
      }
      skipped.push({ anon: anonUid(uid), reason: built.reason });
      continue;
    }
    if (built.nameDefaulted) {
      counts.nameDefaulted += 1;
    }
    if (built.imageUrlDefaulted) {
      counts.imageUrlDefaulted += 1;
    }
    planned.push({ uid, fields: built.fields });
    plannedAnons.push(anonUid(uid));
  }
  plannedAnons.sort();
  skipped.sort((left, right) => (left.anon < right.anon ? -1 : left.anon > right.anon ? 1 : 0));
  counts.planned = planned.length;

  const duplicateGroups = findDuplicateGroups(users);
  counts.duplicateGroupCount = duplicateGroups.length;
  counts.duplicateMemberCount = duplicateGroups.reduce(
    (total, group) => total + group.memberCount,
    0,
  );

  let createdAnons = [];
  if (apply && planned.length > 0) {
    const written = await writeMissing(db, planned, serverTimestamp);
    counts.created = written.created;
    counts.writeBatches = written.batches;
    createdAnons = written.createdAnons;
    for (const uid of written.raced) {
      counts.skippedExisting += 1;
      skipped.push({ anon: anonUid(uid), reason: 'existing-profile' });
    }
    skipped.sort((left, right) => (left.anon < right.anon ? -1 : left.anon > right.anon ? 1 : 0));
  }

  return {
    projectId,
    mode: apply ? 'apply' : 'dry-run',
    pageSize,
    counts,
    duplicateGroups,
    plannedAnons,
    createdAnons,
    skipped,
    notes: [
      'Duplicate legacy usernames are reported as-is; this tool does not establish global username uniqueness.',
      'Existing public profiles are never overwritten; re-runs converge to zero writes.',
    ],
  };
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2));
  if (parsed.help) {
    process.stdout.write(
      'Usage: node public_profile_backfill.js [--apply] [--page-size N] [--project ID]\n',
    );
    return;
  }
  // eslint-disable-next-line global-require
  const admin = require('firebase-admin');
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'roovia-backfill-test' });
  }
  const db = admin.firestore();
  const report = await runBackfill(db, {
    apply: parsed.apply,
    pageSize: parsed.pageSize,
    projectId:
      parsed.projectId || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || undefined,
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`public_profile_backfill failed: ${error && error.message ? error.message : error}`);
    process.exitCode = 1;
  });
}

module.exports = {
  runBackfill,
  buildPublicProfile,
  parseArgs,
  assertEmulatorProject,
  anonUid,
  fingerprintUsername,
  canonicalUsername,
  PUBLIC_PROFILE_KEYS,
  PRIVATE_KEYS_NEVER_COPIED,
};
