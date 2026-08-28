const { test } = require('node:test');
const assert = require('node:assert/strict');
const { publicIdFromUrl } = require('../_cloudinary');

test('Cloudinary URL에서 폴더를 포함한 public ID를 안전하게 추출한다', () => {
  assert.equal(
    publicIdFromUrl(
      'https://res.cloudinary.com/demo/image/upload/v1780000000/latte/user-1/photo-id.jpg',
      'demo',
    ),
    'latte/user-1/photo-id',
  );
});

test('다른 cloud·HTTP·비 Cloudinary URL은 삭제 대상으로 인정하지 않는다', () => {
  assert.equal(
    publicIdFromUrl(
      'https://res.cloudinary.com/other/image/upload/v1/latte/user/photo.jpg',
      'demo',
    ),
    null,
  );
  assert.equal(
    publicIdFromUrl('http://res.cloudinary.com/demo/image/upload/v1/a.jpg', 'demo'),
    null,
  );
  assert.equal(publicIdFromUrl('https://example.com/photo.jpg', 'demo'), null);
});
