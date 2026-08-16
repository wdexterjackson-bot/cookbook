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
    isMFB: false,
    ...overrides,
  };
}

// Shape granted by the one-time free-launch-credit create — both tiers
// received together (see EntitlementGranting.swift / entitlements/create).
function entitlementData(overrides = {}) {
  return {
    userID: 'alice',
    tier1Credits: 1,
    tier2Credits: 2,
    isProUser: false,
    receivedTier1PromoCredit: true,
    receivedTier2PromoCredits: true,
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

describe('entitlements', () => {
  it('allows the exact free-launch-credit grant shape for your own uid', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData()));
  });

  it('rejects granting yourself more than the promo amount', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 100 })));
  });

  it('rejects granting credits to someone else', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/bob'), entitlementData({ userID: 'bob' })));
  });

  it('allows spending exactly one tier-2 credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
  });

  it('rejects granting yourself extra tier-2 credits via update', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 10 })));
  });

  it('rejects granting yourself isProUser via a tier-2 spend update', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 1, isProUser: true })));
  });

  it('allows spending a tier-1 credit to become Pro User', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 0,
      isProUser: true,
    })));
  });

  it('rejects becoming Pro User without spending a tier-1 credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      isProUser: true,
    })));
  });

  it('rejects spending a tier-1 credit while also touching tier2Credits', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 0,
      isProUser: true,
      tier2Credits: 1,
    })));
  });

  it('rejects spending a tier-1 credit you no longer have', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier1Credits: 0 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: -1,
      isProUser: true,
    })));
  });

  it('allows backfilling a missing tier-1 credit on a doc that already has tier-2', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), {
      userID: 'alice', tier1Credits: 0, tier2Credits: 2, isProUser: false,
      receivedTier1PromoCredit: false, receivedTier2PromoCredits: true, createdAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 1,
      tier2Credits: 2,
      receivedTier1PromoCredit: true,
      receivedTier2PromoCredits: true,
    })));
  });

  it('allows backfilling a genuinely legacy doc missing the new fields entirely', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), {
      userID: 'alice', creationCredits: 3, hasFamilyUser: false,
      familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), {
      userID: 'alice', creationCredits: 3, hasFamilyUser: false,
      familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: Timestamp.now(),
      tier1Credits: 1, tier2Credits: 2,
      receivedTier1PromoCredit: true, receivedTier2PromoCredits: true,
    }, { merge: true }));
  });

  it('rejects a backfill that grants the wrong amount', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), {
      userID: 'alice', tier1Credits: 0, tier2Credits: 0, isProUser: false,
      receivedTier1PromoCredit: false, receivedTier2PromoCredits: false, createdAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 5,
      tier2Credits: 2,
    })));
  });

  it('rejects a no-op update pretending to be a backfill', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData()));
  });

  // Credit expiration (tier1: 1/1/2027, tier2: 1/1/2029 — must match
  // tier1ExpirationTimestamp()/tier2ExpirationTimestamp() in firestore.rules
  // and LaunchCreditPromo in EntitlementGranting.swift exactly).
  const PAST = Timestamp.fromDate(new Date('2020-01-01T00:00:00Z'));
  // Relative to "now" rather than a fixed date — a hardcoded near-term
  // date silently becomes a PAST date (and starts failing this test) once
  // real time catches up to it, which is exactly what happened to the
  // fixed '2026-06-01' this replaced.
  const FUTURE_TIER1 = Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60 * 24 * 90));
  const FUTURE_TIER2 = Timestamp.fromDate(new Date('2028-06-01T00:00:00Z'));

  it('allows spending a tier-2 credit that has not expired yet', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2ExpiresAt: FUTURE_TIER2 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 1, tier2ExpiresAt: FUTURE_TIER2 })));
  });

  it('rejects spending a tier-2 credit past its expiration', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2ExpiresAt: PAST })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 1, tier2ExpiresAt: PAST })));
  });

  it('allows spending a tier-1 credit that has not expired yet', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier1ExpiresAt: FUTURE_TIER1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 0, isProUser: true, tier1ExpiresAt: FUTURE_TIER1,
    })));
  });

  it('rejects spending a tier-1 credit past its expiration', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier1ExpiresAt: PAST })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier1Credits: 0, isProUser: true, tier1ExpiresAt: PAST,
    })));
  });

  it('a doc with no *ExpiresAt field at all is treated as not-expired (legacy tolerance)', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
  });
});

describe('group creation', () => {
  it('succeeds when paired with a matching entitlement decrement and uniqueness-key claim in one batch', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group1', createdAt: Timestamp.now() });
    batch.set(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    });
    await assertSucceeds(batch.commit());
  });

  it('rejects creating a group without a matching uniqueness-key claim in the same batch', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    // No groupUniquenessKeys write this time — even with a correct credit
    // decrement, the create rule's second getAfter() check should reject it.
    await assertFails(batch.commit());
  });

  it('rejects claiming a Cookbook Name + Family Name + Location combination that is already taken', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 5 }));
      await setDoc(doc(db, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group0', createdAt: Timestamp.now() });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 4 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group1', createdAt: Timestamp.now() });
    // The reservation doc already exists (from "group0"), so this write is
    // an update, not a create — denied, and the whole batch fails with it.
    await assertFails(batch.commit());
  });

  it('rejects creating a group without spending a credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'groups/group1'), groupData()));
  });

  it('rejects creating a group with no credits available', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 0 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: -1 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    await assertFails(batch.commit());
  });

  it("rejects creating a group on someone else's behalf", async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData({ createdByUserID: 'bob' }));
    await assertFails(batch.commit());
  });

  it('rejects a client setting isMFB true on a new group', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData({ isMFB: true }));
    batch.set(doc(alice, `groupUniquenessKeys/${GROUP1_UNIQUENESS_KEY}`), { groupID: 'group1', createdAt: Timestamp.now() });
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

