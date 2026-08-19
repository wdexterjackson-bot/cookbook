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
import { doc, setDoc, getDoc, deleteDoc, writeBatch, Timestamp, serverTimestamp } from 'firebase/firestore';

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

function groupData(overrides = {}) {
  return {
    id: 'group1',
    slug: 'group1',
    name: 'Barrentines',
    createdByDisplayName: 'Alice',
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
    approvalPolicy: 'anyAdministrator',
    isMFB: false,
    ...overrides,
  };
}

function groupCookbookData(overrides = {}) {
  return {
    id: 'cb-group1',
    groupID: 'group1',
    cookbookName: 'Barrentine Family Reunion',
    createdByUserID: 'alice',
    createdByDisplayName: 'Alice',
    createdAt: Timestamp.now(),
    coverImageURL: null,
    allowsMemberPublishing: true,
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

  // Annual Pro Membership credits — awarded via discount code
  // (DiscountCodePromo.swift), spent via redeemAnnualProMembershipCredit.
  it('rejects a create that tries to seed annual-membership fields directly', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ annualProMembershipCredits: 1 })));
  });

  it('allows redeeming the one valid discount code for a first-time credit', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      redeemedDiscountCodes: ['7595SLEDGERD'], annualProMembershipCredits: 1,
    })));
  });

  it('rejects redeeming an unknown code', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      redeemedDiscountCodes: ['NOT-A-REAL-CODE'], annualProMembershipCredits: 1,
    })));
  });

  it('rejects redeeming the same code a second time', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({
      redeemedDiscountCodes: ['7595SLEDGERD'], annualProMembershipCredits: 1,
    })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      redeemedDiscountCodes: ['7595SLEDGERD', '7595SLEDGERD'], annualProMembershipCredits: 2,
    })));
  });

  it('allows spending an annual-membership credit with an expiration within the ~1-year bound', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ annualProMembershipCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const oneYearOut = Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60 * 24 * 365));
    await assertSucceeds(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      annualProMembershipCredits: 0, annualProMembershipExpiresAt: oneYearOut,
    })));
  });

  it('rejects spending an annual-membership credit with an expiration far beyond the ~1-year bound', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ annualProMembershipCredits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const tenYearsOut = Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60 * 24 * 365 * 10));
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      annualProMembershipCredits: 0, annualProMembershipExpiresAt: tenYearsOut,
    })));
  });

  it('rejects smuggling an annual-membership credit change into a tier-2-spend write', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ annualProMembershipCredits: 0 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
      tier2Credits: 1, annualProMembershipCredits: 1,
    })));
  });

  // The six fields the Annual Pro Member sweep/webhook (Cloud Functions,
  // via the Admin SDK) writes — must never be settable by any client write,
  // including smuggled alongside an otherwise-legitimate transition. Each
  // one is tried on both create and every one of the five update branches;
  // one representative branch (tier-2 spend) per field keeps this from
  // being 30 near-identical cases, since all five branches now share the
  // same subscriptionServerFieldsUnchanged(...) guard.
  const SUBSCRIPTION_SERVER_ONLY_FIELDS = {
    annualProMembershipImagesRemovedAt: Timestamp.now(),
    annualProMembershipOriginalTransactionID: 'txn-123',
    annualProMembershipBillingRetryUntil: Timestamp.now(),
    annualProMembershipWillRenew: true,
    annualProMembershipWarnedAtDay75: true,
    annualProMembershipWarnedAtDay85: true,
  };

  for (const [field, value] of Object.entries(SUBSCRIPTION_SERVER_ONLY_FIELDS)) {
    it(`rejects seeding ${field} directly at create time`, async () => {
      const alice = testEnv.authenticatedContext('alice').firestore();
      await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({ [field]: value })));
    });

    it(`rejects smuggling ${field} into a tier-2-spend write`, async () => {
      await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData()));
      const alice = testEnv.authenticatedContext('alice').firestore();
      await assertFails(setDoc(doc(alice, 'entitlements/alice'), entitlementData({
        tier2Credits: 1, [field]: value,
      })));
    });
  }
});

describe('group creation', () => {
  it('succeeds when paired with a matching entitlement decrement, founder membership, and first cookbook in one batch', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    });
    batch.set(doc(alice, 'groupCookbooks/cb-group1'), groupCookbookData());
    await assertSucceeds(batch.commit());
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
    await assertFails(batch.commit());
  });

  it('rejects an invalid approvalPolicy value', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData({ approvalPolicy: 'nonsense' }));
    await assertFails(batch.commit());
  });
});

