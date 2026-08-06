// storage.rules tests — run against the real Storage + Firestore
// emulators together (not a mock), via `firebase emulators:exec` from the
// repo root. storage.rules relies on cross-service firestore.get()/
// firestore.exists() checks against memberships/{groupID}_{userID}, so
// this needs the Firestore emulator running alongside Storage — see
// ../firestore.rules and ../storage.rules for the design notes.
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
import { ref, uploadBytes, getBytes } from 'firebase/storage';

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

const jpegBytes = new Uint8Array([1, 2, 3]);

describe('publication photo uploads', () => {
  it('allows a member to upload their own recipe photo', async () => {
    await seedMembership('group-upload-own', 'alice');
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-own/alice_recipe1.jpg');
    await assertSucceeds(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it("rejects uploading under someone else's uid prefix", async () => {
    await seedMembership('group-upload-other', 'alice');
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-other/bob_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'image/jpeg' }));
  });

  it('rejects a non-image content type', async () => {
    await seedMembership('group-upload-badtype', 'alice');
    const alice = testEnv.authenticatedContext('alice').storage();
    const fileRef = ref(alice, 'publications/group-upload-badtype/alice_recipe1.jpg');
    await assertFails(uploadBytes(fileRef, jpegBytes, { contentType: 'text/plain' }));
  });

  it('allows another active member of the same group to read the photo', async () => {
    await seedMembership('group-read-member', 'alice');
    await seedMembership('group-read-member', 'bob');
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-member/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const bob = testEnv.authenticatedContext('bob').storage();
    await assertSucceeds(getBytes(ref(bob, 'publications/group-read-member/alice_recipe1.jpg')));
  });

  it('rejects a non-member from reading the photo', async () => {
    await seedMembership('group-read-nonmember', 'alice');
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-nonmember/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const mallory = testEnv.authenticatedContext('mallory').storage();
    await assertFails(getBytes(ref(mallory, 'publications/group-read-nonmember/alice_recipe1.jpg')));
  });

  it('rejects reading from an unauthenticated context', async () => {
    await seedMembership('group-read-anon', 'alice');
    const alice = testEnv.authenticatedContext('alice').storage();
    await uploadBytes(ref(alice, 'publications/group-read-anon/alice_recipe1.jpg'), jpegBytes, { contentType: 'image/jpeg' });

    const anon = testEnv.unauthenticatedContext().storage();
    await assertFails(getBytes(ref(anon, 'publications/group-read-anon/alice_recipe1.jpg')));
  });
});