describe('personalCookbooks', () => {
  function personalCookbookData(overrides = {}) {
    return {
      id: 'cb1', ownerUserID: 'alice', title: 'Weeknight Dinners',
      coverColorHex: 'C25432', coverStyleImageName: null, coverImageURL: null,
      sortOrder: 0, hasBeenConfigured: true, chaptersManuallyReordered: false,
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(), chapters: [],
      ...overrides,
    };
  }

  function personalRecipeData(overrides = {}) {
    return {
      id: 'recipe1', ownerUserID: 'alice', cookbookID: 'cb1', sectionID: null,
      title: 'Cornbread', summary: '', story: '',
      heroPhotoURL: null, galleryPhotoURLs: [],
      yield: '', prepTimeMinutes: null, cookTimeMinutes: null, totalTimeMinutes: null,
      ingredientSections: [], stepSections: [],
      notes: '', sourceType: 'manual', sourceURL: null, sourceAuthorText: null,
      externalSource: null, externalSourceID: null,
      calories: null, proteinGrams: null, fatGrams: null, carbsGrams: null,
      sugarGrams: null, fiberGrams: null, sodiumMilligrams: null,
      cuisine: null, course: null, dietaryLabels: [], allergens: [], tags: [], equipment: [],
      isFavorite: false, personalRating: null, privateNotes: '', isArchived: false,
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(), language: 'en',
      rootOriginRecipeID: null, immediateSourceRecipeID: null,
      sourceOwnerSnapshot: null, sourceGroupSnapshot: null,
      authorLineage: null, authorLineageIsExternal: false, inspirationCredit: null,
      videoURLs: [], prepSummary: null,
      ...overrides,
    };
  }

  it('an owner can write their own personal cookbook doc', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'personalCookbooks/cb1'), personalCookbookData()));
  });

  it("rejects writing a cookbook doc claiming someone else's ownerUserID", async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'personalCookbooks/cb1'), personalCookbookData({ ownerUserID: 'bob' })));
  });

  it('an owner can read their own personal cookbook doc', async () => {
    await seed((db) => setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'personalCookbooks/cb1')));
  });

  it("rejects a different user reading someone else's personal cookbook doc", async () => {
    await seed((db) => setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData()));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'personalCookbooks/cb1')));
  });

  it("rejects a different user overwriting someone else's personal cookbook doc", async () => {
    await seed((db) => setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData()));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'personalCookbooks/cb1'), personalCookbookData({ title: 'Hijacked' })));
  });

  it('an owner can write a recipe subdoc under their own cookbook', async () => {
    await seed((db) => setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'personalCookbooks/cb1/recipes/recipe1'), personalRecipeData()));
  });

  it("rejects writing a recipe subdoc claiming someone else's ownerUserID, even under your own cookbook", async () => {
    await seed((db) => setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'personalCookbooks/cb1/recipes/recipe1'), personalRecipeData({ ownerUserID: 'bob' })));
  });

  it("rejects a different user reading a recipe subdoc under someone else's cookbook", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'personalCookbooks/cb1'), personalCookbookData());
      await setDoc(doc(db, 'personalCookbooks/cb1/recipes/recipe1'), personalRecipeData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'personalCookbooks/cb1/recipes/recipe1')));
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

  it('a Pro User can self-create a member membership when the group auto-approves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true }));
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a non-Pro user can self-create a member membership on the MFB cookbook even without credits', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true, isMFB: true })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a non-Pro user cannot self-create a membership on a non-MFB auto-approve group without a Pro credit', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-create a membership via the auto path when the group does not auto-approve', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: false }));
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-grant admin via the auto-approve path even when the group allows it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ autoApproveJoinRequests: true }));
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('the founding admin membership needs no Pro User status — they already paid a tier-2 credit', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ createdByUserID: 'alice' })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
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

  // Exercises the exact update path AccountDeletionCoordinator's new
  // publication-tombstoning relies on (PublicationsServicing.
  // tombstoneOwnerAttribution): the owner overwriting `content` on their
  // own publication while `groupID`/`ownerUserID`/`sourceRecipeID`/`state`
  // stay put — the same shape as an ordinary "publish update."
  it('the owner can update content.authorLineage on their own publication (e.g. account-deletion tombstone)', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'publications/pub1'), publicationData({
      content: {
        title: 'Cornbread', summary: '', yield: '', totalTimeMinutes: null,
        ingredientSections: [], stepSections: [], notes: '', tags: [],
        authorLineage: 'Original contributor deleted',
      },
    })));
  });

  it('a non-owner member cannot rewrite the content of someone else\'s publication', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1'), publicationData({
      content: {
        title: 'Hijacked', summary: '', yield: '', totalTimeMinutes: null,
        ingredientSections: [], stepSections: [], notes: '', tags: [],
      },
    })));
  });
});

describe('join requests', () => {
  it('an active member cannot request to join the same group again', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'bob', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a Pro User can file a join request', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 })));
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a non-Pro user cannot file a join request against a non-MFB group without a Pro credit', async () => {
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a non-Pro user can file a join request against the MFB cookbook', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ isMFB: true })));
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
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
