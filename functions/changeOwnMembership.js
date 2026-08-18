// Closes a real gap in firestore.rules: GroupPolicy.isLastActiveAdmin
// (the "the sole admin can't demote themselves or leave, since that would
// strand the group with no admin at all") is enforced by
// FirestoreGroupsService.updateRole/leaveGroup client-side, but rules
// can't cheaply count active admins across a collection, so nothing
// server-side ever backed that invariant. Any client writing directly to
// Firestore — bypassing the app's own service layer entirely — could
// demote or remove the last admin from a group. This callable re-verifies
// the invariant with the Admin SDK (same re-verification shape as
// deleteGroupPermanently.js) before performing the write itself; the
// corresponding firestore.rules branches for self-leave-as-admin and
// self-demote no longer allow a direct client write at all, so this is
// now the *only* path for those two mutations, not just a rubber stamp.
//
// Deliberately self-only — there's no `userID` param, only the caller's
// own membership is ever touched. An admin removing or demoting *someone
// else* can never zero out a group's admin count (the acting admin stays
// admin), so those stay direct Firestore writes, unaffected by this.

async function changeOwnMembership({ db, groupID, action, callerUserID }) {
  const trimmedGroupID = (groupID || '').trim();
  if (!trimmedGroupID) {
    throw new Error('groupID is required');
  }
  if (action !== 'leave' && action !== 'demote') {
    throw new Error('action must be "leave" or "demote"');
  }

  const membershipsSnapshot = await db.collection('memberships').where('groupID', '==', trimmedGroupID).get();
  const activeMemberships = membershipsSnapshot.docs
    .map((docSnap) => ({ ref: docSnap.ref, data: docSnap.data() }))
    .filter((entry) => entry.data.status === 'active');

  const callerEntry = activeMemberships.find((entry) => entry.data.userID === callerUserID);
  if (!callerEntry) {
    throw new Error('You are not an active member of this group.');
  }

  if (action === 'leave' && activeMemberships.length === 1) {
    // Mirrors leaveGroup's own branch order client-side — the last active
    // member overall leaves by deleting the whole group, not by flipping
    // this membership to 'left'.
    throw new Error('You are the last active member — use deleteGroupPermanently instead.');
  }

  const callerIsAdmin = callerEntry.data.role === 'admin';
  const otherActiveAdminExists = activeMemberships.some(
    (entry) => entry.data.role === 'admin' && entry.data.userID !== callerUserID
  );

  if (action === 'demote' && !callerIsAdmin) {
    throw new Error('You are not an admin of this group.');
  }
  if ((action === 'leave' || action === 'demote') && callerIsAdmin && !otherActiveAdminExists) {
    throw new Error('The last admin of a group can\'t leave or be demoted — promote someone else first.');
  }

  if (action === 'leave') {
    await callerEntry.ref.update({ status: 'left', leftAt: new Date() });
  } else {
    await callerEntry.ref.update({ role: 'member' });
  }

  return { ok: true };
}

module.exports = { changeOwnMembership };
