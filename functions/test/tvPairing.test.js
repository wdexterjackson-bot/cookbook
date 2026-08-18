// Runs against the real Firestore emulator (tvPairingRequests + rate-limit
// bookkeeping) with a stubbed Auth client (no real Auth-emulator user
// fixture needed) — same approach as findUserByEmail.test.js.

const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { requestPairingCode, checkPairingStatus, confirmPairingCode } = require('../tvPairing');

let db;

before(() => {
  process.env.GCLOUD_PROJECT = 'demo-cookbook';
  if (getApps().length === 0) {
    initializeApp({ projectId: 'demo-cookbook' });
  }
  db = getFirestore();
});

beforeEach(async () => {
  for (const collectionName of [
    'tvPairingRequests',
    'tvPairingRequestAttempts',
    'tvPairingPollAttempts',
    'tvPairingConfirmAttempts',
  ]) {
    const snapshot = await db.collection(collectionName).get();
    await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
  }
});

function fakeAuthClient() {
  const minted = [];
  return {
    minted,
    async createCustomToken(uid) {
      const token = `fake-token-for-${uid}-${minted.length}`;
      minted.push({ uid, token });
      return token;
    },
  };
}

test('the full happy path: request, confirm, then a single token delivery', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });
  assert.equal(code.length, 6);

  const pending = await checkPairingStatus({ db, authClient: fakeAuthClient(), code, deviceSessionID: 'tv-session-1' });
  assert.deepEqual(pending, { status: 'pending' });

  const confirmResult = await confirmPairingCode({ db, code, callerUserID: 'alice' });
  assert.deepEqual(confirmResult, { ok: true });

  const auth = fakeAuthClient();
  const confirmed = await checkPairingStatus({ db, authClient: auth, code, deviceSessionID: 'tv-session-1' });
  assert.equal(confirmed.status, 'confirmed');
  assert.ok(confirmed.token);
  assert.deepEqual(auth.minted, [{ uid: 'alice', token: confirmed.token }]);

  // The token is handed out exactly once — a second poll (even from the
  // same legitimate TV session, e.g. a retried request after a dropped
  // response) must not mint or return another one.
  const secondPoll = await checkPairingStatus({ db, authClient: auth, code, deviceSessionID: 'tv-session-1' });
  assert.deepEqual(secondPoll, { status: 'confirmed' });
  assert.equal(auth.minted.length, 1);
});

test('polling with the right code but the wrong deviceSessionID is rejected, even before confirmation — closes the "anyone who saw the code" race', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });

  const result = await checkPairingStatus({ db, authClient: fakeAuthClient(), code, deviceSessionID: 'attacker-session' });

  assert.deepEqual(result, { status: 'expired' });
});

test('polling with the wrong deviceSessionID never delivers the token, even after the real phone confirms', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });
  await confirmPairingCode({ db, code, callerUserID: 'alice' });

  const attackerAuth = fakeAuthClient();
  const attackerResult = await checkPairingStatus({ db, authClient: attackerAuth, code, deviceSessionID: 'attacker-session' });
  assert.deepEqual(attackerResult, { status: 'expired' });
  assert.equal(attackerAuth.minted.length, 0);

  // The real TV, polling with its own correct session ID, still gets it —
  // the attacker's failed attempt must not have consumed tokenDelivered.
  const realAuth = fakeAuthClient();
  const realResult = await checkPairingStatus({ db, authClient: realAuth, code, deviceSessionID: 'tv-session-1' });
  assert.equal(realResult.status, 'confirmed');
  assert.ok(realResult.token);
});

test('checking an unknown code reports expired, not an error', async () => {
  const result = await checkPairingStatus({ db, authClient: fakeAuthClient(), code: 'ZZZZZZ', deviceSessionID: 'tv-session-1' });
  assert.deepEqual(result, { status: 'expired' });
});

test('checking a genuinely expired code reports expired', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });
  await db.collection('tvPairingRequests').doc(code).update({ expiresAt: Date.now() - 1000 });

  const result = await checkPairingStatus({ db, authClient: fakeAuthClient(), code, deviceSessionID: 'tv-session-1' });
  assert.deepEqual(result, { status: 'expired' });
});

test('confirming an expired code fails and leaves it untouched', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });
  await db.collection('tvPairingRequests').doc(code).update({ expiresAt: Date.now() - 1000 });

  await assert.rejects(() => confirmPairingCode({ db, code, callerUserID: 'alice' }));

  const doc = await db.collection('tvPairingRequests').doc(code).get();
  assert.equal(doc.data().status, 'pending');
});

test('confirming an unknown code fails', async () => {
  await assert.rejects(() => confirmPairingCode({ db, code: 'ZZZZZZ', callerUserID: 'alice' }));
});

test('confirming an already-confirmed code fails — single use, not re-assignable', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });
  await confirmPairingCode({ db, code, callerUserID: 'alice' });

  await assert.rejects(() => confirmPairingCode({ db, code, callerUserID: 'mallory' }));

  const doc = await db.collection('tvPairingRequests').doc(code).get();
  assert.equal(doc.data().confirmedUserID, 'alice');
});

test('code lookups are case-insensitive (a phone retyping the code shouldn\'t need exact case)', async () => {
  const { code } = await requestPairingCode({ db, deviceSessionID: 'tv-session-1' });

  await assert.doesNotReject(() => confirmPairingCode({ db, code: code.toLowerCase(), callerUserID: 'alice' }));
});

test('rejects a missing deviceSessionID on request', async () => {
  await assert.rejects(() => requestPairingCode({ db, deviceSessionID: '  ' }));
});

test('rate-limits repeated code requests by the same device session', async () => {
  for (let i = 0; i < 10; i++) {
    await requestPairingCode({ db, deviceSessionID: 'rl-session' });
  }
  await assert.rejects(() => requestPairingCode({ db, deviceSessionID: 'rl-session' }));
});

test('request rate limit is tracked per device session, not globally', async () => {
  for (let i = 0; i < 10; i++) {
    await requestPairingCode({ db, deviceSessionID: 'rl-session-a' });
  }
  await assert.doesNotReject(() => requestPairingCode({ db, deviceSessionID: 'rl-session-b' }));
});

test('rate-limits repeated confirm attempts by the same caller — prevents mass code-guessing across many TVs', async () => {
  for (let i = 0; i < 10; i++) {
    await assert.rejects(() => confirmPairingCode({ db, code: 'NOPE00', callerUserID: 'mallory' }));
  }
  await assert.rejects(() => confirmPairingCode({ db, code: 'NOPE00', callerUserID: 'mallory' }), /Too many attempts/);
});
