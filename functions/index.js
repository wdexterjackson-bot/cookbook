const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { applyPurchaseClaim } = require('./applyPurchaseClaim');
const { verifyTransaction } = require('./purchaseClaimVerifier');
const { resolveSignInProviders, RateLimitExceededError } = require('./resolveSignInProviders');
const { deleteGroupPermanently } = require('./deleteGroupPermanently');
const { handleAppStoreServerNotification } = require('./appStoreServerNotifications');
const { decodeAndVerifyNotification } = require('./appStoreServerNotificationVerifier');
const { sweepLapsedAnnualProMembers } = require('./sweepLapsedAnnualProMembers');

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

// Called by GroupsServicing.leaveGroup client-side, only once it's
// determined the caller is the last active member — see
// deleteGroupPermanently.js for why this can't be done from the client at
// all (every collection it touches has `allow delete: if false`).
exports.deleteGroupPermanently = onCall(async (request) => {
  const groupID = request.data && request.data.groupID;
  const callerUserID = request.auth && request.auth.uid;
  if (!callerUserID) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  try {
    return await deleteGroupPermanently({ db: getFirestore(), bucket: getStorage().bucket(), groupID, callerUserID });
  } catch (error) {
    console.error('deleteGroupPermanently failed:', error);
    throw new HttpsError('internal', error.message || 'Could not delete this cookbook right now.');
  }
});

// Apple calls this directly — there is no Firebase auth context here at
// all. All security is the JWS signature check inside
// decodeAndVerifyNotification (appStoreServerNotificationVerifier.js). The
// App Store Server Notifications V2 endpoint URL, once deployed, must be
// configured in App Store Connect and verified via Apple's sandbox
// "Request a Test Notification" tool before any real purchase flow ships.
exports.appStoreServerNotifications = onRequest(async (req, res) => {
  const signedPayload = req.body && req.body.signedPayload;
  if (!signedPayload) {
    // Malformed request, not an Apple notification at all — 400, not 200,
    // so this doesn't get silently marked as "handled" in Apple's logs.
    res.status(400).send('Missing signedPayload');
    return;
  }
  try {
    await handleAppStoreServerNotification({ db: getFirestore(), decodeAndVerifyNotification, signedPayload });
    res.status(200).send('OK');
  } catch (error) {
    // Apple retries on non-2xx — deliberate here, since a thrown error at
    // this level (verification failure, unexpected shape) is exactly the
    // case where a retry might succeed once whatever's wrong is fixed.
    console.error('appStoreServerNotifications failed:', error);
    res.status(500).send('Internal error');
  }
});

// Daily sweep for lapsed Annual Pro Memberships — deletes a lapsed member's
// personal-cookbook photos 90 days past annualProMembershipExpiresAt (never
// their Firestore recipe/cookbook data), plus day-75/day-85 warning
// markers ahead of that. Requires the Cloud Scheduler API enabled on the
// real GCP project before this actually runs in production (one-time
// console step).
exports.annualProMembershipSweep = onSchedule('every day 03:00', async () => {
  const result = await sweepLapsedAnnualProMembers({ db: getFirestore(), bucket: getStorage().bucket() });
  console.log(`annualProMembershipSweep: swept ${result.swept}, warned75 ${result.warned75}, warned85 ${result.warned85}.`);
});
