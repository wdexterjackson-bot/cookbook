// Full cascade deletion for a Family Cookbook group once its last active
// member has left: memberships, publications, their Storage photos, the
// groupUniquenessKeys reservation doc (so the cookbook-name/family-name/
// location combo can be reused), and the group doc itself. None of this is
// reachable from the client — firestore.rules sets `allow delete: if false`
// on every one of these collections, and storage.rules only lets a user
// delete files they themselves uploaded (no admin override) — so this
// always runs through the Admin SDK (via `db`/`bucket`, injected the same
// way applyPurchaseClaim.js injects verifyTransaction), which bypasses
// both rules files.

async function deletePublicationsForGroup(db, groupID) {
  const snapshot = await db.collection('publications').where('groupID', '==', groupID).get();
  await Promise.all(snapshot.docs.map((docSnap) => docSnap.ref.delete()));
}

async function deletePhotosForGroup(bucket, groupID) {
  const [files] = await bucket.getFiles({ prefix: `publications/${groupID}/` });
  await Promise.all(files.map((file) => file.delete()));
}

async function deleteGroupPermanently({ db, bucket, groupID, callerUserID }) {
  const trimmedGroupID = (groupID || '').trim();
  if (!trimmedGroupID) {
    throw new Error('groupID is required');
  }

  const groupRef = db.collection('groups').doc(trimmedGroupID);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    // Already gone — treat as success so a retried call is safe.
    return { deleted: false };
  }
  const groupData = groupSnap.data();

  const membershipsSnapshot = await db.collection('memberships').where('groupID', '==', trimmedGroupID).get();
  const isActiveMember = membershipsSnapshot.docs.some((docSnap) => {
    const data = docSnap.data();
    return data.userID === callerUserID && data.status === 'active';
  });
  if (!isActiveMember) {
    throw new Error('Only an active member of this cookbook can delete it.');
  }

  await Promise.all(membershipsSnapshot.docs.map((docSnap) => docSnap.ref.delete()));
  await deletePublicationsForGroup(db, trimmedGroupID);
  await deletePhotosForGroup(bucket, trimmedGroupID);

  if (groupData.uniquenessKey) {
    await db.collection('groupUniquenessKeys').doc(groupData.uniquenessKey).delete();
  }

  await groupRef.delete();

  return { deleted: true };
}

module.exports = { deleteGroupPermanently };
