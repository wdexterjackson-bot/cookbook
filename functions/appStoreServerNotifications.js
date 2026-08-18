// Core business logic for an incoming App Store Server Notification V2 —
// the real source of truth for Annual Pro Membership renewals/cancellations
// (StoreKit never hands the client a fresh JWS to resubmit on its own).
// decodeAndVerifyNotification is injected (real Apple verification in
// production via appStoreServerNotificationVerifier.js, a stub in tests),
// same shape as applyPurchaseClaim.js's verifyTransaction seam.
//
// This is the first onRequest (no Firebase auth context — Apple calls it
// directly) function in this codebase. All security is the JWS signature
// check inside decodeAndVerifyNotification; there is no other authorization
// layer here. Always resolves (never throws past the top level) and always
// responds 200 for a payload it doesn't need to act on, so Apple doesn't
// retry indefinitely on something this function intentionally ignores.
//
// Deliberately not implemented: cross-checking the notification's
// environment (Sandbox/Production) against a previously-recorded value on
// the entitlement doc before writing. The original design considered this
// as defense-in-depth against a stray sandbox notification touching
// production data, but called it out as unlikely in practice (Apple
// transaction IDs shouldn't collide across environments) — left as a
// documented, deferred hardening step rather than added speculatively.

const ANNUAL_PRO_MEMBERSHIP_PRODUCT_ID = 'VibeApp.cookbook.annualProMembership';

// Not `.limit(1)`: under Apple's default Family Sharing for auto-renewable
// subscriptions, each family member's own device independently submits its
// own purchaseClaims doc for the *same* originalTransactionId (deduped only
// per-transaction, not per-originalTransactionId — see applyPurchaseClaim.js)
// resulting in several entitlements docs sharing one originalTransactionId.
// A renewal/cancellation notification has to update all of them, or every
// family member but the first ever resolved gets silently stranded on a
// stale expiry and eventually swept as lapsed despite an actively-renewing
// subscription.
async function findEntitlementsByOriginalTransactionID(db, originalTransactionId) {
  const snapshot = await db.collection('entitlements')
    .where('annualProMembershipOriginalTransactionID', '==', originalTransactionId)
    .get();
  return snapshot.docs;
}

async function handleAppStoreServerNotification({ db, decodeAndVerifyNotification, signedPayload }) {
  const decoded = await decodeAndVerifyNotification(signedPayload);

  if (!decoded.notificationUUID) {
    // Malformed/unverifiable — nothing safe to do with this.
    console.error('appStoreServerNotifications: decoded payload missing notificationUUID, dropping.');
    return;
  }

  const processedRef = db.collection('processedAppStoreNotifications').doc(decoded.notificationUUID);
  const processedSnap = await processedRef.get();
  if (processedSnap.exists) {
    // Apple retries notifications until it gets a 2xx — a redelivery of one
    // already applied must never double-apply.
    return;
  }

  if (decoded.productId && decoded.productId !== ANNUAL_PRO_MEMBERSHIP_PRODUCT_ID) {
    // Not this feature's product — record as processed so a redelivery
    // short-circuits above, but there's nothing else to do.
    await processedRef.set({ notificationType: decoded.notificationType, processedAt: new Date() });
    return;
  }

  const entitlementDocs = decoded.originalTransactionId
    ? await findEntitlementsByOriginalTransactionID(db, decoded.originalTransactionId)
    : [];

  if (entitlementDocs.length === 0) {
    // No account resolved to this originalTransactionId yet — most likely
    // the very first SUBSCRIBED notification racing ahead of
    // applyPurchaseClaim.js's own claim-submission path, or a notification
    // type (e.g. TEST) with no real transaction behind it at all. Logged,
    // not thrown, so Apple doesn't retry forever on something that may
    // simply resolve itself.
    console.log(`appStoreServerNotifications: no entitlement found for originalTransactionId ${decoded.originalTransactionId} (type ${decoded.notificationType}).`);
    await processedRef.set({ notificationType: decoded.notificationType, processedAt: new Date() });
    return;
  }

  const updates = updatesFor(decoded);
  if (updates) {
    await Promise.all(entitlementDocs.map((doc) => doc.ref.update(updates)));
  }

  await processedRef.set({
    notificationType: decoded.notificationType,
    originalTransactionId: decoded.originalTransactionId,
    processedAt: new Date(),
  });
}

function updatesFor(decoded) {
  switch (decoded.notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
      if (!decoded.expiresDate) {
        // Shouldn't happen for these types — logged, no write, rather than
        // sending an undefined value to Firestore (which throws).
        console.error(`appStoreServerNotifications: ${decoded.notificationType} notification missing expiresDate.`);
        return null;
      }
      return {
        annualProMembershipExpiresAt: new Date(decoded.expiresDate),
        annualProMembershipImagesRemovedAt: null,
        annualProMembershipBillingRetryUntil: null,
        // A fresh renewal means any prior lapse-warning cycle is over —
        // clear both markers so a future lapse warns again instead of
        // staying silently suppressed by a stale marker from last time.
        annualProMembershipWarnedAtDay75: null,
        annualProMembershipWarnedAtDay85: null,
      };
    case 'DID_CHANGE_RENEWAL_STATUS':
      // No expiration change — just the informational "will this actually
      // renew" signal, per gap #5: a member who turns off auto-renew
      // shouldn't be caught off guard weeks later with no earlier signal.
      return { annualProMembershipWillRenew: decoded.autoRenewStatus === 1 };
    case 'DID_FAIL_TO_RENEW':
      if (decoded.isInBillingRetryPeriod && decoded.gracePeriodExpiresDate) {
        // Apple is still retrying — the member must not be treated as
        // lapsed yet even past the normal 90-day sweep mark (gap #1).
        return { annualProMembershipBillingRetryUntil: new Date(decoded.gracePeriodExpiresDate) };
      }
      return null;
    case 'EXPIRED':
    case 'REVOKED':
      // No write needed — annualProMembershipExpiresAt is already in the
      // past (or REVOKED's underlying transaction data reflects that);
      // the sweep, not this webhook, acts on a lapsed member.
      return null;
    default:
      // PRICE_INCREASE, REFUND, TEST, and anything else this function
      // doesn't need to act on — explicitly a no-op, not an error.
      return null;
  }
}

module.exports = { handleAppStoreServerNotification, ANNUAL_PRO_MEMBERSHIP_PRODUCT_ID };
