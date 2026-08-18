// Runs against the real Firestore emulator (memberships/publications/
// groupCookbooks/groups docs) with a stubbed Storage bucket (no real
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
  for (const collectionName of ['groups', 'memberships', 'publications', 'groupCookbooks', 'deleteGroupPermanentlyAttempts']) {
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

async function seedGroup({ groupID, memberships }) {
  await db.collection('groups').doc(groupID).set({ id: groupID });
  await Promise.all(memberships.map((membership) => (
    db.collection('memberships').doc(membership.id).set(membership)
  )));
}

test('deletes the group, its memberships, cookbooks, publications, and photos', async () => {
  const groupID = 'group-1';
  await seedGroup({
    groupID,
    memberships: [{ id: 'm1', groupID, userID: 'alice', status: 'active' }],
  });
  await db.collection('groupCookbooks').doc('cb1').set({ id: 'cb1', groupID, cookbookName: 'Reunion' });
  await db.collection('groupCookbooks').doc('cb2').set({ id: 'cb2', groupID, cookbookName: 'Holidays' });
  await db.collection('publications').doc('p1').set({ groupID, sourceRecipeID: 'r1' });
  await db.collection('publications').doc('p2').set({ groupID, sourceRecipeID: 'r2' });
  const bucket = fakeBucket({
    [`publications/${groupID}/`]: [`${groupID}/alice_r1.jpg`, `${groupID}/alice_r2.jpg`],
  });

  const result = await deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' });

  assert.deepEqual(result, { deleted: true });
  assert.equal((await db.collection('groups').doc(groupID).get()).exists, false);
  assert.equal((await db.collection('memberships').doc('m1').get()).exists, false);
  assert.equal((await db.collection('groupCookbooks').doc('cb1').get()).exists, false);
  assert.equal((await db.collection('groupCookbooks').doc('cb2').get()).exists, false);
  assert.equal((await db.collection('publications').doc('p1').get()).exists, false);
  assert.equal((await db.collection('publications').doc('p2').get()).exists, false);
  assert.equal(bucket.deleted.length, 2);
});

test('rejects a caller who is not an active member of the group', async () => {
  const groupID = 'group-2';
  await seedGroup({
    groupID,
    memberships: [{ id: 'm1', groupID, userID: 'alice', status: 'active' }],
  });
  const bucket = fakeBucket({});

  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'mallory' }));

  // Nothing should have been touched.
  assert.equal((await db.collection('groups').doc(groupID).get()).exists, true);
});

test('rejects an active member who is not the last active member', async () => {
  const groupID = 'group-4';
  await seedGroup({
    groupID,
    memberships: [
      { id: 'm1', groupID, userID: 'alice', status: 'active' },
      { id: 'm2', groupID, userID: 'bob', status: 'active' },
    ],
  });
  const bucket = fakeBucket({});

  // alice is a genuine active member, but bob is too — alice is not the
  // *last* one, so this must be rejected. Before this check existed, any
  // active member could delete the whole shared cookbook out from under
  // everyone else.
  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' }));

  assert.equal((await db.collection('groups').doc(groupID).get()).exists, true);
  assert.equal((await db.collection('memberships').doc('m1').get()).exists, true);
  assert.equal((await db.collection('memberships').doc('m2').get()).exists, true);
});

test('rejects a caller whose own membership has already left', async () => {
  const groupID = 'group-3';
  await seedGroup({
    groupID,
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

test('rate-limits repeated deletion attempts by the same caller', async () => {
  const bucket = fakeBucket({});

  // 5 real, successful deletions (each its own group, same caller) —
  // exhausts the limit; the 6th must be rejected even though it targets
  // yet another group this caller genuinely owns and could otherwise
  // delete. Without this, a compromised/malicious client could script
  // unlimited deleteGroupPermanently calls with no throttling at all.
  for (let i = 0; i < 5; i++) {
    const groupID = `rl-group-${i}`;
    await seedGroup({
      groupID,
      memberships: [{ id: `rl-m-${i}`, groupID, userID: 'alice', status: 'active' }],
    });
    const result = await deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' });
    assert.deepEqual(result, { deleted: true });
  }

  const sixthGroupID = 'rl-group-5';
  await seedGroup({
    groupID: sixthGroupID,
    memberships: [{ id: 'rl-m-5', groupID: sixthGroupID, userID: 'alice', status: 'active' }],
  });

  await assert.rejects(() => deleteGroupPermanently({ db, bucket, groupID: sixthGroupID, callerUserID: 'alice' }));

  // The 6th group is genuinely untouched — rejected before any deletion work.
  assert.equal((await db.collection('groups').doc(sixthGroupID).get()).exists, true);
});

test('rate limit is tracked per caller, not globally', async () => {
  const bucket = fakeBucket({});

  for (let i = 0; i < 5; i++) {
    const groupID = `rl2-group-${i}`;
    await seedGroup({
      groupID,
      memberships: [{ id: `rl2-m-${i}`, groupID, userID: 'alice', status: 'active' }],
    });
    await deleteGroupPermanently({ db, bucket, groupID, callerUserID: 'alice' });
  }

  // alice just exhausted her limit, but bob has his own independent budget.
  const bobGroupID = 'rl2-bob-group';
  await seedGroup({
    groupID: bobGroupID,
    memberships: [{ id: 'rl2-bob-m', groupID: bobGroupID, userID: 'bob', status: 'active' }],
  });

  const result = await deleteGroupPermanently({ db, bucket, groupID: bobGroupID, callerUserID: 'bob' });
  assert.deepEqual(result, { deleted: true });
});
