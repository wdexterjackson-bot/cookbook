// Core business logic for a purchaseClaims/{claimID} doc: verify the
// signed transaction really came from Apple, cross-check it matches what
// the client claimed, then apply the entitlement exactly once per Apple
// transaction ID. `verifyTransaction` is injected (real Apple verification
// in production via purchaseClaimVerifier.js, a stub in tests) so this
// logic is testable without a real Apple-signed JWS.

// Must match StoreProductID in cookbook/Services/PurchaseServicing.swift.
const FAMILY_USER_LIFETIME_PRODUCT_ID = 'VibeApp.cookbook.familyUser.lifetime';
const GROUP_CREATION_CREDIT_PRODUCT_ID = 'VibeApp.cookbook.groupCreationCredit';

async function applyPurchaseClaim({ db, claimID, claimData, verifyTransaction }) {
  const decoded = await verifyTransaction(claimData.jwsRepresentation);

  if (decoded.transactionId !== claimData.transactionID || decoded.productId !== claimData.productID) {
    throw new Error(`Decoded transaction (${decoded.transactionId}/${decoded.productId}) does not match claim ${claimID} (${claimData.transactionID}/${claimData.productID})`);
  }

  const processedRef = db.collection('processedPurchaseTransactions').doc(decoded.transactionId);
  const entitlementRef = db.collection('entitlements').doc(claimData.userID);

  await db.runTransaction(async (transaction) => {
    const processedSnap = await transaction.get(processedRef);
    if (processedSnap.exists) {
      // Already applied for this Apple transaction ID — a client re-submit
      // (e.g. after relaunch re-processing Transaction.currentEntitlements)
      // must never double-credit.
      return;
    }

    const entitlementSnap = await transaction.get(entitlementRef);
    const current = entitlementSnap.exists ? entitlementSnap.data() : {
      userID: claimData.userID,
      creationCredits: 0,
      hasFamilyUser: false,
      familyUserPromoCreditAvailable: false,
      grantedPromoCredits: false,
      createdAt: new Date(),
    };

    let updates;
    if (decoded.productId === FAMILY_USER_LIFETIME_PRODUCT_ID) {
      updates = { hasFamilyUser: true };
    } else if (decoded.productId === GROUP_CREATION_CREDIT_PRODUCT_ID) {
      updates = { creationCredits: (current.creationCredits || 0) + 1 };
    } else {
      throw new Error(`Unknown productID on claim ${claimID}: ${decoded.productId}`);
    }

    transaction.set(entitlementRef, { ...current, ...updates }, { merge: true });
    transaction.set(processedRef, {
      transactionID: decoded.transactionId,
      productID: decoded.productId,
      userID: claimData.userID,
      claimID,
      processedAt: new Date(),
    });
  });
}

module.exports = {
  applyPurchaseClaim,
  FAMILY_USER_LIFETIME_PRODUCT_ID,
  GROUP_CREATION_CREDIT_PRODUCT_ID,
};