describe('groupCookbooks', () => {
  it("lets the founder create the group's first cookbook in the same batch as the group itself", async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/alice'), entitlementData({ tier2Credits: 1 })));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'entitlements/alice'), entitlementData({ tier2Credits: 0 }));
    batch.set(doc(alice, 'groups/group1'), groupData());
    batch.set(doc(alice, 'groupCookbooks/cb-group1'), groupCookbookData());
    await assertSucceeds(batch.commit());
  });

  it("rejects a cookbook create claiming a different user's createdByUserID than the actor, even during group creation", async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', tier2Credits: 1 })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    const batch = writeBatch(bob);
    batch.set(doc(bob, 'entitlements/bob'), entitlementData({ userID: 'bob', tier2Credits: 0 }));
    batch.set(doc(bob, 'groups/group1'), groupData({ createdByUserID: 'bob' }));
    // Bob is the group's real founder (would pass the getAfter() founder
    // check), but claims someone else made the cookbook — the plain
    // auth.uid == createdByUserID check on groupCookbooks/create itself
    // has to catch this independent of the founder branch.
    batch.set(doc(bob, 'groupCookbooks/cb-group1'), groupCookbookData({ createdByUserID: 'alice' }));
    await assertFails(batch.commit());
  });

  it('an admin can add a further cookbook to an already-existing group', async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'groupCookbooks/cb2'), groupCookbookData({ id: 'cb2' })));
  });

  it('a plain member cannot add a further cookbook to an already-existing group', async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'groupCookbooks/cb2'), groupCookbookData({ id: 'cb2', createdByUserID: 'bob' })));
  });

  it("a member can read their group's cookbook", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'groupCookbooks/cb-group1')));
  });

  it('a non-member cannot read a cookbook belonging to a private group they are not in', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ visibility: 'private' }));
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData());
    });
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'groupCookbooks/cb-group1')));
  });

  // Mirrors groups/{id}'s own public-read rule — needed so a public
  // cookbook's name/metadata is searchable without being a member
  // (fetchPublicGroupCookbooks).
  it('a non-member can read a cookbook belonging to a public group', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ visibility: 'public' }));
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData());
    });
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertSucceeds(getDoc(doc(mallory, 'groupCookbooks/cb-group1')));
  });

  // Real correctness gap: the founder branch used to be keyed only on
  // groups/{id}.createdByUserID, which never changes — so a founder who
  // self-demoted and left could still exploit this branch to inject
  // cookbooks into a group they're no longer even a member of, forever.
  it('rejects a departed founder from using the founder branch once their membership doc exists (even left)', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ createdByUserID: 'alice' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'left', source: 'founder', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'groupCookbooks/cb2'), groupCookbookData({ id: 'cb2', createdByUserID: 'alice' })));
  });

  it('rejects reparenting a cookbook to a different group', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData());
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'groupCookbooks/cb-group1'), groupCookbookData({ groupID: 'group2' })));
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

  it('a Pro User can self-create a member membership when the group needs no approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'noApprovalNeeded' }));
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a non-Pro user can self-create a member membership on the MFB cookbook even without credits', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'noApprovalNeeded', isMFB: true })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a non-Pro user cannot self-create a membership on a non-MFB no-approval group without a Pro credit', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'noApprovalNeeded' })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-create a membership via the auto path when the group requires approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'anyAdministrator' }));
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'auto', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('a user cannot self-grant admin via the auto path even when the group needs no approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'noApprovalNeeded' }));
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

  // Exercises the exact gap that would exist if canDecideJoinRequest()
  // (joinRequests/update) and this collection's "someone approved my
  // request" branch ever fell out of lock-step: under an anyUser policy, a
  // plain member (not an admin) can legally decide the request, so they
  // must also be able to create the resulting membership.
  it('under an anyUser approval policy, a plain member can create the membership their own approval unlocked', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'anyUser' }));
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('under a creatorOnly approval policy, an admin who is not the creator cannot create the resulting membership while the creator is still active', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'creatorOnly', createdByUserID: 'alice' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('an admin cannot remove a plain member via a direct write — must go through changeMemberRole', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'suspended', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
    }));
  });

  it('a plain member cannot remove anyone', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
      status: 'suspended', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
    }));
  });

  it('an admin cannot remove themselves this way (must leave or be demoted instead)', async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'suspended', source: 'founder', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
    }));
  });

  // The last-admin invariant (GroupPolicy.isLastActiveAdmin) can't be
  // enforced here — rules can't cheaply count active admins across a
  // collection — so a direct client write is no longer trusted with
  // self-demotion at all, last-admin or not; it must go through the
  // changeOwnMembership Cloud Function (Admin SDK, re-verifies server
  // side), covered in functions/test/changeOwnMembership.test.js.
  it('an admin cannot demote themselves via a direct write, even when another admin exists', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
      status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('an admin cannot self-leave via a direct write, even when another admin exists', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'memberships/group1_alice'), {
      id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
      status: 'left', source: 'founder', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
    }));
  });

  it('a plain member can still self-leave via a direct write, unaffected', async () => {
    await seed((db) => setDoc(doc(db, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'left', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
    }));
  });

  it("an admin cannot promote/demote someone else via a direct write — must go through changeMemberRole (functions/changeMemberRole.js), which can atomically re-verify the last-admin invariant a client-side transaction can't", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  // Membership.compositeID's own doc comment: status transitions reuse the
  // same document rather than piling up duplicates — this covers the
  // "update", not "create", path that reactivation actually takes.
  it('a decider can reactivate a previously removed/left member by re-approving them', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'anyAdministrator' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'suspended', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });

  it('someone who is not a decider cannot reactivate a removed member themselves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'anyAdministrator' }));
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'suspended', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'memberships/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
      status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
    }));
  });
});

