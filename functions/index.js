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
const { RateLimitExceededError: FriendLookupRateLimitExceededError } = require('./rateLimiter');
const { findUserByEmail } = require('./findUserByEmail');
const { deleteGroupPermanently } = require('./deleteGroupPermanently');
const { changeOwnMembership } = require('./changeOwnMembership');
const { changeMemberRole } = require('./changeMemberRole');
const { requestPairingCode, checkPairingStatus, confirmPairingCode } = require('./tvPairing');
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

// Friend discovery by email (#5) — see findUserByEmail.js for the
// anti-enumeration reasoning (silent not-found for both "no such user"
// and "user hid their email," rate-limited per caller).
exports.findUserByEmail = onCall(async (request) => {
  const email = request.data && request.data.email;
  const callerUserID = request.auth && request.auth.uid;
  if (!callerUserID) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  try {
    return await findUserByEmail({ db: getFirestore(), authClient: getAuth(), email, callerUserID });
  } catch (error) {
    if (error instanceof FriendLookupRateLimitExceededError) {
      throw new HttpsError('resource-exhausted', error.message);
    }
    console.error('findUserByEmail failed:', error);
    throw new HttpsError('internal', 'Could not look up this email right now.');
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

// Called by FirestoreGroupsService.leaveGroup/updateRole client-side only
// for the two self-targeting mutations firestore.rules can no longer
// perform as a direct write (self-leave-as-admin, self-demote) — see
// changeOwnMembership.js for why rules alone can't enforce "the last
// admin can't leave or be demoted."
exports.changeOwnMembership = onCall(async (request) => {
  const groupID = request.data && request.data.groupID;
  const action = request.data && request.data.action;
  const callerUserID = request.auth && request.auth.uid;
  if (!callerUserID) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  try {
    return await changeOwnMembership({ db: getFirestore(), groupID, action, callerUserID });
  } catch (error) {
    console.error('changeOwnMembership failed:', error);
    throw new HttpsError('failed-precondition', error.message || 'Could not update your membership right now.');
  }
});

// Called by FirestoreGroupsService.updateRole/removeMember for an admin
// acting on *someone else's* membership — see changeMemberRole.js for why
// this can't be a client-side Firestore transaction (the client SDK's
// Transaction type has no query support, only the Admin SDK's does).
exports.changeMemberRole = onCall(async (request) => {
  const groupID = request.data && request.data.groupID;
  const targetUserID = request.data && request.data.targetUserID;
  const action = request.data && request.data.action;
  const callerUserID = request.auth && request.auth.uid;
  if (!callerUserID) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  try {
    return await changeMemberRole({ db: getFirestore(), groupID, targetUserID, action, callerUserID });
  } catch (error) {
    console.error('changeMemberRole failed:', error);
    throw new HttpsError('failed-precondition', error.message || 'Could not update that member right now.');
  }
});

// Apple TV phone-pairing sign-in (tvPairing.js) — the TV is signed out
// when it calls this, so no request.auth is expected or required. Rate-
// limited by the TV-generated deviceSessionID (see tvPairing.js's own
// comment for why this collection has no firestore.rules entry at all).
exports.requestPairingCode = onCall(async (request) => {
  const deviceSessionID = request.data && request.data.deviceSessionID;
  try {
    return await requestPairingCode({ db: getFirestore(), deviceSessionID });
  } catch (error) {
    if (error instanceof FriendLookupRateLimitExceededError) {
      throw new HttpsError('resource-exhausted', error.message);
    }
    console.error('requestPairingCode failed:', error);
    throw new HttpsError('internal', error.message || 'Could not start pairing right now.');
  }
});

// Also signed-out — the TV polls this until the phone confirms. Only ever
// returns a custom token once per pairing code (tvPairing.js's
// tokenDelivered guard), so a dropped response can't be silently retried
// into a second valid token.
exports.checkPairingStatus = onCall(async (request) => {
  const code = request.data && request.data.code;
  const deviceSessionID = request.data && request.data.deviceSessionID;
  try {
    return await checkPairingStatus({ db: getFirestore(), authClient: getAuth(), code, deviceSessionID });
  } catch (error) {
    if (error instanceof FriendLookupRateLimitExceededError) {
      throw new HttpsError('resource-exhausted', error.message);
    }
    console.error('checkPairingStatus failed:', error);
    throw new HttpsError('internal', error.message || 'Could not check pairing status right now.');
  }
});

// The one call in this trio that IS authenticated — the phone confirming
// the code belongs to its own signed-in account.
exports.confirmPairingCode = onCall(async (request) => {
  const code = request.data && request.data.code;
  const callerUserID = request.auth && request.auth.uid;
  if (!callerUserID) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  try {
    return await confirmPairingCode({ db: getFirestore(), code, callerUserID });
  } catch (error) {
    if (error instanceof FriendLookupRateLimitExceededError) {
      throw new HttpsError('resource-exhausted', error.message);
    }
    console.error('confirmPairingCode failed:', error);
    throw new HttpsError('failed-precondition', error.message || 'Could not confirm this code right now.');
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
