const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { applyPurchaseClaim } = require('./applyPurchaseClaim');
const { verifyTransaction } = require('./purchaseClaimVerifier');
const { resolveSignInProviders, RateLimitExceededError } = require('./resolveSignInProviders');

initializeApp();

// firestore.rules lets a client only ever create a purchaseClaims doc, never
// mark it processed or grant itself an entitlement — this function is the
// one thing (via the Admin SDK) that's allowed to do the latter, and only
// after independently re-verifying the signed transaction against Apple.
exports.purchaseClaims = onDocumentCreated('purchaseClaims/{claimID}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const claimData = snapshot.data();
  const db = getFirestore();

  try {
    await applyPurchaseClaim({ db, claimID: event.params.claimID, claimData, verifyTransaction });
  } catch (error) {
    // Left as an unprocessed claim doc — safe to inspect and, once the
    // underlying issue is fixed, safe to reprocess by hand (the doc ID is
    // the stable Apple transaction ID).
    console.error(`Failed to apply purchase claim ${event.params.claimID}:`, error);
  }
});

// Client-side duplicate-account detection (mandatory sign-in gate work):
// resolves which provider(s) an email is already registered under. Called
// reactively, only after a real sign-up/sign-in attempt already indicated
// a conflict — never as the user types — and rate-limited per email on top
// of that, since this is otherwise exactly the enumeration lookup Firebase
// deprecated fetchSignInMethodsForEmail to prevent.
exports.resolveSignInProviders = onCall(async (request) => {
  const email = request.data && request.data.email;
  try {
    return await resolveSignInProviders({ authClient: getAuth(), db: getFirestore(), email });
  } catch (error) {
    if (error instanceof RateLimitExceededError) {
      throw new HttpsError('resource-exhausted', error.message);
    }
    console.error('resolveSignInProviders failed:', error);
    throw new HttpsError('internal', 'Could not check this email right now.');
  }
});