function publicationData(overrides = {}) {
  return {
    id: 'pub1',
    groupID: 'group1',
    cookbookID: 'cb-group1',
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

  it('a member can publish to a cookbook that allows member publishing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData({ allowsMemberPublishing: true }));
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'publications/pub1'), publicationData({ ownerUserID: 'bob' })));
  });

  it('a member cannot publish to a cookbook that disallows member publishing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData({ allowsMemberPublishing: false }));
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1'), publicationData({ ownerUserID: 'bob' })));
  });

  it('an admin can publish to a cookbook regardless of allowsMemberPublishing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData({ allowsMemberPublishing: false }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'publications/pub1'), publicationData()));
  });

  it("rejects publishing with a cookbookID that belongs to a different group than claimed", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groupCookbooks/cb-group1'), groupCookbookData({ groupID: 'group2', allowsMemberPublishing: true }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    // publicationData() claims groupID: 'group1', but cb-group1 actually belongs to group2.
    await assertFails(setDoc(doc(alice, 'publications/pub1'), publicationData()));
  });

  it('the owner can delete their own publication', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(deleteDoc(doc(alice, 'publications/pub1')));
  });

  it("an admin can delete a member's publication", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData({ ownerUserID: 'bob' }));
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(deleteDoc(doc(alice, 'publications/pub1')));
  });

  it("a non-owner, non-admin member cannot delete someone else's publication", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(deleteDoc(doc(bob, 'publications/pub1')));
  });
});

