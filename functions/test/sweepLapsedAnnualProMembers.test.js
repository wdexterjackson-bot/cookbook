// Runs against the real Firestore emulator with a stubbed Storage bucket —
// same approach as deleteGroupPermanently.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { sweepLapsedAnnualProMembers } = require('../sweepLapsedAnnualProMembers');

let db;
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-08-17T12:00:00.000Z');

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  const snapshot = await db.collection('entitlements').get();
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
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

async function seedEntitlement(userID, fields) {
  await db.collection('entitlements').doc(userID).set({
    userID, tier1Credits: 0, tier2Credits: 0, isProUser: false,
    receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: Timestamp.now(),
    ...fields,
  });
}

test('deletes photos and marks imagesRemovedAt for a member lapsed more than 90 days', async () => {
  await seedEntitlement('alice', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 91 * DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/alice/': ['personalCookbooks/alice/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 1);
  assert.deepEqual(bucket.deleted, ['personalCookbooks/alice/photo1.jpg']);
  const entitlement = (await db.collection('entitlements').doc('alice').get()).data();
  assert.ok(entitlement.annualProMembershipImagesRemovedAt);
});

test('does not sweep a member still within the 90-day window', async () => {
  await seedEntitlement('bob', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 10 * DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/bob/': ['personalCookbooks/bob/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 0);
  assert.deepEqual(bucket.deleted, []);
});

test('does not sweep a lapsed member still within Apple\'s billing retry window', async () => {
  await seedEntitlement('carol', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 95 * DAY_MS)),
    annualProMembershipBillingRetryUntil: Timestamp.fromDate(new Date(NOW.getTime() + DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/carol/': ['personalCookbooks/carol/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 0);
  assert.deepEqual(bucket.deleted, []);
});

test('sweeps a lapsed member once the billing retry window has passed', async () => {
  await seedEntitlement('dana', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 95 * DAY_MS)),
    annualProMembershipBillingRetryUntil: Timestamp.fromDate(new Date(NOW.getTime() - DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/dana/': ['personalCookbooks/dana/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 1);
  assert.deepEqual(bucket.deleted, ['personalCookbooks/dana/photo1.jpg']);
});

test('is idempotent — a member already swept is skipped, not re-deleted', async () => {
  await seedEntitlement('erin', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 95 * DAY_MS)),
    annualProMembershipImagesRemovedAt: Timestamp.fromDate(new Date(NOW.getTime() - DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/erin/': ['personalCookbooks/erin/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 0);
  assert.deepEqual(bucket.deleted, []);
});

test('warns at day 75 and day 85 exactly once each, not on every run', async () => {
  await seedEntitlement('frank', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() - 80 * DAY_MS)),
  });
  const bucket = fakeBucket({});

  const first = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });
  assert.equal(first.warned75, 1);
  assert.equal(first.warned85, 0);

  const second = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });
  assert.equal(second.warned75, 0, 'day-75 marker should already be set, no re-warn');

  const entitlement = (await db.collection('entitlements').doc('frank').get()).data();
  assert.equal(entitlement.annualProMembershipWarnedAtDay75, true);
  assert.equal(entitlement.annualProMembershipWarnedAtDay85 ?? false, false);
});

test('a re-subscribed member (expiresAt pushed forward past the cutoff) is not swept', async () => {
  // Simulates a webhook-driven renewal landing between the query and the
  // per-doc re-fetch: seed with a fresh, future expiresAt from the start —
  // the query itself should simply not match this account at all.
  await seedEntitlement('gina', {
    annualProMembershipExpiresAt: Timestamp.fromDate(new Date(NOW.getTime() + 300 * DAY_MS)),
  });
  const bucket = fakeBucket({ 'personalCookbooks/gina/': ['personalCookbooks/gina/photo1.jpg'] });

  const result = await sweepLapsedAnnualProMembers({ db, bucket, now: NOW });

  assert.equal(result.swept, 0);
  assert.deepEqual(bucket.deleted, []);
});
