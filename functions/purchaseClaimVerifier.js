// Real Apple verification, used by index.js in production. Not exercised
// by the emulator tests (applyPurchaseClaim.test.js injects a stub
// instead) since it needs Apple's actual root certificates and a
// genuinely Apple-signed JWS, neither of which is available offline.
//
// SETUP REQUIRED BEFORE DEPLOYING (deliberately deferred — see
// functions/certs/README.md): download Apple's root certificates and
// place them in functions/certs/*.cer.

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

async function verifyTransaction(jwsRepresentation) {
  const rootCertificates = loadRootCertificates();
  if (rootCertificates.length === 0) {
    throw new Error('No Apple root certificates configured — see functions/certs/README.md');
  }

  const bundleID = process.env.APPLE_BUNDLE_ID || 'VibeApp.cookbook';
  const environment = process.env.APPLE_ENVIRONMENT === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;

  const verifier = new SignedDataVerifier(rootCertificates, true, environment, bundleID);
  return await verifier.verifyAndDecodeTransaction(jwsRepresentation);
}

module.exports = { verifyTransaction };
