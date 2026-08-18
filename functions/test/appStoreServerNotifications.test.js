// Runs against the real Firestore emulator using the Admin SDK.
// decodeAndVerifyNotification is stubbed rather than real — same reasoning
// as applyPurchaseClaim.test.js stubbing verifyTransaction: no Apple root
// certificates or genuinely Apple-signed payload available offline. This
// proves handleAppStoreServerNotification's own logic (routing, idempotency,
// entitlement resolution/updates) for real.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { handleAppStoreServerNotification } = require('../appStoreServerNotifications');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const name of ['entitlements', 'processedAppStoreNotifications']) {
    const snapshot = await db.collection(name).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

function fakeDecoder(decoded) {
  return async () => decoded;
}

async function seedEntitlement(userID, fields) {
  await db.collection('entitlements').doc(userID).set({
    userID, tier1Credits: 0, tier2Credits: 0, isProUser: false,
    receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: Timestamp.now(),
    ...fields,
  });
}

test('SUBSCRIBED sets expiresAt and clears sweep/billing-retry/warn markers', async () => {
  await seedEntitlement('alice', {
    annualProMembershipOriginalTransactionID: 'orig-1',
    annualProMembershipImagesRemovedAt: Timestamp.now(),
    annualProMembershipBillingRetryUntil: Timestamp.now(),
    annualProMembershipWarnedAtDay75: true,
    annualProMembershipWarnedAtDay85: true,
  });
  const expiresMs = Date.parse('2027-08-17T00:00:00.000Z');

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'SUBSCRIBED',
      notificationUUID: 'n1',
      originalTransactionId: 'orig-1',
      productId: 'VibeApp.cookbook.annualProMembership',
      expiresDate: expiresMs,
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('alice').get()).data();
  assert.equal(entitlement.annualProMembershipExpiresAt.toMillis(), expiresMs);
  assert.equal(entitlement.annualProMembershipImagesRemovedAt, null);
  assert.equal(entitlement.annualProMembershipBillingRetryUntil, null);
  assert.equal(entitlement.annualProMembershipWarnedAtDay75, null);
  assert.equal(entitlement.annualProMembershipWarnedAtDay85, null);
});

test('DID_RENEW extends expiresAt the same way SUBSCRIBED does', async () => {
  await seedEntitlement('bob', { annualProMembershipOriginalTransactionID: 'orig-2' });
  const expiresMs = Date.parse('2028-01-01T00:00:00.000Z');

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'DID_RENEW',
      notificationUUID: 'n2',
      originalTransactionId: 'orig-2',
      productId: 'VibeApp.cookbook.annualProMembership',
      expiresDate: expiresMs,
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('bob').get()).data();
  assert.equal(entitlement.annualProMembershipExpiresAt.toMillis(), expiresMs);
});

test('DID_CHANGE_RENEWAL_STATUS records willRenew without touching expiresAt', async () => {
  const originalExpiry = Timestamp.fromDate(new Date('2027-01-01'));
  await seedEntitlement('carol', {
    annualProMembershipOriginalTransactionID: 'orig-3',
    annualProMembershipExpiresAt: originalExpiry,
  });

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'DID_CHANGE_RENEWAL_STATUS',
      notificationUUID: 'n3',
      originalTransactionId: 'orig-3',
      productId: 'VibeApp.cookbook.annualProMembership',
      autoRenewStatus: 0,
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('carol').get()).data();
  assert.equal(entitlement.annualProMembershipWillRenew, false);
  assert.equal(entitlement.annualProMembershipExpiresAt.toMillis(), originalExpiry.toMillis());
});

test('DID_FAIL_TO_RENEW during the billing retry period sets billingRetryUntil, not a lapse', async () => {
  await seedEntitlement('dana', { annualProMembershipOriginalTransactionID: 'orig-4' });
  const graceMs = Date.parse('2026-09-01T00:00:00.000Z');

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'DID_FAIL_TO_RENEW',
      notificationUUID: 'n4',
      originalTransactionId: 'orig-4',
      productId: 'VibeApp.cookbook.annualProMembership',
      isInBillingRetryPeriod: true,
      gracePeriodExpiresDate: graceMs,
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('dana').get()).data();
  assert.equal(entitlement.annualProMembershipBillingRetryUntil.toMillis(), graceMs);
});

