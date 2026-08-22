// Server-side email lookup for Friends (#5) — looks up userProfiles by
// email, respecting isEmailDiscoverable. Silent no-match either way (no
// such user, or a user who's hidden their email) so the caller can't
// distinguish "no such user" from "user exists but hid their email" — no
// enumeration signal, same anti-enumeration reasoning
// resolveSignInProviders.js already established for sign-in lookups.
//
// Provider-agnostic by construction, not by new code: this app's existing
// duplicate-account-detection flow (resolveSignInProviders) already
// guarantees at most one Firebase Auth UID per email regardless of which
// provider the person used — so querying userProfiles (one doc per UID,
// written by PostSignInCoordinator on every sign-in) alone is sufficient.
//
// Rate-limited per *caller*, not per searched email — unlike
// resolveSignInProviders (which fires pre-auth, before any UID exists,
// so it has to key by email instead). Keying by callerUserID here is what
// actually matters: an attacker enumerating many different emails would
// get a fresh per-email budget every time if this were keyed by email
// instead.

const { checkAndRecordRateLimit, RateLimitExceededError } = require('./rateLimiter');

const RATE_LIMIT_MAX_ATTEMPTS = 20;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

async function findUserByEmail({ db, authClient, email, callerUserID }) {
  // Lowercased to match FirestoreUserProfileService.setEmail's own
  // normalization — a federated sign-in provider can hand back a
  // mixed-case email, but this is an exact-match Firestore query, not a
  // case-insensitive one, so a search typed in the searcher's own casing
  // (almost always lowercase) would otherwise silently never match.
  const trimmedEmail = (email || '').trim().toLowerCase();
  if (!trimmedEmail) {
    throw new Error('email is required');
  }
  if (!callerUserID) {
    throw new Error('callerUserID is required');
  }

  const allowed = await checkAndRecordRateLimit(db, {
    collection: 'findUserByEmailAttempts',
    key: callerUserID,
    maxAttempts: RATE_LIMIT_MAX_ATTEMPTS,
    windowMs: RATE_LIMIT_WINDOW_MS,
  });
  if (!allowed) {
    throw new RateLimitExceededError('Too many lookups — try again later.');
  }

  const snapshot = await db.collection('userProfiles')
    .where('email', '==', trimmedEmail)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return { found: false };
  }

  const profileDoc = snapshot.docs[0];
  if (profileDoc.data().isEmailDiscoverable === false) {
    return { found: false };
  }

  try {
    const userRecord = await authClient.getUser(profileDoc.id);
    return { found: true, userID: profileDoc.id, displayName: userRecord.displayName || null };
  } catch (error) {
    // Profile doc exists but the Auth account doesn't (e.g. a deleted
    // account whose userProfiles doc cleanup hasn't run/failed) — nothing
    // meaningful to return, so treat it the same as not found.
    if (error.code === 'auth/user-not-found') {
      return { found: false };
    }
    throw error;
  }
}

module.exports = { findUserByEmail };
