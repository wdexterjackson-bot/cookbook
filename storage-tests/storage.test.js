// storage.rules tests — run against the real Storage + Firestore
// emulators together (not a mock), via `firebase emulators:exec` from the
// repo root. storage.rules relies on cross-service firestore.get()/
// firestore.exists() checks against memberships/{groupID}_{userID} and
// entitlements/{userID}, so this needs the Firestore emulator running
// alongside Storage — see ../firestore.rules and ../storage.rules for the
// design notes.
//
// Storing a photo (write, either path) requires an active Annual Pro
// Membership — reading one back never does, and never checks who
// uploaded it originally. Every write-success test below seeds the
// uploader an active annual entitlement first; every bare setup upload
// used only to get a photo in place for a read/delete test does too,
// since it would otherwise fail before the test even gets to what it's
// actually checking.
//
// Each test uses its own group/file names rather than clearing storage
// between tests (no equivalent of clearFirestore() for Storage in
// @firebase/rules-unit-testing as of this writing).

import { before, after, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-cookbook',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

async function seedMembership(groupID, userID) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `memberships/${groupID}_${userID}`), {
      id: `${groupID}_${userID}`, groupID, userID, role: 'member',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    });
  });
}

// annualProMembershipExpiresAt is the only field storage.rules reads;
// isProUser is included so tests can prove Annual-only, not any-Pro.
async function seedEntitlement(userID, { annualProMembershipExpiresAt = null, isProUser = false } = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `entitlements/${userID}`), {
      userID, tier1Credits: 0, tier2Credits: 0, isProUser,
      receivedTier1PromoCredit: false, receivedTier2PromoCredits: false,
      createdAt: Timestamp.now(),
      ...(annualProMembershipExpiresAt ? { annualProMembershipExpiresAt } : {}),
    });
  });
}

function daysFromNow(days) {
  return Timestamp.fromMillis(Date.now() + days * 24 * 60 * 60 * 1000);
}

const jpegBytes = new Uint8Array([1, 2, 3]);

describe('publication photo uploads', () => {
  it('allows an active Annual Pro Member to upload their own recipe photo', async () => {
    await seedMembership('group-upload-own', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-own/cb-1/alice_recipe1.jpg');
    await assertSucceeds(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload with no entitlement doc at all', async () => {
    // A dedicated userID never seeded an entitlement anywhere else in this
    // file — this file doesn't reset Firestore state between tests, so
    // reusing 'alice' here would pick up whatever an earlier test left
    // behind instead of proving the "no doc" case.
    await seedMembership('group-upload-noent', 'nopro');
    const nopro = testEnv.authenticatedContext('nopro').storage();
    const fileRef = ref(nopro, 'publications/group-upload-noent/cb-1/nopro_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload once Annual Pro Membership has expired', async () => {
    await seedMembership('group-upload-expired', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(-1) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-expired/cb-1/alice_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload from a lifetime Pro User with no active Annual Pro Membership', async () => {
    await seedMembership('group-upload-lifetimepro', 'alice');
    await seedEntitlement('alice', { isProUser: true });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-lifetimepro/cb-1/alice_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it("rejects uploading under someone else's uid prefix", async () => {
    await seedMembership('group-upload-other', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-other/cb-1/bob_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects a non-image content type', async () => {
    await seedMembership('group-upload-badtype', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-badtype/cb-1/alice_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'text/plain' }));
  });

  it('allows another active member of the same group to read the photo, with no entitlement of their own', async () => {
    await seedMembership('group-read-member', 'alice');
    await seedMembership('group-read-member', 'bob');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-member/cb-1/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    // bob has no entitlements doc at all — reading never checks it.
    const bob = testEnv.authenticatedContext('bob').storage();
    await assertSucceeds(getBytes(ref(bob, 'publications/group-read-member/cb-1/alice_recipe1.jpg')));
  });

  it('rejects a non-member from reading the photo', async () => {
    await seedMembership('group-read-nonmember', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-nonmember/cb-1/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const mallory = testEnv.authenticatedContext('mallory').storage();
    await assertFails(getBytes(ref(mallory, 'publications/group-read-nonmember/cb-1/alice_recipe1.jpg')));
  });

  it('rejects reading from an unauthenticated context', async () => {
    await seedMembership('group-read-anon', 'alice');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-anon/cb-1/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const anon = testEnv.unauthenticatedContext().storage();
    await assertFails(getBytes(ref(anon, 'publications/group-read-anon/cb-1/alice_recipe1.jpg')));
  });

  it('allows reading a photo under a second cookbook in the same group', async () => {
    await seedMembership('group-multi-cookbook', 'alice');
    await seedMembership('group-multi-cookbook', 'bob');
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-multi-cookbook/cb-2/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const bob = testEnv.authenticatedContext('bob').storage();
    await assertSucceeds(getBytes(ref(bob, 'publications/group-multi-cookbook/cb-2/alice_recipe1.jpg')));
  });
});

describe('personal cookbook photo uploads', () => {
  it('allows an active Annual Pro Member to upload under their own uid prefix', async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/alice/recipe1.jpg');
    await assertSucceeds(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload with no entitlement doc at all', async () => {
    // Same dedicated never-seeded userID as the publications block above,
    // for the same reason — no Firestore reset between tests in this file.
    const nopro = testEnv.authenticatedContext('nopro').storage();
    const fileRef = ref(nopro, 'personalCookbooks/nopro/recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload once Annual Pro Membership has expired', async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(-1) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/alice/recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects an upload from a lifetime Pro User with no active Annual Pro Membership', async () => {
    await seedEntitlement('alice', { isProUser: true });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/alice/recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it("rejects uploading under someone else's uid prefix", async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/bob/recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects a non-image content type', async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/alice/recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'text/plain' }));
  });

  it('allows the owner to read their own photo', async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'personalCookbooks/alice/recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });
    await assertSucceeds(getBytes(ref(alice, 'personalCookbooks/alice/recipe1.jpg')));
  });

  it("rejects another user reading someone else's personal cookbook photo", async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'personalCookbooks/alice/recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const bob = testEnv.authenticatedContext('bob').storage();
    await assertFails(getBytes(ref(bob, 'personalCookbooks/alice/recipe1.jpg')));
  });

  it('allows the owner to delete their own photo', async () => {
    await seedEntitlement('alice', { annualProMembershipExpiresAt: daysFromNow(30) });
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'personalCookbooks/alice/recipe1.jpg');
    await uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' });
    await assertSucceeds(deleteObject(fileRef));
  });
});