test('DID_FAIL_TO_RENEW outside the retry period makes no write', async () => {
  await seedEntitlement('erin', { annualProMembershipOriginalTransactionID: 'orig-5' });

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'DID_FAIL_TO_RENEW',
      notificationUUID: 'n5',
      originalTransactionId: 'orig-5',
      productId: 'VibeApp.cookbook.annualProMembership',
      isInBillingRetryPeriod: false,
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('erin').get()).data();
  assert.equal(entitlement.annualProMembershipBillingRetryUntil, undefined);
});

test('EXPIRED and an unhandled type (PRICE_INCREASE) both make no write', async () => {
  const originalExpiry = Timestamp.fromDate(new Date('2026-01-01'));
  await seedEntitlement('frank', {
    annualProMembershipOriginalTransactionID: 'orig-6',
    annualProMembershipExpiresAt: originalExpiry,
  });

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'EXPIRED', notificationUUID: 'n6', originalTransactionId: 'orig-6',
      productId: 'VibeApp.cookbook.annualProMembership',
    }),
    signedPayload: 'stub',
  });
  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'PRICE_INCREASE', notificationUUID: 'n7', originalTransactionId: 'orig-6',
      productId: 'VibeApp.cookbook.annualProMembership',
    }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('frank').get()).data();
  assert.equal(entitlement.annualProMembershipExpiresAt.toMillis(), originalExpiry.toMillis());
});

test('is idempotent — a redelivered notification (same notificationUUID) is not reapplied', async () => {
  await seedEntitlement('gina', { annualProMembershipOriginalTransactionID: 'orig-7' });
  const decoded = {
    notificationType: 'SUBSCRIBED',
    notificationUUID: 'n8',
    originalTransactionId: 'orig-7',
    productId: 'VibeApp.cookbook.annualProMembership',
    expiresDate: Date.parse('2027-01-01T00:00:00.000Z'),
  };

  await handleAppStoreServerNotification({ db, decodeAndVerifyNotification: fakeDecoder(decoded), signedPayload: 'stub' });
  // A second delivery with a different (later) expiresDate must not apply —
  // the first processing already claimed this notificationUUID.
  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({ ...decoded, expiresDate: Date.parse('2030-01-01T00:00:00.000Z') }),
    signedPayload: 'stub',
  });

  const entitlement = (await db.collection('entitlements').doc('gina').get()).data();
  assert.equal(entitlement.annualProMembershipExpiresAt.toMillis(), decoded.expiresDate);
});

test('an unresolvable originalTransactionId (no matching entitlement) is logged, not thrown', async () => {
  await assert.doesNotReject(() => handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'SUBSCRIBED', notificationUUID: 'n9', originalTransactionId: 'no-such-transaction',
      productId: 'VibeApp.cookbook.annualProMembership', expiresDate: Date.now(),
    }),
    signedPayload: 'stub',
  }));
});

test('a renewal updates every entitlement doc sharing one originalTransactionId (Family Sharing)', async () => {
  // Under Apple's default Family Sharing for auto-renewable subscriptions,
  // each family member's device independently submits its own purchaseClaims
  // doc for the same underlying subscription, so more than one entitlements
  // doc can carry the same originalTransactionId. A DID_RENEW must not
  // stamp just one of them — see the real bug this guards against in
  // findEntitlementsByOriginalTransactionID's own doc comment.
  await seedEntitlement('helen', { annualProMembershipOriginalTransactionID: 'orig-family' });
  await seedEntitlement('irene', { annualProMembershipOriginalTransactionID: 'orig-family' });
  await seedEntitlement('june', { annualProMembershipOriginalTransactionID: 'other-transaction' });
  const expiresMs = Date.parse('2027-09-01T00:00:00.000Z');

  await handleAppStoreServerNotification({
    db,
    decodeAndVerifyNotification: fakeDecoder({
      notificationType: 'DID_RENEW',
      notificationUUID: 'n10',
      originalTransactionId: 'orig-family',
      productId: 'VibeApp.cookbook.annualProMembership',
      expiresDate: expiresMs,
    }),
    signedPayload: 'stub',
  });

  const helen = (await db.collection('entitlements').doc('helen').get()).data();
  const irene = (await db.collection('entitlements').doc('irene').get()).data();
  const june = (await db.collection('entitlements').doc('june').get()).data();
  assert.equal(helen.annualProMembershipExpiresAt.toMillis(), expiresMs);
  assert.equal(irene.annualProMembershipExpiresAt.toMillis(), expiresMs);
  assert.equal(june.annualProMembershipExpiresAt, undefined);
});
