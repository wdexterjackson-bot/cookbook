// Daily scheduled sweep for the Annual Pro Membership subscription (and its
// discount-code-credit stepping stone, which sets the same
// annualProMembershipExpiresAt field). Mirrors deleteGroupPermanently.js's
// bucket.getFiles({ prefix }) delete idiom, applied to a lapsed member's
// personal-cookbook photos rather than a group's. Never touches Firestore
// cookbook/recipe docs — Storage photos only, per the confirmed "photos
// only" decision.
//
// Both queries below filter on a single field (range or equality), which
// Firestore indexes automatically — no firestore.indexes.json entry needed.

const SWEEP_GRACE_PERIOD_MS = 90 * 24 * 60 * 60 * 1000; // 90 days
const WARN_AT_DAY_75_MS = 75 * 24 * 60 * 60 * 1000;
const WARN_AT_DAY_85_MS = 85 * 24 * 60 * 60 * 1000;

async function deletePhotosForOwner(bucket, ownerUserID) {
  const [files] = await bucket.getFiles({ prefix: `personalCookbooks/${ownerUserID}/` });
  await Promise.all(files.map((file) => file.delete()));
}

function toDateOrNull(value) {
  if (!value) return null;
  return typeof value.toDate === 'function' ? value.toDate() : value;
}

async function sweepLapsedAnnualProMembers({ db, bucket, now = new Date() }) {
  const deletionCutoff = new Date(now.getTime() - SWEEP_GRACE_PERIOD_MS);
  const warnAt75Cutoff = new Date(now.getTime() - WARN_AT_DAY_75_MS);
  const warnAt85Cutoff = new Date(now.getTime() - WARN_AT_DAY_85_MS);

  const lapsedSnapshot = await db.collection('entitlements')
    .where('annualProMembershipExpiresAt', '<', deletionCutoff)
    .get();

  let swept = 0;
  for (const docSnap of lapsedSnapshot.docs) {
    // Re-fetch at delete time — guards a same-run re-subscribe race between
    // the query above and this iteration (gap: a webhook-driven renewal
    // landing mid-sweep must never lose photos it shouldn't have lost).
    const freshSnap = await docSnap.ref.get();
    const data = freshSnap.data();
    if (!data) continue;
    if (data.annualProMembershipImagesRemovedAt) continue; // already swept

    const expiresAt = toDateOrNull(data.annualProMembershipExpiresAt);
    if (!expiresAt || expiresAt >= deletionCutoff) continue; // re-subscribed since the query ran

    const billingRetryUntil = toDateOrNull(data.annualProMembershipBillingRetryUntil);
    if (billingRetryUntil && billingRetryUntil > now) continue; // Apple is still retrying — not lapsed yet

    await deletePhotosForOwner(bucket, docSnap.id);
    await docSnap.ref.update({ annualProMembershipImagesRemovedAt: now });
    swept += 1;
  }

  // Day-75/day-85 warnings — independent of the deletion pass above, each
  // dedup'd by its own marker so a lapsed-but-unswept account (e.g. still
  // in its billing-retry window) is warned once per touchpoint, not on
  // every daily run.
  const warned75 = await warnOnce(db, {
    cutoff: warnAt75Cutoff,
    markerField: 'annualProMembershipWarnedAtDay75',
  });
  const warned85 = await warnOnce(db, {
    cutoff: warnAt85Cutoff,
    markerField: 'annualProMembershipWarnedAtDay85',
  });

  return { swept, warned75, warned85 };
}

async function warnOnce(db, { cutoff, markerField }) {
  const snapshot = await db.collection('entitlements')
    .where('annualProMembershipExpiresAt', '<', cutoff)
    .get();

  let warned = 0;
  for (const docSnap of snapshot.docs) {
    const data = docSnap.data();
    if (data[markerField]) continue;
    if (data.annualProMembershipImagesRemovedAt) continue; // already fully swept, nothing left to warn about
    await docSnap.ref.update({ [markerField]: true });
    warned += 1;
  }
  return warned;
}

module.exports = { sweepLapsedAnnualProMembers, SWEEP_GRACE_PERIOD_MS };
