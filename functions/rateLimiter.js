// Generic per-key rate limiter, factored out of the pattern
// resolveSignInProviders.js established first — a Firestore transaction
// keyed by a hashed identifier, counting attempts inside a rolling window.
// deleteGroupPermanently.js is the first other caller (SEC-004/SAFE-002:
// destructive/abuse-relevant Cloud Functions had no rate limiting at all
// besides resolveSignInProviders, which is a real gap the PRD calls out).
// resolveSignInProviders.js keeps its own copy of this logic rather than
// being refactored to call this — it already has passing tests against its
// own inline version, and touching a working, tested file isn't worth the
// risk here.

const crypto = require('crypto');

class RateLimitExceededError extends Error {
  constructor(message) {
    super(message || 'Too many attempts — try again later.');
  }
}

// Not cryptographic — just keeps raw identifiers (user IDs, emails) out of
// Firestore document IDs/logs more than strictly necessary.
function hashKey(key) {
  return crypto.createHash('sha256').update(String(key).trim().toLowerCase()).digest('hex');
}

/// Returns true if `key` is still within its rate limit (and records this
/// attempt); false if the limit has been hit for the current window.
/// `collection` scopes the bookkeeping doc so unrelated rate limits (e.g.
/// sign-in lookups vs. group deletions) never collide on the same key.
async function checkAndRecordRateLimit(db, { collection, key, maxAttempts, windowMs }) {
  const ref = db.collection(collection).doc(hashKey(key));
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.exists ? snap.data() : { windowStart: now, count: 0 };

    const windowExpired = now - data.windowStart > windowMs;
    const windowStart = windowExpired ? now : data.windowStart;
    const count = windowExpired ? 0 : data.count;

    if (count >= maxAttempts) {
      return false;
    }

    transaction.set(ref, { windowStart, count: count + 1 }, { merge: true });
    return true;
  });
}

module.exports = { checkAndRecordRateLimit, hashKey, RateLimitExceededError };
