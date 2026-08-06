// Runs against the real Firestore emulator (memberships/publications/
// groupUniquenessKeys/groups docs) with a stubbed Storage bucket (no real
// Storage emulator fixture needed for listing/deleting a handful of fake
// file references) — same approach as resolveSignInProviders.test.js
// stubbing the Auth client.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { deleteGroupPermanently } = require('../deleteGroupPermanently');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const collectionName of ['groups', 'memberships', 'publications', 'groupUniquenessKeys']) {
    const snapshot = await db.collection(collectionName).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

function fakeBucket(filesByPrefix) {
  const deleted = [];
  return {
    deleted,
    async getFiles({ prefix }) {
      const files = filesByPrefix[prefix] || [];
      return [files.map((name) => ({
        name,
        async delete() {
          deleted.push(name);
        },
      }))];
    },
  };
}

async function seedGroup({ groupID, uniquenessKey, memberships }) {
  await db.collection('groups').doc(groupID).set({
    id: groupID,
    cookbookName: 'Reunion',
    uniquenessKey,
  });
  await Promise.all(memberships.map((membership) => (
    db.collection('memberships').doc(membership.id).set(membership)
  )));
}

test('deletes the group, its memberships, publications, photos, and the uniqueness reservation', async () => {
  const groupID = 'group-1';
  const uniquenessKey = 'reunion|barrentine|memphis';
  await seedGroup({
    groupID,
    uniquenessKey,
    memberships: [{ id: 'm1', groupID, userID: 'alice', status: 'active' }],
  });
  await db.collection('groupUniquenessKeys').doc(uniquenessKey).set({ groupID });
  await db.collection('publications').doc('p1').set({ groupID, sourceRecipeID: 'r1' });
  await db.collection('publications').doc('p2').set({ groupID, sourceRecipeID: 'r2' });
  const bucket = fakeBucket({
    [`publications/${groupID}/`]: [`${groupID}/alice_r1.jpg`, `${groupID}/alice_r2.jpg`],
  });

  const result = await deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' });

  assert.deepEqual(result, { deleted: true });
  assert.equal((await db.collection('groups').doc(groupID).get()).exists, false);
  assert.equal((await db.collection('memberships').doc('m1').get()).exists, false);
  assert.equal((await db.collection('publications').doc('p1').get()).exists, false);
  assert.equal((await db.collection('publications').doc('p2').get()).exists, false);
  assert.equal((await db.collection('groupUniquenessKeys').doc(uniquenessKey).get()).exists, false);
  assert.equal(bucket.deleted.length, 2);
});

test('rejects a caller who is not an active member of the group', async () => {
  const groupID = 'group-2';
  await seedGroup({
    groupID,
    uniquenessKey: 'other-key',
    memberships: [{ id: 'm1', groupID, userID: 'alice', status: 'active' }],
  });
  const bucket = fakeBucket({});

  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'mallory' }));

  // Nothing should have been touched.
  assert.equal((await db.collection('groups').doc(groupID).get()).exists, true);
});

test('rejects a caller whose own membership has already left', async () => {
  const groupID = 'group-3';
  await seedGroup({
    groupID,
    uniquenessKey: 'other-key-2',
    memberships: [{ id: 'm1', groupID, userID: 'alice', status: 'left' }],
  });
  const bucket = fakeBucket({});

  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' }));
});

test('is idempotent — a retry against an already-deleted group succeeds as a no-op', async () => {
  const bucket = fakeBucket({});

  const result = await deleteGroupPermanently({ db, bucket, groupID: 'never-existed', callerUserID: 'alice' });

  assert.deepEqual(result, { deleted: false });
});

test('rejects a missing groupID', async () => {
  const bucket = fakeBucket({});

  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID: '  ', callerUserID: 'alice' }));
});
