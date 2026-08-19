// storage.rules can only check the client-declared Content-Type header at
// write time — Storage security rules have no way to read the actual bytes
// of the object being written. This app's own upload code always sends a
// real JPEG (FirebaseRecipePhotoUploadService/FirebasePersonalCookbookPhoto
// UploadService both hardcode `metadata.contentType = "image/jpeg"`), but
// nothing stops a client from bypassing the app entirely and writing an
// arbitrary blob straight through the Storage SDK with a spoofed `image/*`
// header — the write-time rule (`contentType.matches('image/.*')`) would
// wave it straight through.
//
// This is the read-after-write half of that check: once an object lands
// under one of the two paths this app ever accepts uploads on, re-verify
// its real magic bytes and delete it if they don't match a real image
// format. Deliberately narrow — JPEG and PNG only, matching what this app's
// own uploaders actually produce — not a general-purpose file-type sniffer,
// virus scanner, or EXIF stripper (SEC-003's fuller scope, out of reach for
// a solo-maintained app at this scale).

const JPEG_MAGIC = [0xff, 0xd8, 0xff];
const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

function matchesMagic(buffer, magic) {
  if (buffer.length < magic.length) return false;
  return magic.every((byte, index) => buffer[index] === byte);
}

function isRealImage(buffer) {
  return matchesMagic(buffer, JPEG_MAGIC) || matchesMagic(buffer, PNG_MAGIC);
}

// The only two prefixes storage.rules ever accepts a client write under —
// see that file's two `match` blocks. Anything else (shouldn't exist, but
// defense-in-depth) is left alone rather than guessed at.
const VALIDATED_PREFIXES = ['publications/', 'personalCookbooks/'];

async function validateUploadedImage({ bucket, filePath, contentType }) {
  if (!VALIDATED_PREFIXES.some((prefix) => filePath.startsWith(prefix))) {
    return { deleted: false, reason: 'not a validated upload path' };
  }
  if (!contentType || !contentType.startsWith('image/')) {
    // storage.rules already requires an image/* header at write time for
    // these paths — reaching here with something else means the object
    // was created outside that rule (Admin SDK, console), not a client
    // spoof this check is meant to catch.
    return { deleted: false, reason: 'not flagged as an image at write time' };
  }

  const file = bucket.file(filePath);
  const [head] = await file.download({ start: 0, end: 15 });
  if (isRealImage(head)) {
    return { deleted: false, reason: 'valid image' };
  }

  await file.delete({ ignoreNotFound: true });
  return { deleted: true, reason: 'declared image/* but content did not match a real image format' };
}

module.exports = { validateUploadedImage, isRealImage };
