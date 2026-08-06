// Core logic for "which sign-in provider(s) does this email use" —
// deliberately server-side (Admin SDK), since Firebase disabled the
// client-side equivalent (fetchSignInMethodsForEmail) for anti-enumeration
// reasons. `authClient` is injected (real admin.auth() in production, a
// stub in tests) — same reasoning as applyPurchaseClaim.js injecting
// verifyTransaction, since seeding a real Auth-emulator user for every
// test case is unnecessary ceremony when this file's own logic (provider
// mapping + rate limiting) is what needs proving. `db` is real Firestore
// (the emulator in tests) since the rate-limit bookkeeping itself is
// exactly what we want to exercise for real.

const crypto = require('crypto');

const RATE_LIMIT_MAX_ATTEMPTS = 10;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

class RateLimitExceededError extends Error {
  constructor() {
    super('Too many lookups for this email — try again later.');
  }
}

// Not cryptographic — just keeps raw email addresses out of Firestore
// document IDs (which have their own character restrictions) and out of
// logs/paths more than strictly necessary.
function hashEmail(email) {
  return crypto.createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
}

async function checkAndRecordRateLimit(db, email) {
  const ref = db.collection('signInLookupAttempts').doc(hashEmail(email));
  const now = Date.now();

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.exists ? snap.data() : { windowStart: now, count: 0 };

    const windowExpired = now - data.windowStart > RATE_LIMIT_WINDOW_MS;
    const windowStart = windowExpired ? now : data.windowStart;
    const count = windowExpired ? 0 : data.count;

    if (count >= RATE_LIMIT_MAX_ATTEMPTS) {
      return false;
    }

    transaction.set(ref, { windowStart, count: count + 1 }, { merge: true });
    return true;
  });
}

async function resolveSignInProviders({ authClient, db, email }) {
  const trimmedEmail = (email || '').trim();
  if (!trimmedEmail) {
    throw new Error('email is required');
  }

  const allowed = await checkAndRecordRateLimit(db, trimmedEmail);
  if (!allowed) {
    throw new RateLimitExceededError();
  }

  try {
    const userRecord = await authClient.getUserByEmail(trimmedEmail);
    const providers = userRecord.providerData.map((provider) => provider.providerId);
    return { exists: true, providers };
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return { exists: false, providers: [] };
    }
    throw error;
  }
}

module.exports = { resolveSignInProviders, checkAndRecordRateLimit, hashEmail, RateLimitExceededError };
