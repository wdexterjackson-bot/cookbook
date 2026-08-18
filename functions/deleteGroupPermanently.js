// Full cascade deletion for a Family Cookbook group once its last active
// member has left: memberships, groupCookbooks, publications, their
// Storage photos, and the group doc itself. None of this is reachable
// from the client — firestore.rules sets `allow delete: if false` on
// every one of these collections, and storage.rules only lets a user
// delete files they themselves uploaded (no admin override) — so this
// always runs through the Admin SDK (via `db`/`bucket`, injected the same
// way applyPurchaseClaim.js injects verifyTransaction), which bypasses
// both rules files.

const { checkAndRecordRateLimit, RateLimitExceededError } = require('./rateLimiter');

// This is the single most destructive callable in the app — a successful
// call permanently removes a shared cookbook, its publications, and their
// photos for every member, with no undo. A legitimate caller hits this at
// most once per group per lifetime (leaving the last group they belong to),
// so a low cap here costs no real user anything while meaningfully
// narrowing a scripted-abuse window (SAFE-002/SEC-004 — this callable had
// no rate limiting at all before, unlike resolveSignInProviders).
const DELETE_GROUP_RATE_LIMIT_MAX_ATTEMPTS = 5;
const DELETE_GROUP_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

// recursiveDelete (Admin SDK only, bypasses rules the same as everything
// else here) — plain docSnap.ref.delete() doesn't cascade to
// subcollections, so without this every comment/like/rating ever left on
// one of this group's publications would survive as a permanent orphan:
// unreachable once memberships are gone (comments/likes/ratings reads
// require isMember/isSignedIn checks that resolve against data that no
// longer exists), but never actually cleaned up or stopped being billed
// for.
async function deletePublicationsForGroup(db, groupID) {
  const snapshot = await db.collection('publications').where('groupID', '==', groupID).get();
  await Promise.all(snapshot.docs.map((docSnap) => db.recursiveDelete(docSnap.ref)));
}

async function deleteGroupCookbooksForGroup(db, groupID) {
  const snapshot = await db.collection('groupCookbooks').where('groupID', '==', groupID).get();
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
}

async function deletePhotosForGroup(bucket, groupID) {
  const [files] = await bucket.getFiles({ prefix: `publications/${groupID}/` });
  await Promise.all(files.map((file) => file.delete()));
}

async function deleteGroupPermanently({ db, bucket, groupID, callerUserID }) {
  const trimmedGroupID = (groupID || '').trim();
  if (!trimmedGroupID) {
    throw new Error('groupID is required');
  }

  const allowed = await checkAndRecordRateLimit(db, {
    collection: 'deleteGroupPermanentlyAttempts',
    key: callerUserID,
    maxAttempts: DELETE_GROUP_RATE_LIMIT_MAX_ATTEMPTS,
    windowMs: DELETE_GROUP_RATE_LIMIT_WINDOW_MS,
  });
  if (!allowed) {
    throw new RateLimitExceededError('Too many deletion attempts — try again later.');
  }

  const groupRef = db.collection('groups').doc(trimmedGroupID);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    // Already gone — treat as success so a retried call is safe.
    return { deleted: false };
  }

  const membershipsSnapshot = await db.collection('memberships').where('groupID', '==', trimmedGroupID).get();
  const activeMemberships = membershipsSnapshot.docs
    .map((docSnap) => docSnap.data())
    .filter((data) => data.status === 'active');
  // Mirrors GroupPolicy.isLastActiveMember on the client exactly — the
  // client only ever calls this callable when the caller is the sole
  // remaining active member, but that invariant was previously enforced
  // only client-side. Re-checking it here server-side is load-bearing: any
  // active member (not just the last one) could otherwise call this
  // callable directly with an arbitrary groupID and delete a shared
  // cookbook out from under everyone else.
  const isLastActiveMember = activeMemberships.length === 1 && activeMemberships[0].userID === callerUserID;
  if (!isLastActiveMember) {
    throw new Error('Only the last active member of this cookbook can permanently delete it.');
  }

  await Promise.all(membershipsSnapshot.docs.map((docSnap) => docSnap.ref.delete()));
  await deleteGroupCookbooksForGroup(db, trimmedGroupID);
  await deletePublicationsForGroup(db, trimmedGroupID);
  await deletePhotosForGroup(bucket, trimmedGroupID);

  await groupRef.delete();

  return { deleted: true };
}

module.exports = { deleteGroupPermanently };
