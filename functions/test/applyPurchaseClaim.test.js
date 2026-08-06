// Runs against the real Firestore emulator (via `firebase emulators:exec`
// from the repo root, same harness as ../../rules-tests) using the Admin
// SDK, which always bypasses firestore.rules — appropriate here since this
// is testing server-side function logic, not client permissions.
//
// verifyTransaction is stubbed rather than real: we have no Apple root
// certificates or a genuinely Apple-signed JWS available offline. This
// proves applyPurchaseClaim's own logic (matching, idempotency, entitlement
// math) for real; see purchaseClaimVerifier.js for the unverified part.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { applyPurchaseClaim } = require('../applyPurchaseClaim');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const name of ['entitlements', 'processedPurchaseTransactions']) {
    const snapshot = await db.collection(name).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

function fakeVerifier(decoded) {
  return async () => decoded;
}

test('grants hasFamilyUser for the lifetime product', async () => {
  await db.collection('entitlements').doc('alice').set({
    userID: 'alice', creationCredits: 3, hasFamilyUser: false,
    familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: Timestamp.now(),
  });

  await applyPurchaseClaim({
    db,
    claimID: 'txn1',
    claimData: { userID: 'alice', productID: 'VibeApp.cookbook.familyUser.lifetime', transactionID: 'txn1', jwsRepresentation: 'stub' },
    verifyTransaction: fakeVerifier({ transactionId: 'txn1', productId: 'VibeApp.cookbook.familyUser.lifetime' }),
  });

  const entitlement = (await db.collection('entitlements').doc('alice').get()).data();
  assert.equal(entitlement.hasFamilyUser, true);
  assert.equal(entitlement.creationCredits, 3);
});

test('increments creationCredits for the consumable product', async () => {
  await db.collection('entitlements').doc('bob').set({
    userID: 'bob', creationCredits: 1, hasFamilyUser: false,
    familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: Timestamp.now(),
  });

  await applyPurchaseClaim({
    db,
    claimID: 'txn2',
    claimData: { userID: 'bob', productID: 'VibeApp.cookbook.groupCreationCredit', transactionID: 'txn2', jwsRepresentation: 'stub' },
    verifyTransaction: fakeVerifier({ transactionId: 'txn2', productId: 'VibeApp.cookbook.groupCreationCredit' }),
  });

  const entitlement = (await db.collection('entitlements').doc('bob').get()).data();
  assert.equal(entitlement.creationCredits, 2);
});

test('creates an entitlement doc from scratch when none exists yet', async () => {
  await applyPurchaseClaim({
    db,
    claimID: 'txn5',
    claimData: { userID: 'dave', productID: 'VibeApp.cookbook.groupCreationCredit', transactionID: 'txn5', jwsRepresentation: 'stub' },
    verifyTransaction: fakeVerifier({ transactionId: 'txn5', productId: 'VibeApp.cookbook.groupCreationCredit' }),
  });

  const entitlement = (await db.collection('entitlements').doc('dave').get()).data();
  assert.equal(entitlement.creationCredits, 1);
  assert.equal(entitlement.hasFamilyUser, false);
});

test('is idempotent for the same Apple transaction ID', async () => {
  const claimData = { userID: 'carol', productID: 'VibeApp.cookbook.groupCreationCredit', transactionID: 'txn3', jwsRepresentation: 'stub' };
  const verifyTransaction = fakeVerifier({ transactionId: 'txn3', productId: 'VibeApp.cookbook.groupCreationCredit' });

  await applyPurchaseClaim({ db, claimID: 'txn3', claimData, verifyTransaction });
  await applyPurchaseClaim({ db, claimID: 'txn3', claimData, verifyTransaction });

  const entitlement = (await db.collection('entitlements').doc('carol').get()).data();
  assert.equal(entitlement.creationCredits, 1);
});

test('rejects a claim whose decoded transaction does not match the submitted fields', async () => {
  await assert.rejects(() => applyPurchaseClaim({
    db,
    claimID: 'txn4',
    claimData: { userID: 'mallory', productID: 'VibeApp.cookbook.familyUser.lifetime', transactionID: 'txn4', jwsRepresentation: 'stub' },
    verifyTransaction: fakeVerifier({ transactionId: 'DIFFERENT', productId: 'VibeApp.cookbook.familyUser.lifetime' }),
  }));

  const entitlement = await db.collection('entitlements').doc('mallory').get();
  assert.equal(entitlement.exists, false);
});
