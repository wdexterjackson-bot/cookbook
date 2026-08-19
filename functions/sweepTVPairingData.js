// Daily scheduled sweep for Apple TV phone-pairing sign-in data
// (tvPairing.js) — nothing in that file ever deletes a document, so
// tvPairingRequests/{code} accumulates one new doc per pairing attempt
// forever (most abandoned/expired within the 5-minute code lifetime), and
// the three rate-limit bookkeeping collections keep every caller's doc
// around indefinitely too, even though checkAndRecordRateLimit already
// treats a doc past its own window as stale and silently resets it in
// place. Neither needs to be kept once its useful life is over — a code
// is already functionally dead after expiresAt, and a rate-limit window
// that's already reset serves no purpose being retained. Deleting these
// is pure data-minimization/storage hygiene, not a correctness fix:
// nothing in tvPairing.js behaves any differently whether or not this
// sweep has run — same "photos only, never blocks anything" spirit as
// sweepLapsedAnnualProMembers.js.
//
// Both queries filter on a single field (range), which Firestore indexes
// automatically — no firestore.indexes.json entry needed, same note as
// sweepLapsedAnnualProMembers.js.

const TV_PAIRING_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000; // 24h past expiresAt
// Comfortably longer than the longest rate-limit window tvPairing.js
// defines (1h, for request/confirm attempts) — a bookkeeping doc whose
// window started this long ago has already reset and is dead weight.
const RATE_LIMIT_BOOKKEEPING_GRACE_PERIOD_MS = 24 * 60 * 60 * 1000;

const RATE_LIMIT_COLLECTIONS = ['tvPairingRequestAttempts', 'tvPairingPollAttempts', 'tvPairingConfirmAttempts'];

async function deleteAll(snapshot) {
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  return snapshot.docs.length;
}

async function sweepTVPairingData({ db, now = new Date() }) {
  const nowMs = now.getTime();

  const expiredPairingRequests = await db.collection('tvPairingRequests')
    .where('expiresAt', '<', nowMs - TV_PAIRING_GRACE_PERIOD_MS)
    .get();
  const deletedPairingRequests = await deleteAll(expiredPairingRequests);

  let deletedRateLimitDocs = 0;
  for (const collectionName of RATE_LIMIT_COLLECTIONS) {
    const staleDocs = await db.collection(collectionName)
      .where('windowStart', '<', nowMs - RATE_LIMIT_BOOKKEEPING_GRACE_PERIOD_MS)
      .get();
    deletedRateLimitDocs += await deleteAll(staleDocs);
  }

  return { deletedPairingRequests, deletedRateLimitDocs };
}

module.exports = { sweepTVPairingData, TV_PAIRING_GRACE_PERIOD_MS, RATE_LIMIT_BOOKKEEPING_GRACE_PERIOD_MS };