describe('comments', () => {
  function commentData(overrides = {}) {
    return {
      id: 'comment1', publicationID: 'pub1', groupID: 'group1',
      authorUserID: 'bob', authorDisplayName: 'Bob', text: 'Delicious!',
      createdAt: Timestamp.now(),
      ...overrides,
    };
  }

  it('a member can comment when the publication has comments enabled', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData({ commentsEnabled: true }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'publications/pub1/comments/comment1'), commentData()));
  });

  it('rejects commenting when the publication has comments disabled', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData({ commentsEnabled: false }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1/comments/comment1'), commentData()));
  });

  it('rejects a non-member commenting even when comments are enabled', async () => {
    await seed((db) => setDoc(doc(db, 'publications/pub1'), publicationData({ commentsEnabled: true })));
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(setDoc(doc(mallory, 'publications/pub1/comments/comment1'), commentData({ authorUserID: 'mallory' })));
  });

  it('rejects impersonating another user as the comment author', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1'), publicationData({ commentsEnabled: true }));
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1/comments/comment1'), commentData({ authorUserID: 'alice' })));
  });

  it('the author can delete their own comment', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), commentData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(deleteDoc(doc(bob, 'publications/pub1/comments/comment1')));
  });

  it("an admin can delete someone else's comment", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), commentData());
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(deleteDoc(doc(alice, 'publications/pub1/comments/comment1')));
  });

  it("a non-author, non-admin member cannot delete someone else's comment", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), commentData());
    });
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(deleteDoc(doc(carol, 'publications/pub1/comments/comment1')));
  });

  it('rejects editing a comment after it is posted', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), commentData());
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1/comments/comment1'), commentData({ text: 'Edited' })));
  });

  // The one deliberate exception to "immutable": PublicationsServicing.
  // tombstoneCommentAuthorship uses this on account deletion so a deleted
  // user's comments read as "Deleted User" instead of staying attributed
  // to an account that no longer exists.
  it('the author can rewrite their own display name on a comment (tombstone), text untouched', async () => {
    const original = commentData();
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), original);
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'publications/pub1/comments/comment1'), { ...original, authorDisplayName: 'Deleted User' }));
  });

  it('rejects tombstoning display name together with a text change', async () => {
    const original = commentData();
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'member',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), original);
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'publications/pub1/comments/comment1'), { ...original, authorDisplayName: 'Deleted User', text: 'Edited' }));
  });

  it("rejects someone else rewriting another user's comment display name", async () => {
    const original = commentData();
    await seed(async (db) => {
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'publications/pub1/comments/comment1'), original);
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'publications/pub1/comments/comment1'), { ...original, authorDisplayName: 'Deleted User' }));
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
    await assertFails(setDoc(doc(bob, 'joinRequests/group1_bob'), {
      id: 'group1_bob', groupID: 'group1', requesterID: 'bob', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a Pro User can file a join request', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 })));
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a non-Pro user cannot file a join request against a non-MFB group without a Pro credit', async () => {
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a non-Pro user can file a join request against the MFB cookbook', async () => {
    await seed((db) => setDoc(doc(db, 'groups/group1'), groupData({ isMFB: true })));
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a doc id that does not match groupID_requesterID is rejected even if every other field is valid', async () => {
    await seed((db) => setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 })));
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  // Regression coverage for the duplicate-join-request bug: the deterministic
  // groupID_requesterID doc id means a second request lands on the same
  // document, so it goes through the update rule (not create) and must be
  // explicitly rejected while still pending rather than silently succeeding
  // as a second write — which is what let an admin see the same requester
  // twice with one row stuck pending forever.
  it('requesting to join again while already pending is rejected, not a silent duplicate', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 }));
      await setDoc(doc(db, 'joinRequests/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
      });
    });
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertFails(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: 'again', createdAt: Timestamp.now(),
      state: 'pending', decidedByUserID: null, decidedAt: null,
    }));
  });

  it('re-requesting after an earlier denial resets the same doc back to pending', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 }));
      await setDoc(doc(db, 'joinRequests/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'denied', decidedByUserID: 'alice', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
      });
    });
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('re-requesting after an earlier approval whose membership has since ended (e.g. removal) also resets to pending', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/carol'), entitlementData({ userID: 'carol', isProUser: true, tier1Credits: 0 }));
      await setDoc(doc(db, 'memberships/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', userID: 'carol', role: 'member',
        status: 'left', source: 'request', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'joinRequests/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'approved', decidedByUserID: 'alice', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
      });
    });
    const carol = testEnv.authenticatedContext('carol').firestore();
    await assertSucceeds(setDoc(doc(carol, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('a different user cannot reset someone else\'s denied request back to pending', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'entitlements/bob'), entitlementData({ userID: 'bob', isProUser: true, tier1Credits: 0 }));
      await setDoc(doc(db, 'joinRequests/group1_carol'), {
        id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'denied', decidedByUserID: 'alice', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'joinRequests/group1_carol'), {
      id: 'group1_carol', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
    }));
  });

  it('under the default anyAdministrator policy, a non-admin cannot approve a join request', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
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

  it('under the default anyAdministrator policy, an admin can approve a join request', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData());
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

  it('under a creatorOnly policy, the creator can approve while an active member (the normal case, since the founder membership is created atomically with the group)', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'creatorOnly', createdByUserID: 'alice' }));
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

  // Real correctness gap: creatorOnly used to pin decision power to
  // createdByUserID with no membership check at all, so a creator who
  // self-demoted and left could still silently decide forever, while any
  // admin actually still in the group had no way to decide anything.
  it('under a creatorOnly policy, once the creator is no longer an active member, any active admin can approve instead', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'creatorOnly', createdByUserID: 'alice' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'left', source: 'founder', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
        status: 'active', source: 'request', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'joinRequests/req1'), {
        id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
      });
    });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'approved', decidedByUserID: 'bob', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
    }));
  });

  it('under a creatorOnly policy, a departed creator can no longer decide once they have left', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'creatorOnly', createdByUserID: 'alice' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'member',
        status: 'left', source: 'founder', joinedAt: Timestamp.now(), leftAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'joinRequests/req1'), {
        id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
        state: 'pending', decidedByUserID: null, createdAt: Timestamp.now(), decidedAt: null,
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'approved', decidedByUserID: 'alice', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
    }));
  });

  it('under a creatorOnly policy, an admin who is not the creator cannot approve while the creator is still active', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'creatorOnly', createdByUserID: 'alice' }));
      await setDoc(doc(db, 'memberships/group1_alice'), {
        id: 'group1_alice', groupID: 'group1', userID: 'alice', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
      });
      await setDoc(doc(db, 'memberships/group1_bob'), {
        id: 'group1_bob', groupID: 'group1', userID: 'bob', role: 'admin',
        status: 'active', source: 'founder', joinedAt: Timestamp.now(), leftAt: null,
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

  it('under an anyUser policy, a plain member can approve', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groups/group1'), groupData({ approvalPolicy: 'anyUser' }));
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
    await assertSucceeds(setDoc(doc(bob, 'joinRequests/req1'), {
      id: 'req1', groupID: 'group1', requesterID: 'carol', note: null,
      state: 'approved', decidedByUserID: 'bob', createdAt: Timestamp.now(), decidedAt: Timestamp.now(),
    }));
  });
});

