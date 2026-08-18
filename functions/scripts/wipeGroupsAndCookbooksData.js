// One-off destructive script: wipes all personal-cookbook and Family
// Cookbook data ahead of the #5 Groups & Friends schema rewrite (see
// "Pre-work: clean slate" in the implementation plan). There is no real
// production data yet, so a clean slate was chosen over a migration.
// Run manually via `node`, never deployed as a Cloud Function — this
// exists to run at most once.
//
// Usage:
//   node functions/scripts/wipeGroupsAndCookbooksData.js \
//       --project=cookbook-779c6 --bucket=cookbook-779c6.firebasestorage.app
//       (dry run: counts docs/files, deletes nothing)
//   ...same, plus --confirm
//       (actually deletes)
//
// Requires GOOGLE_APPLICATION_CREDENTIALS to point at a service account
// key for the target project (Firebase Console > Project Settings >
// Service Accounts > Generate new private key). Deliberately does NOT
// fall back to ambient/default credential discovery — this dev machine
// has no gcloud/ADC set up, and a silent fallback could resolve against
// the wrong project.

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

// Deliberately NOT touched: entitlements/*, userProfiles/*, purchaseClaims/*
// — unrelated to cookbooks/groups.
const FIRESTORE_COLLECTIONS = [
  'personalCookbooks', // recursiveDelete also removes its recipes subcollection
  'groups',
  'memberships',
  'publications', // recursiveDelete also removes its likes/ratings subcollections
  'joinRequests',
  'invitations',
  'groupUniquenessKeys',
];

const STORAGE_PREFIXES = ['personalCookbooks/', 'publications/'];

function parseArgs(argv) {
  const projectArg = argv.find((a) => a.startsWith('--project='));
  const bucketArg = argv.find((a) => a.startsWith('--bucket='));
  return {
    projectId: projectArg ? projectArg.split('=')[1] : null,
    storageBucket: bucketArg ? bucketArg.split('=')[1] : null,
    confirm: argv.includes('--confirm'),
  };
}

async function countCollection(db, name) {
  const snap = await db.collection(name).count().get();
  return snap.data().count;
}

async function countStoragePrefix(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix });
  return files.length;
}

async function deleteStoragePrefix(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix });
  await Promise.all(files.map((file) => file.delete()));
  return files.length;
}

async function main() {
  const { projectId, storageBucket, confirm } = parseArgs(process.argv.slice(2));
  if (!projectId) {
    console.error(
      'Refusing to run: pass --project=<id> explicitly (e.g. --project=cookbook-779c6). ' +
        'No default project is used, to avoid ever wiping the wrong one.'
    );
    process.exit(1);
  }
  if (!storageBucket) {
    console.error(
      'Refusing to run: pass --bucket=<name> explicitly (find it in GoogleService-Info.plist / STORAGE_BUCKET).'
    );
    process.exit(1);
  }
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      'Refusing to run: set GOOGLE_APPLICATION_CREDENTIALS to a service account key for the target project first.'
    );
    process.exit(1);
  }

  initializeApp({ credential: applicationDefault(), projectId, storageBucket });
  const db = getFirestore();
  const bucket = getStorage().bucket();

  console.log(`Target project: ${projectId}`);
  console.log(confirm ? 'Mode: DELETE (--confirm passed)' : 'Mode: DRY RUN (pass --confirm to actually delete)');
  console.log('');

  for (const name of FIRESTORE_COLLECTIONS) {
    const count = await countCollection(db, name);
    console.log(`Firestore /${name}: ${count} top-level doc(s)`);
  }
  for (const prefix of STORAGE_PREFIXES) {
    const count = await countStoragePrefix(bucket, prefix);
    console.log(`Storage ${prefix}*: ${count} file(s)`);
  }

  if (!confirm) {
    console.log('\nDry run only — nothing deleted. Re-run with --confirm to actually wipe this data.');
    return;
  }

  console.log('\nDeleting...');
  for (const name of FIRESTORE_COLLECTIONS) {
    await db.recursiveDelete(db.collection(name));
    console.log(`Deleted Firestore /${name} (incl. subcollections).`);
  }
  for (const prefix of STORAGE_PREFIXES) {
    const deletedCount = await deleteStoragePrefix(bucket, prefix);
    console.log(`Deleted ${deletedCount} Storage file(s) under ${prefix}*.`);
  }
  console.log('\nDone.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
