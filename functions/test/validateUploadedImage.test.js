const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateUploadedImage, isRealImage } = require('../validateUploadedImage');

function fakeBucket(fileBytesByPath) {
  const deletedPaths = [];
  return {
    deletedPaths,
    file(path) {
      return {
        async download() {
          const bytes = fileBytesByPath[path];
          if (!bytes) throw new Error(`no fake file at ${path}`);
          return [Buffer.from(bytes)];
        },
        async delete() {
          deletedPaths.push(path);
        },
      };
    },
  };
}

const REAL_JPEG_HEAD = [0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const REAL_PNG_HEAD = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0];
const NOT_AN_IMAGE_HEAD = Buffer.from('<html><body>not an image</body>', 'utf8');

test('isRealImage recognizes real JPEG and PNG magic bytes', () => {
  assert.equal(isRealImage(Buffer.from(REAL_JPEG_HEAD)), true);
  assert.equal(isRealImage(Buffer.from(REAL_PNG_HEAD)), true);
  assert.equal(isRealImage(NOT_AN_IMAGE_HEAD), false);
});

test('a real JPEG under publications/ is left alone', async () => {
  const bucket = fakeBucket({ 'publications/g1/c1/user1_recipe1.jpg': REAL_JPEG_HEAD });
  const result = await validateUploadedImage({ bucket, filePath: 'publications/g1/c1/user1_recipe1.jpg', contentType: 'image/jpeg' });

  assert.equal(result.deleted, false);
  assert.deepEqual(bucket.deletedPaths, []);
});

test('a real PNG under personalCookbooks/ is left alone', async () => {
  const bucket = fakeBucket({ 'personalCookbooks/user1/cover.jpg': REAL_PNG_HEAD });
  const result = await validateUploadedImage({ bucket, filePath: 'personalCookbooks/user1/cover.jpg', contentType: 'image/png' });

  assert.equal(result.deleted, false);
  assert.deepEqual(bucket.deletedPaths, []);
});

// The actual gap this closes: a client bypassing this app's own upload
// code, writing arbitrary content straight through the Storage SDK with a
// spoofed `image/*` header — the exact thing storage.rules' write-time
// contentType check can't catch, since rules can't read file bytes.
test('a non-image blob with a spoofed image/* header is deleted', async () => {
  const path = 'publications/g1/c1/attacker_recipe1.jpg';
  const bucket = fakeBucket({ [path]: NOT_AN_IMAGE_HEAD });
  const result = await validateUploadedImage({ bucket, filePath: path, contentType: 'image/jpeg' });

  assert.equal(result.deleted, true);
  assert.deepEqual(bucket.deletedPaths, [path]);
});

test('objects outside the two validated upload paths are never touched', async () => {
  const bucket = fakeBucket({});
  const result = await validateUploadedImage({ bucket, filePath: 'someOtherPrefix/thing.jpg', contentType: 'image/jpeg' });

  assert.equal(result.deleted, false);
  assert.deepEqual(bucket.deletedPaths, []);
});

test('objects without an image/* content type are left for something else to explain', async () => {
  const bucket = fakeBucket({});
  const result = await validateUploadedImage({ bucket, filePath: 'publications/g1/c1/user1_recipe1.jpg', contentType: 'application/octet-stream' });

  assert.equal(result.deleted, false);
  assert.deepEqual(bucket.deletedPaths, []);
});
