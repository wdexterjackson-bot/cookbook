// Runs against the real Firestore emulator, same approach as
// deleteGroupPermanently.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { changeOwnMembership } = require('../changeOwnMembership');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  const snapshot = await db.collection('memberships').get();
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
});

async function seedMemberships(groupID, memberships) {
  await Promise.all(memberships.map((membership) => (
    db.collection('memberships').doc(membership.id).set({ groupID, ...membership })
  )));
}

test('rejects a sole admin trying to demote themselves while other members remain', async () => {
  const groupID = 'group-1';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'demote', callerUserID: 'alice' }));

  const membership = (await db.collection('memberships').doc('m1').get()).data();
  assert.equal(membership.role, 'admin');
});

test('rejects a sole admin trying to leave while other members remain', async () => {
  const groupID = 'group-2';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'leave', callerUserID: 'alice' }));

  const membership = (await db.collection('memberships').doc('m1').get()).data();
  assert.equal(membership.status, 'active');
});

test('allows self-demote once a second active admin exists', async () => {
  const groupID = 'group-3';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'admin', status: 'active' },
  ]);

  const result = await changeOwnMembership({ db, groupID, action: 'demote', callerUserID: 'alice' });

  assert.deepEqual(result, { ok: true });
  const membership = (await db.collection('memberships').doc('m1').get()).data();
  assert.equal(membership.role, 'member');
});

test('allows an admin to leave once a second active admin exists', async () => {
  const groupID = 'group-4';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'admin', status: 'active' },
  ]);

  const result = await changeOwnMembership({ db, groupID, action: 'leave', callerUserID: 'alice' });

  assert.deepEqual(result, { ok: true });
  const membership = (await db.collection('memberships').doc('m1').get()).data();
  assert.equal(membership.status, 'left');
});

test('rejects a caller who is not an active member of the group', async () => {
  const groupID = 'group-5';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'leave', callerUserID: 'mallory' }));
});

test('rejects a plain member trying to demote (nothing to demote)', async () => {
  const groupID = 'group-6';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'demote', callerUserID: 'bob' }));
});

test('a plain member can leave freely, regardless of admin count', async () => {
  const groupID = 'group-7';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  const result = await changeOwnMembership({ db, groupID, action: 'leave', callerUserID: 'bob' });

  assert.deepEqual(result, { ok: true });
});

test('rejects the last active member leaving — deleteGroupPermanently is the right call instead', async () => {
  const groupID = 'group-8';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'leave', callerUserID: 'alice' }));
});

test('rejects a missing groupID', async () => {
  await assert.rejects(() => changeOwnMembership({ db, groupID: '  ', action: 'leave', callerUserID: 'alice' }));
});

test('rejects an invalid action', async () => {
  const groupID = 'group-9';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeOwnMembership({ db, groupID, action: 'promote', callerUserID: 'alice' }));
});
