const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { applyPurchaseClaim } = require('./applyPurchaseClaim');
const { verifyTransaction } = require('./purchaseClaimVerifier');

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