function invitationData(overrides = {}) {
  return {
    id: 'invite1', groupID: 'group1', inviterID: 'alice',
    inviteeIdentifier: 'bob@example.com', state: 'pending',
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

describe('invitations', () => {
  it('an invitee identified by email can read their own invitation', async () => {
    await seed((db) => setDoc(doc(db, 'invitations/invite1'), invitationData()));
    const bob = testEnv.authenticatedContext('bob', { email: 'bob@example.com' }).firestore();
    await assertSucceeds(getDoc(doc(bob, 'invitations/invite1')));
  });

  // The real correctness gap this covers: inviteeIdentifier can now hold a
  // UID (friend invites), not just an email — the original rule only ever
  // checked request.auth.token.email, so a UID-identified invitee could
  // never read or accept their own invitation.
  it('an invitee identified by userID can read their own invitation', async () => {
    await seed((db) => setDoc(doc(db, 'invitations/invite1'), invitationData({ inviteeIdentifier: 'bob' })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'invitations/invite1')));
  });

  it('an invitee identified by userID can accept their own invitation', async () => {
    await seed((db) => setDoc(doc(db, 'invitations/invite1'), invitationData({ inviteeIdentifier: 'bob' })));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'invitations/invite1'), invitationData({
      inviteeIdentifier: 'bob', state: 'accepted',
    })));
  });

  it('a stranger cannot read an invitation meant for someone else', async () => {
    await seed((db) => setDoc(doc(db, 'invitations/invite1'), invitationData({ inviteeIdentifier: 'bob' })));
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'invitations/invite1')));
  });
});

// SAFE-002: sendFriendRequest is a direct client write, gated only by
// firestore.rules — a sender's UID is visible to every co-member of any
// group they're in, so this pairs every create/re-request write with a
// rate-limit-counter increment in the same batch (see
// friendRequestRateLimitPaid()'s doc comment in firestore.rules).
function payRateLimitBatch(batch, db, senderID, { windowStart, count } = {}) {
  batch.set(doc(db, `friendRequestRateLimits/${senderID}`), {
    windowStart: windowStart ?? serverTimestamp(),
    count: count ?? 1,
  });
}

