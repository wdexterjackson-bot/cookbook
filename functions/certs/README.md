# Apple root certificates (required before deploying)

`purchaseClaimVerifier.js` needs Apple's root certificates to validate the
signature chain on a StoreKit transaction JWS. Download the current G3 root
(and any intermediate Apple currently documents for App Store Server Library
use) from Apple's PKI page and place the `.cer` files in this directory —
they are not vendored in this repo.

Until this directory has at least one `.cer` file, `verifyTransaction` throws
immediately rather than silently accepting unverified purchases.
