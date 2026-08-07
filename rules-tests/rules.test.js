// firestore.rules tests — run against the real Firestore emulator (not a
// mock), via `firebase emulators:exec` from the repo root. See
// ../firestore.rules for the design notes these tests are proving out.

import { before, after, beforeEach, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, writeBatch, Timestamp } from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-cookbook',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

const GROUP1_UNIQUENESS_KEY = 'barrentine family reunion|barrentines|memphis';

function groupData(overrides = {}) {
  return {
    id: 'group1',
    slug: 'group1',
    name: 'Barrentines',
    cookbookName: 'Barrentine Family Reunion',
    uniquenessKey: GROUP1_UNIQUENESS_KEY,
    description: '',
    type: 'Family',
    locationText: 'Memphis',
    structuredRegion: null,
    coverImageURL: null,
    visibility: 'public',
    createdByUserID: 'alice',
    createdAt: Timestamp.now(),
    status: 'active',
    allowsMemberInvites: false,
    allowsMemberPublishing: true,
    autoApproveJoinRequests: false,
    ...overrides,
  };
}

function entitlementData(overrides = {}) {
  return {
    userID: 'alice',
    creationCredits: 3,
    hasFamilyUser: false,
    familyUserPromoCreditAvailable: true,
    grantedPromoCredits: true,
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

describe('entitlements', () => {
  it('allows the exact promo grant shape for your own uid', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData()));
  });

  it('rejects granting yourself more than the promo amount', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 100 })));
  });

  it('rejects granting credits to someone else', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/bob'), entitlementData({ userID: 'bob' })));
  });

  it('allows spending exactly one credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 2 })));
  });

  it('rejects granting yourself extra credits via update', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 10 })));
  });

  it('rejects granting yourself hasFamilyUser via update', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 2, hasFamilyUser: true })));
  });

  it('allows redeeming the free Family User promo credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      hasFamilyUser: true,
      familyUserPromoCreditAvailable: false,
    })));
  });

  it('rejects redeeming the promo credit a second time', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({
      hasFamilyUser: true,
      familyUserPromoCreditAvailable: false,
    })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      hasFamilyUser: true,
      familyUserPromoCreditAvailable: false,
    })));
  });

  it('rejects redeeming the promo credit while also touching creationCredits', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      hasFamilyUser: true,
      familyUserPromoCreditAvailable: false,
      creationCredits: 2,
    })));
  });
});

describe('group creation', () => {
  it('succeeds when paired with a matching entitlement decrement and uniqueness-key claim in one batch', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group1', createdAt: Timestamp.now() });
    batch.set(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    });
    await assertSucceeds(batch.commit());
  });

  it('rejects creating a group without a matching uniqueness-key claim in the same batch', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    // No groupUniquenessKeys write this time — even with a correct credit
    // decrement, the create rule's second getAfter() check should reject it.
    await assertFails(batch.commit());
  });

  it('rejects claiming a Cookbook Name + Family Name + Location combination that is already taken', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 5 }));
      await setDoc(doc(db, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group0', createdAt: Timestamp.now() });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 4 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group1', createdAt: Timestamp.now() });
    // The reservation doc already exists (from "group0"), so this write is
    // an update, not a create — denied, and the whole batch fails with it.
    await assertFails(batch.commit());
  });

  it('rejects creating a group without spending a credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'groups/group1'), groupData()));
  });

  it('rejects creating a group with no credits available', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 0 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: -1 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    await assertFails(batch.commit());
  });

  it("rejects creating a group on someone else's behalf", async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ creationCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ creationCredits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData({ createdByUserID: 'bob' }));
    await assertFails(batch.commit());
  });
});

describe('purchase claims', () => {
  it('allows submitting your own claim', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'purchaseClaims/txn1'), {
      userID: 'alice', productID: 'VibeApp.cookbook.familyUser.lifetime',
      transactionID: 'txn1', jwsRepresentation: 'stub-jws', submittedAt: Timestamp.now(),
    }));
  });

  it("rejects submitting a claim on someone else's behalf", async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'purchaseClaims/txn1'), {
      userID: 'bob', productID: 'VibeApp.cookbook.familyUser.lifetime',
      transactionID: 'txn1', jwsRepresentation: 'stub-jws', submittedAt: Timestamp.now(),
    }));
  });

  it('rejects a client marking its own claim processed', async () => {
    await seed((db) => setDoc(doc(db, 'purchaseClaims/txn1'), {
      userID: 'alice', productID: 'VibeApp.cookbook.familyUser.lifetime',
      transactionID: 'txn1', jwsRepresentation: 'stub-jws', submittedAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'purchaseClaims/txn1'), {
      userID: 'alice', productID: 'VibeApp.cookbook.familyUser.lifetime',
      transactionID: 'txn1', jwsRepresentation: 'stub-jws', submittedAt: Timestamp.now(), processed: true,
    }));
  });
});

describe('memberships', () => {
  it('rejects a signed-in user adding themself as a member directly', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ visibility: 'private' })));
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(setDoc(doc(mallory, 'memberships/group1_mallory'), {
      id: 'group1_mallory', groupID: 'group1', userID: 'mallory', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it("a non-member cannot read a private group's membership list", async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'memberships/group1_alice')));
  });

  it('a user can self-create a member membership when the group auto-approves', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-create a membership via the auto path when the group does not auto-approve', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: false })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-grant admin via the auto-approve path even when the group allows it', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });
});

function publicationData(overrides = {}) {
  return {
    id: 'pub1',
    groupID: 'group1',
    ownerUserID: 'alice',
    sourceRecipeID: 'recipe1',
    state: 'published',
    publishedAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    content: {
      title: 'Cornbread', summary: '', yield: '', totalTimeMinutes: null,
      ingredientSections: [], stepSections: [], notes: '', tags: [],
    },
    ...overrides,
  };
}

describe('publications', () => {
  it("a non-member cannot read a public group's recipes", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'publications/pub1')));
  });

  it("a member can read a public group's recipes", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'publications/pub1')));
  });
});

describe('join requests', () => {
  it('an active member cannot request to join the same group again', async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'bob', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a non-admin cannot approve a join request', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'joinRequests/req1'), {
        id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'approved', decidedByUserID: 'bob', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
    }));
  });

  it('an admin can approve a join request', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'joinRequests/req1'), {
        id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'approved', decidedByUserID: 'alice', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
    }));
  });
});
