// Real Apple verification for App Store Server Notifications V2, used by
// index.js in production. Not exercised by the emulator tests
// (appStoreServerNotifications.test.js injects a stub instead) — same
// reasoning as purchaseClaimVerifier.js: needs Apple's actual root
// certificates and a genuinely Apple-signed payload, neither available
// offline.
//
// A notification's outer payload only carries nested signed sub-payloads
// (data.signedTransactionInfo, data.signedRenewalInfo) — this decodes and
// verifies all three layers (notification, transaction, renewal info) and
// flattens the fields appStoreServerNotifications.js actually needs into
// one plain object, so the business-logic side never has to know about
// Apple's nested-JWS shape.

const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');
const fs = require('fs');
const path = require('path');

function loadRootCertificates() {
  const certsDir = path.join(__dirname, 'certs');
  if (!fs.existsSync(certsDir)) return [];
  return fs.readdirSync(certsDir)
    .filter((name) => name.endsWith('.cer'))
    .map((name) => fs.readFileSync(path.join(certsDir, name)));
}

function makeVerifier() {
  const rootCertificates = loadRootCertificates();
  if (rootCertificates.length === 0) {
    throw new Error('No Apple root certificates configured — see functions/certs/README.md');
  }
  const bundleID = process.env.APPLE_BUNDLE_ID || 'VibeApp.cookbook';
  const environment = process.env.APPLE_ENVIRONMENT === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
  return new SignedDataVerifier(rootCertificates, true, environment, bundleID);
}

async function decodeAndVerifyNotification(signedPayload) {
  const verifier = makeVerifier();
  const notification = await verifier.verifyAndDecodeNotification(signedPayload);

  const transactionInfo = notification.data && notification.data.signedTransactionInfo
    ? await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo)
    : undefined;
  const renewalInfo = notification.data && notification.data.signedRenewalInfo
    ? await verifier.verifyAndDecodeRenewalInfo(notification.data.signedRenewalInfo)
    : undefined;

  return {
    notificationType: notification.notificationType,
    notificationUUID: notification.notificationUUID,
    environment: notification.data && notification.data.environment,
    originalTransactionId: (transactionInfo && transactionInfo.originalTransactionId)
      || (renewalInfo && renewalInfo.originalTransactionId),
    productId: (transactionInfo && transactionInfo.productId) || (renewalInfo && renewalInfo.productId),
    expiresDate: transactionInfo && transactionInfo.expiresDate,
    isInBillingRetryPeriod: renewalInfo && renewalInfo.isInBillingRetryPeriod,
    gracePeriodExpiresDate: renewalInfo && renewalInfo.gracePeriodExpiresDate,
    autoRenewStatus: renewalInfo && renewalInfo.autoRenewStatus,
  };
}

module.exports = { decodeAndVerifyNotification };
