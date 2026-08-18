// Runs against the real Firestore emulator, same approach as
// changeOwnMembership.test.js.
//
// Note on the last-admin guard: in a single, non-concurrent call, the
// caller is always a *different* active admin than the target (self-
// targeting is rejected separately), so the caller itself always
// satisfies "another admin exists" — the guard can never fire from one
// call in isolation. It exists specifically for the race two concurrent
// calls create (two admins simultaneously removing *each other*), so
// that's what's actually tested below, using real concurrent transactions
// against the emulator rather than a sequential setup.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { changeMemberRole } = require('../changeMemberRole');

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

test('an admin can promote another member', async () => {
  const groupID = 'group-1';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  const result = await changeMemberRole({ db, groupID, targetUserID: 'bob', action: 'promote', callerUserID: 'alice' });

  assert.deepEqual(result, { ok: true });
  const membership = (await db.collection('memberships').doc('m2').get()).data();
  assert.equal(membership.role, 'admin');
});

test('an admin can demote another admin, leaving the caller as sole admin', async () => {
  const groupID = 'group-2';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'admin', status: 'active' },
  ]);

  await changeMemberRole({ db, groupID, targetUserID: 'bob', action: 'demote', callerUserID: 'alice' });

  const membership = (await db.collection('memberships').doc('m2').get()).data();
  assert.equal(membership.role, 'member');
});

test('an admin can remove another admin, leaving the caller as sole admin', async () => {
  const groupID = 'group-3';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'admin', status: 'active' },
  ]);

  await changeMemberRole({ db, groupID, targetUserID: 'bob', action: 'remove', callerUserID: 'alice' });

  const membership = (await db.collection('memberships').doc('m2').get()).data();
  assert.equal(membership.status, 'suspended');
});

// The actual regression test for the bug this function was written to
// close: two admins simultaneously try to remove *each other*. Before the
// transactional rewrite, a plain read-then-write let both succeed (each
// individually saw "2 admins, safe"), zeroing the group's admin count
// permanently. Firestore's transaction retry (forced by both transactions
// reading the same memberships query, so a write inside one invalidates
// the other's read set) must serialize these — the second to commit has
// to see the first's result and correctly refuse, since by then the
// group's only remaining active admin is itself.
test('two admins concurrently removing each other cannot both succeed — at least one admin always survives', async () => {
  const groupID = 'group-4';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'admin', status: 'active' },
  ]);

  const results = await Promise.allSettled([
    changeMemberRole({ db, groupID, targetUserID: 'bob', action: 'remove', callerUserID: 'alice' }),
    changeMemberRole({ db, groupID, targetUserID: 'alice', action: 'remove', callerUserID: 'bob' }),
  ]);

  // Exactly one of the two racing calls must have been rejected by the
  // last-admin guard — never both succeeding (the bug) and, since this is
  // a genuine race with no seed for a valid rejection, never both failing
  // either.
  const succeededCount = results.filter((r) => r.status === 'fulfilled').length;
  assert.equal(succeededCount, 1);

  const [aliceDoc, bobDoc] = await Promise.all([
    db.collection('memberships').doc('m1').get(),
    db.collection('memberships').doc('m2').get(),
  ]);
  const activeCount = [aliceDoc, bobDoc].filter((d) => d.data().status === 'active').length;
  assert.equal(activeCount, 1, 'exactly one admin must remain active — the group must never lose all its admins');
});

test('rejects a caller who is not an active admin', async () => {
  const groupID = 'group-5';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeMemberRole({ db, groupID, targetUserID: 'alice', action: 'demote', callerUserID: 'bob' }));
});

test('rejects a target who is not an active member', async () => {
  const groupID = 'group-6';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
  ]);

  await assert.rejects(() => changeMemberRole({ db, groupID, targetUserID: 'ghost', action: 'promote', callerUserID: 'alice' }));
});

test('rejects self-targeting — that path is changeOwnMembership, not this function', async () => {
  const groupID = 'group-7';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
  ]);

  await assert.rejects(() => changeMemberRole({ db, groupID, targetUserID: 'alice', action: 'demote', callerUserID: 'alice' }));
});

test('rejects an invalid action', async () => {
  const groupID = 'group-8';
  await seedMemberships(groupID, [
    { id: 'm1', userID: 'alice', role: 'admin', status: 'active' },
    { id: 'm2', userID: 'bob', role: 'member', status: 'active' },
  ]);

  await assert.rejects(() => changeMemberRole({ db, groupID, targetUserID: 'bob', action: 'delete', callerUserID: 'alice' }));
});
