// Apple TV phone-pairing sign-in (the Netflix/YouTube-TV device-code
// pattern): a signed-out TV requests a short code, shows it (as text and
// as a QR), a signed-in phone confirms it belongs to their account, and
// the TV exchanges the confirmed code for a Firebase custom token —
// mirrors OAuth's device authorization grant (RFC 8628).
//
// tvPairingRequests has no firestore.rules entry at all — falls through
// to the catch-all `allow read, write: if false`, same as the
// deleteGroupPermanentlyAttempts/findUserByEmailAttempts rate-limit
// bookkeeping collections. Every interaction goes through one of these
// three callables (Admin SDK, bypasses rules), never a direct client
// read/write — a direct Firestore read on an unauthenticated collection
// would be an unrate-limitable brute-force oracle over the code space.

const { checkAndRecordRateLimit, RateLimitExceededError } = require('./rateLimiter');

const REQUEST_RATE_LIMIT_MAX_ATTEMPTS = 10;
const REQUEST_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour, per deviceSessionID

const POLL_RATE_LIMIT_MAX_ATTEMPTS = 150;
const POLL_RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000; // 10 minutes, per deviceSessionID — a legit TV polling every 3s for the 5-minute code lifetime is ~100 calls

const CONFIRM_RATE_LIMIT_MAX_ATTEMPTS = 10;
const CONFIRM_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour, per confirming uid — a signed-in account can't be used to mass-guess codes

const CODE_TTL_MS = 5 * 60 * 1000; // 5 minutes

// Crockford-ish alphabet with ambiguous characters dropped (0/O, 1/I/L) —
// 32 symbols, 6 characters, ~1 billion combinations. Uppercase only, since
// this is read off a TV screen and typed on a phone.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;

function generateCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

async function requestPairingCode({ db, deviceSessionID }) {
  const trimmedSessionID = (deviceSessionID || '').trim();
  if (!trimmedSessionID) {
    throw new Error('deviceSessionID is required');
  }

  const allowed = await checkAndRecordRateLimit(db, {
    collection: 'tvPairingRequestAttempts',
    key: trimmedSessionID,
    maxAttempts: REQUEST_RATE_LIMIT_MAX_ATTEMPTS,
    windowMs: REQUEST_RATE_LIMIT_WINDOW_MS,
  });
  if (!allowed) {
    throw new RateLimitExceededError('Too many pairing attempts — try again later.');
  }

  const now = Date.now();
  const expiresAt = now + CODE_TTL_MS;

  // Collisions are vanishingly unlikely at this scale (~1 in a billion per
  // attempt), but checked and retried anyway rather than trusted away.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = generateCode();
    const ref = db.collection('tvPairingRequests').doc(code);
    const created = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      if (snap.exists) return false;
      transaction.set(ref, {
        status: 'pending',
        deviceSessionID: trimmedSessionID,
        createdAt: now,
        expiresAt,
      });
      return true;
    });
    if (created) {
      return { code, expiresAt };
    }
  }
  throw new Error('Could not generate a pairing code right now — try again.');
}

async function checkPairingStatus({ db, authClient, code, deviceSessionID }) {
  const trimmedCode = (code || '').trim().toUpperCase();
  const trimmedSessionID = (deviceSessionID || '').trim();
  if (!trimmedCode || !trimmedSessionID) {
    throw new Error('code and deviceSessionID are required');
  }

  const allowed = await checkAndRecordRateLimit(db, {
    collection: 'tvPairingPollAttempts',
    key: trimmedSessionID,
    maxAttempts: POLL_RATE_LIMIT_MAX_ATTEMPTS,
    windowMs: POLL_RATE_LIMIT_WINDOW_MS,
  });
  if (!allowed) {
    throw new RateLimitExceededError('Too many status checks — try again later.');
  }

  const ref = db.collection('tvPairingRequests').doc(trimmedCode);

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) {
      return { status: 'expired' };
    }
    const data = snap.data();
    if (Date.now() > data.expiresAt) {
      return { status: 'expired' };
    }
    // Binds redemption to the exact TV that created this code — without
    // this, the 6-character *display* code (shown on screen, encoded in
    // its QR, sayable out loud) would be the only thing needed to redeem
    // the sign-in token once a phone confirms it: anyone who merely saw
    // the code (a photo, a screenshot, someone glancing at the TV) could
    // call this endpoint directly and race the real TV for it.
    // deviceSessionID is never displayed anywhere, so only the TV that
    // actually called requestPairingCode can supply the right one. Same
    // "expired" response as an unknown code — not a distinct error —
    // so a wrong guess doesn't confirm the real deviceSessionID is wrong.
    if (data.deviceSessionID !== trimmedSessionID) {
      return { status: 'expired' };
    }
    if (data.status === 'pending') {
      return { status: 'pending' };
    }
    // data.status === 'confirmed' from here on.
    if (data.tokenDelivered) {
      // Already handed out once — never again, even to the legitimate TV
      // re-polling after a dropped response.
      return { status: 'confirmed' };
    }
    const token = await authClient.createCustomToken(data.confirmedUserID);
    transaction.update(ref, { tokenDelivered: true });
    return { status: 'confirmed', token };
  });
}

async function confirmPairingCode({ db, code, callerUserID }) {
  const trimmedCode = (code || '').trim().toUpperCase();
  if (!trimmedCode) {
    throw new Error('code is required');
  }

  const allowed = await checkAndRecordRateLimit(db, {
    collection: 'tvPairingConfirmAttempts',
    key: callerUserID,
    maxAttempts: CONFIRM_RATE_LIMIT_MAX_ATTEMPTS,
    windowMs: CONFIRM_RATE_LIMIT_WINDOW_MS,
  });
  if (!allowed) {
    throw new RateLimitExceededError('Too many attempts — try again later.');
  }

  const ref = db.collection('tvPairingRequests').doc(trimmedCode);

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) {
      throw new Error('This code is invalid or has expired.');
    }
    const data = snap.data();
    if (Date.now() > data.expiresAt) {
      throw new Error('This code is invalid or has expired.');
    }
    if (data.status !== 'pending') {
      throw new Error('This code has already been used.');
    }
    transaction.update(ref, { status: 'confirmed', confirmedUserID: callerUserID });
  });

  return { ok: true };
}

module.exports = { requestPairingCode, checkPairingStatus, confirmPairingCode };
