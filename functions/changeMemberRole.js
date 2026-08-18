// Closes the same class of gap changeOwnMembership.js closes for
// self-targeting mutations, but for an admin acting on *someone else's*
// membership (promote/demote/remove). The client-side equivalent
// (FirestoreGroupsService.updateRole/removeMember) used to do a plain
// read-then-write with no transaction — the old inline comment claimed
// this was "provably safe... since the acting admin stays admin," which
// only holds for a single write in isolation. Two admins simultaneously
// demoting/removing *each other* both read "2 active admins, safe to
// proceed" and both commit, leaving zero — a group with no admin at all,
// permanently unmanageable since promoting requires being one.
//
// The client Firestore SDK's Transaction type has no query support (only
// get(DocumentReference)), so a client-side transaction can't atomically
// re-count active admins the way this needs — only the Admin SDK's
// Transaction.get() accepts a Query. Hence a Cloud Function, same
// reasoning as changeOwnMembership.js.

async function changeMemberRole({ db, groupID, targetUserID, action, callerUserID }) {
  const trimmedGroupID = (groupID || '').trim();
  const trimmedTargetUserID = (targetUserID || '').trim();
  if (!trimmedGroupID || !trimmedTargetUserID) {
    throw new Error('groupID and targetUserID are required');
  }
  if (trimmedTargetUserID === callerUserID) {
    throw new Error('Use changeOwnMembership for your own membership.');
  }
  if (action !== 'promote' && action !== 'demote' && action !== 'remove') {
    throw new Error('action must be "promote", "demote", or "remove"');
  }

  const membershipsQuery = db.collection('memberships').where('groupID', '==', trimmedGroupID);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(membershipsQuery);
    const entries = snapshot.docs.map((docSnap) => ({ ref: docSnap.ref, data: docSnap.data() }));
    const activeEntries = entries.filter((entry) => entry.data.status === 'active');

    const callerEntry = activeEntries.find((entry) => entry.data.userID === callerUserID);
    if (!callerEntry || callerEntry.data.role !== 'admin') {
      throw new Error('You are not an active admin of this group.');
    }
    const targetEntry = activeEntries.find((entry) => entry.data.userID === trimmedTargetUserID);
    if (!targetEntry) {
      throw new Error('That member is not active in this group.');
    }

    if (action === 'promote') {
      transaction.update(targetEntry.ref, { role: 'admin' });
      return;
    }

    // demote and remove both need the last-admin invariant re-verified —
    // the exact race this function exists to close.
    const otherActiveAdminExists = activeEntries.some(
      (entry) => entry.data.role === 'admin' && entry.data.userID !== trimmedTargetUserID
    );
    if (targetEntry.data.role === 'admin' && !otherActiveAdminExists) {
      throw new Error("The last admin of a group can't be demoted or removed — promote someone else first.");
    }

    if (action === 'demote') {
      transaction.update(targetEntry.ref, { role: 'member' });
    } else {
      transaction.update(targetEntry.ref, { status: 'suspended', leftAt: new Date() });
    }
  });

  return { ok: true };
}

module.exports = { changeMemberRole };
