// Runs against the real Firestore emulator (rate-limit bookkeeping) with a
// stubbed Auth client (no real Auth-emulator user fixture needed) — same
// approach as applyPurchaseClaim.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { resolveSignInProviders, RateLimitExceededError, hashEmail } = require('../resolveSignInProviders');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  const snapshot = await db.collection('signInLookupAttempts').get();
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
});

function fakeAuthClient(usersByEmail) {
  return {
    async getUserByEmail(email) {
      const user = usersByEmail[email];
      if (!user) {
        const error = new Error('no user');
        error.code = 'auth/user-not-found';
        throw error;
      }
      return user;
    },
  };
}

test('reports providers for a known email', async () => {
  const authClient = fakeAuthClient({
    'alice@example.com': { providerData: [{ providerId: 'google.com' }] },
  });

  const result = await resolveSignInProviders({ authClient, db, email: 'alice@example.com' });

  assert.deepEqual(result, { exists: true, providers: ['google.com'] });
});

test('reports multiple providers when an account has linked more than one', async () => {
  const authClient = fakeAuthClient({
    'bob@example.com': { providerData: [{ providerId: 'password' }, { providerId: 'apple.com' }] },
  });

  const result = await resolveSignInProviders({ authClient, db, email: 'bob@example.com' });

  assert.deepEqual(result, { exists: true, providers: ['password', 'apple.com'] });
});

test('reports not found for an unregistered email', async () => {
  const authClient = fakeAuthClient({});

  const result = await resolveSignInProviders({ authClient, db, email: 'nobody@example.com' });

  assert.deepEqual(result, { exists: false, providers: [] });
});

test('rejects an empty email', async () => {
  const authClient = fakeAuthClient({});

  await assert.rejects(() => resolveSignInProviders({ authClient, db, email: '  ' }));
});

test('rate-limits repeated lookups for the same email', async () => {
  const authClient = fakeAuthClient({});
  const email = 'carol@example.com';

  for (let i = 0; i < 10; i += 1) {
    await resolveSignInProviders({ authClient, db, email });
  }

  await assert.rejects(
    () => resolveSignInProviders({ authClient, db, email }),
    RateLimitExceededError,
  );
});

test('rate limit is tracked per email, not globally', async () => {
  const authClient = fakeAuthClient({});

  for (let i = 0; i < 10; i += 1) {
    await resolveSignInProviders({ authClient, db, email: 'dave@example.com' });
  }

  // A different email still has its own fresh budget.
  const result = await resolveSignInProviders({ authClient, db, email: 'erin@example.com' });
  assert.deepEqual(result, { exists: false, providers: [] });
});

test('hashEmail is case/whitespace-insensitive so the rate limit cannot be trivially dodged', () => {
  assert.equal(hashEmail('Foo@Example.com'), hashEmail('  foo@example.com  '));
});