describe('friendRequests', () => {
  it('a user can send a friend request, paired with a rate-limit increment', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'alice');
    await assertSucceeds(batch.commit());
  });

  it('rejects sending a friend request without the paired rate-limit write', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
  });

  it('rejects a friend request referencing an old, already-paid rate-limit count instead of a fresh increment', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequestRateLimits/alice'), { windowStart: Timestamp.now(), count: 5 }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    // Not incrementing — just referencing the same count already there.
    await assertFails(batch.commit());
  });

  it('rejects a 21st friend request within the same hour (the 20-attempt cap)', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequestRateLimits/alice'), { windowStart: Timestamp.now(), count: 20 }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_carol'), {
      id: 'alice_carol', senderID: 'alice', recipientID: 'carol',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    batch.set(doc(alice, 'friendRequestRateLimits/alice'), { windowStart: Timestamp.now(), count: 21 });
    await assertFails(batch.commit());
  });

  it('allows a fresh request once the rate-limit window has expired, resetting the count', async () => {
    const overAnHourAgo = Timestamp.fromMillis(Date.now() - 3601000);
    await seed((db) => setDoc(doc(db, 'friendRequestRateLimits/alice'), { windowStart: overAnHourAgo, count: 20 }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_carol'), {
      id: 'alice_carol', senderID: 'alice', recipientID: 'carol',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'alice');
    await assertSucceeds(batch.commit());
  });

  it("rejects sending a friend request on someone else's behalf", async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/bob_carol'), {
      id: 'bob_carol', senderID: 'bob', recipientID: 'carol',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'bob');
    await assertFails(batch.commit());
  });

  it('rejects a self-friend-request', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_alice'), {
      id: 'alice_alice', senderID: 'alice', recipientID: 'alice',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'alice');
    await assertFails(batch.commit());
  });

  it('the recipient can accept a pending request', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(setDoc(doc(bob, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'accepted', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
  });

  it('the sender cannot unilaterally accept their own request', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'accepted', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
  });

  it('the original sender can re-request after an earlier decline, paired with a rate-limit increment', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'declined', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'alice');
    await assertSucceeds(batch.commit());
  });

  it('rejects re-requesting after a decline without the paired rate-limit write', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'declined', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
  });

  it('the sender can cancel their own pending request', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'cancelled', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
  });

  it('the recipient cannot cancel a request sent to them', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'cancelled', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
  });

  it('the original sender can re-request after cancelling, paired with a rate-limit increment', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'cancelled', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    });
    payRateLimitBatch(batch, alice, 'alice');
    await assertSucceeds(batch.commit());
  });
});

describe('friendships', () => {
  it('creating a friendship succeeds when paired with the matching request flipping to accepted, in one batch', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'pending', createdAt: Timestamp.now(), respondedAt: null,
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    const batch = writeBatch(bob);
    batch.set(doc(bob, 'friendRequests/alice_bob'), {
      id: 'alice_bob', senderID: 'alice', recipientID: 'bob',
      status: 'accepted', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    });
    batch.set(doc(bob, 'friendships/alice_bob'), {
      id: 'alice_bob', userIDs: ['alice', 'bob'], becameFriendsAt: Timestamp.now(),
    });
    await assertSucceeds(batch.commit());
  });

  it('rejects creating a friendship with no accepted request behind it', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'friendships/alice_bob'), {
      id: 'alice_bob', userIDs: ['alice', 'bob'], becameFriendsAt: Timestamp.now(),
    }));
  });

  it('rejects a self-friendship (both userIDs the same)', async () => {
    await seed((db) => setDoc(doc(db, 'friendRequests/alice_alice'), {
      id: 'alice_alice', senderID: 'alice', recipientID: 'alice',
      status: 'accepted', createdAt: Timestamp.now(), respondedAt: Timestamp.now(),
    }));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'friendships/alice_alice'), {
      id: 'alice_alice', userIDs: ['alice', 'alice'], becameFriendsAt: Timestamp.now(),
    }));
  });

  it('either party can read the friendship', async () => {
    await seed((db) => setDoc(doc(db, 'friendships/alice_bob'), {
      id: 'alice_bob', userIDs: ['alice', 'bob'], becameFriendsAt: Timestamp.now(),
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'friendships/alice_bob')));
  });

  it('a third party cannot read the friendship', async () => {
    await seed((db) => setDoc(doc(db, 'friendships/alice_bob'), {
      id: 'alice_bob', userIDs: ['alice', 'bob'], becameFriendsAt: Timestamp.now(),
    }));
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'friendships/alice_bob')));
  });

  it('either party can remove the friendship', async () => {
    await seed((db) => setDoc(doc(db, 'friendships/alice_bob'), {
      id: 'alice_bob', userIDs: ['alice', 'bob'], becameFriendsAt: Timestamp.now(),
    }));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(deleteDoc(doc(bob, 'friendships/alice_bob')));
  });
});
