// Runs against the real Firestore emulator — same approach as
// sweepLapsedAnnualProMembers.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { sweepTVPairingData, TV_PAIRING_GRACE_PERIOD_MS, RATE_LIMIT_BOOKKEEPING_GRACE_PERIOD_MS } = require('../sweepTVPairingData');

let db;
const HOUR_MS = 60 * 60 * 1000;
const NOW = new Date('2026-08-19T12:00:00.000Z');
const NOW_MS = NOW.getTime();

const COLLECTIONS = ['tvPairingRequests', 'tvPairingRequestAttempts', 'tvPairingPollAttempts', 'tvPairingConfirmAttempts'];

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const collectionName of COLLECTIONS) {
    const snapshot = await db.collection(collectionName).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

test('deletes a pairing request whose expiry is past the grace period', async () => {
  await db.collection('tvPairingRequests').doc('AB12CD').set({
    status: 'confirmed', deviceSessionID: 'session-1', createdAt: NOW_MS - TV_PAIRING_GRACE_PERIOD_MS - 2 * HOUR_MS,
    expiresAt: NOW_MS - TV_PAIRING_GRACE_PERIOD_MS - HOUR_MS, confirmedUserID: 'alice', tokenDelivered: true,
  });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedPairingRequests, 1);
  const remaining = await db.collection('tvPairingRequests').doc('AB12CD').get();
  assert.equal(remaining.exists, false);
});

test('keeps a pairing request that expired recently but is still within its grace period', async () => {
  await db.collection('tvPairingRequests').doc('XY99ZZ').set({
    status: 'pending', deviceSessionID: 'session-2', createdAt: NOW_MS - HOUR_MS, expiresAt: NOW_MS - 60 * 1000,
  });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedPairingRequests, 0);
  const remaining = await db.collection('tvPairingRequests').doc('XY99ZZ').get();
  assert.equal(remaining.exists, true);
});

test('keeps a pairing request that has not expired at all — someone is mid-pairing', async () => {
  await db.collection('tvPairingRequests').doc('LIVE01').set({
    status: 'pending', deviceSessionID: 'session-3', createdAt: NOW_MS, expiresAt: NOW_MS + 4 * 60 * 1000,
  });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedPairingRequests, 0);
  const remaining = await db.collection('tvPairingRequests').doc('LIVE01').get();
  assert.equal(remaining.exists, true);
});

test('deletes stale rate-limit bookkeeping docs whose window reset long ago, across all three collections', async () => {
  const staleWindowStart = NOW_MS - RATE_LIMIT_BOOKKEEPING_GRACE_PERIOD_MS - HOUR_MS;
  await db.collection('tvPairingRequestAttempts').doc('hash1').set({ windowStart: staleWindowStart, count: 3 });
  await db.collection('tvPairingPollAttempts').doc('hash2').set({ windowStart: staleWindowStart, count: 40 });
  await db.collection('tvPairingConfirmAttempts').doc('hash3').set({ windowStart: staleWindowStart, count: 1 });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedRateLimitDocs, 3);
  for (const [collectionName, docId] of [['tvPairingRequestAttempts', 'hash1'], ['tvPairingPollAttempts', 'hash2'], ['tvPairingConfirmAttempts', 'hash3']]) {
    const remaining = await db.collection(collectionName).doc(docId).get();
    assert.equal(remaining.exists, false, `expected ${collectionName}/${docId} to be deleted`);
  }
});

test('keeps a rate-limit bookkeeping doc whose window is still active', async () => {
  await db.collection('tvPairingRequestAttempts').doc('hash-active').set({ windowStart: NOW_MS - 10 * 60 * 1000, count: 2 });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedRateLimitDocs, 0);
  const remaining = await db.collection('tvPairingRequestAttempts').doc('hash-active').get();
  assert.equal(remaining.exists, true);
});

test('is idempotent — a second run against already-swept data deletes nothing and does not throw', async () => {
  await db.collection('tvPairingRequests').doc('OLD001').set({
    status: 'expired', deviceSessionID: 'session-4', createdAt: NOW_MS - 3 * 24 * HOUR_MS, expiresAt: NOW_MS - 2 * 24 * HOUR_MS,
  });

  const first = await sweepTVPairingData({ db, now: NOW });
  assert.equal(first.deletedPairingRequests, 1);

  const second = await sweepTVPairingData({ db, now: NOW });
  assert.equal(second.deletedPairingRequests, 0);
  assert.equal(second.deletedRateLimitDocs, 0);
});

test('a mix of expired, grace-period, and live requests only sweeps the truly expired one', async () => {
  await db.collection('tvPairingRequests').doc('EXPIRED').set({
    status: 'pending', deviceSessionID: 's1', createdAt: NOW_MS, expiresAt: NOW_MS - TV_PAIRING_GRACE_PERIOD_MS - HOUR_MS,
  });
  await db.collection('tvPairingRequests').doc('GRACE01').set({
    status: 'pending', deviceSessionID: 's2', createdAt: NOW_MS, expiresAt: NOW_MS - 60 * 1000,
  });
  await db.collection('tvPairingRequests').doc('LIVE002').set({
    status: 'pending', deviceSessionID: 's3', createdAt: NOW_MS, expiresAt: NOW_MS + 60 * 1000,
  });

  const result = await sweepTVPairingData({ db, now: NOW });

  assert.equal(result.deletedPairingRequests, 1);
  assert.equal((await db.collection('tvPairingRequests').doc('EXPIRED').get()).exists, false);
  assert.equal((await db.collection('tvPairingRequests').doc('GRACE01').get()).exists, true);
  assert.equal((await db.collection('tvPairingRequests').doc('LIVE002').get()).exists, true);
});
