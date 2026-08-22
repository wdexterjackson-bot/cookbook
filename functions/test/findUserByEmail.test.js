// Runs against the real Firestore emulator (userProfiles + rate-limit
// bookkeeping) with a stubbed Auth client (no real Auth-emulator user
// fixture needed) — same approach as resolveSignInProviders.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { findUserByEmail } = require('../findUserByEmail');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const collectionName of ['userProfiles', 'findUserByEmailAttempts']) {
    const snapshot = await db.collection(collectionName).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

function fakeAuthClient(usersByUID) {
  return {
    async getUser(uid) {
      const user = usersByUID[uid];
      if (!user) {
        const error = new Error('no user');
        error.code = 'auth/user-not-found';
        throw error;
      }
      return user;
    },
  };
}

test('finds a discoverable user by email', async () => {
  await db.collection('userProfiles').doc('bob-uid').set({ email: 'bob@example.com', isEmailDiscoverable: true });
  const authClient = fakeAuthClient({ 'bob-uid': { displayName: 'Bob Barrentine' } });

  const result = await findUserByEmail({ db, authClient, email: 'bob@example.com', callerUserID: 'alice-uid' });

  assert.deepEqual(result, { found: true, userID: 'bob-uid', displayName: 'Bob Barrentine' });
});

test('reports not found for an unregistered email', async () => {
  const authClient = fakeAuthClient({});

  const result = await findUserByEmail({ db, authClient, email: 'nobody@example.com', callerUserID: 'alice-uid' });

  assert.deepEqual(result, { found: false });
});

test('reports not found (not "hidden") for a user who opted out of discovery', async () => {
  await db.collection('userProfiles').doc('bob-uid').set({ email: 'bob@example.com', isEmailDiscoverable: false });
  const authClient = fakeAuthClient({ 'bob-uid': { displayName: 'Bob Barrentine' } });

  const result = await findUserByEmail({ db, authClient, email: 'bob@example.com', callerUserID: 'alice-uid' });

  // Identical shape to "no such user" — no enumeration signal.
  assert.deepEqual(result, { found: false });
});

test('treats a missing isEmailDiscoverable field as discoverable (default true)', async () => {
  await db.collection('userProfiles').doc('bob-uid').set({ email: 'bob@example.com' });
  const authClient = fakeAuthClient({ 'bob-uid': { displayName: 'Bob Barrentine' } });

  const result = await findUserByEmail({ db, authClient, email: 'bob@example.com', callerUserID: 'alice-uid' });

  assert.equal(result.found, true);
});

test('treats a profile doc with no matching Auth user as not found', async () => {
  await db.collection('userProfiles').doc('orphan-uid').set({ email: 'orphan@example.com', isEmailDiscoverable: true });
  const authClient = fakeAuthClient({});

  const result = await findUserByEmail({ db, authClient, email: 'orphan@example.com', callerUserID: 'alice-uid' });

  assert.deepEqual(result, { found: false });
});

test('finds a user regardless of search-input casing (stored lowercase, searched mixed-case)', async () => {
  await db.collection('userProfiles').doc('bob-uid').set({ email: 'bob@example.com', isEmailDiscoverable: true });
  const authClient = fakeAuthClient({ 'bob-uid': { displayName: 'Bob Barrentine' } });

  const result = await findUserByEmail({ db, authClient, email: 'Bob@Example.com', callerUserID: 'alice-uid' });

  assert.deepEqual(result, { found: true, userID: 'bob-uid', displayName: 'Bob Barrentine' });
});

test('rejects an empty email', async () => {
  const authClient = fakeAuthClient({});

  await assert.rejects(() => findUserByEmail({ db, authClient, email: '  ', callerUserID: 'alice-uid' }));
});

test('rejects a missing callerUserID', async () => {
  const authClient = fakeAuthClient({});

  await assert.rejects(() => findUserByEmail({ db, authClient, email: 'bob@example.com', callerUserID: '' }));
});

test('rate-limits repeated lookups by the same caller', async () => {
  const authClient = fakeAuthClient({});

  for (let i = 0; i < 20; i += 1) {
    await findUserByEmail({ db, authClient, email: `person${i}@example.com`, callerUserID: 'alice-uid' });
  }

  await assert.rejects(
    () => findUserByEmail({ db, authClient, email: 'one-more@example.com', callerUserID: 'alice-uid' }),
  );
});

test('rate limit is tracked per caller, not per email — enumerating many emails does not dodge it', async () => {
  const authClient = fakeAuthClient({});

  for (let i = 0; i < 20; i += 1) {
    await findUserByEmail({ db, authClient, email: `enum${i}@example.com`, callerUserID: 'mallory-uid' });
  }

  await assert.rejects(
    () => findUserByEmail({ db, authClient, email: 'brand-new-email@example.com', callerUserID: 'mallory-uid' }),
  );
});

test('rate limit is tracked per caller — a different caller has their own fresh budget', async () => {
  const authClient = fakeAuthClient({});

  for (let i = 0; i < 20; i += 1) {
    await findUserByEmail({ db, authClient, email: `x${i}@example.com`, callerUserID: 'alice-uid' });
  }

  const result = await findUserByEmail({ db, authClient, email: 'fresh@example.com', callerUserID: 'bob-uid' });
  assert.deepEqual(result, { found: false });
});
