const crypto = require('node:crypto');

function publicIdFromUrl(value, expectedCloudName) {
  try {
    const url = new URL(String(value));
    if (url.protocol !== 'https:' || url.hostname !== 'res.cloudinary.com') return null;
    const parts = url.pathname.split('/').filter(Boolean);
    if (parts.length < 5 || parts[0] !== expectedCloudName || parts[1] !== 'image') {
      return null;
    }
    const uploadIndex = parts.indexOf('upload');
    if (uploadIndex < 0) return null;
    const versionIndex = parts.findIndex(
      (part, index) => index > uploadIndex && /^v\d+$/.test(part),
    );
    const start = versionIndex >= 0 ? versionIndex + 1 : uploadIndex + 1;
    if (start >= parts.length) return null;
    const publicId = parts.slice(start).join('/').replace(/\.[a-z0-9]+$/i, '');
    return publicId && !publicId.includes('..') ? publicId : null;
  } catch (_) {
    return null;
  }
}

async function destroyPublicId(publicId) {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;
  if (!cloudName || !apiKey || !apiSecret) {
    if (process.env.FIRESTORE_EMULATOR_HOST) return { skipped: 'emulator' };
    throw new Error('cloudinary-not-configured');
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = crypto
    .createHash('sha1')
    .update(`public_id=${publicId}&timestamp=${timestamp}${apiSecret}`)
    .digest('hex');
  const body = new URLSearchParams({
    public_id: publicId,
    timestamp: String(timestamp),
    api_key: apiKey,
    signature,
  });
  const response = await fetch(
    `https://api.cloudinary.com/v1_1/${cloudName}/image/destroy`,
    { method: 'POST', body },
  );
  if (!response.ok) throw new Error(`cloudinary-destroy-${response.status}`);
  const result = await response.json();
  if (!['ok', 'not found'].includes(result.result)) {
    throw new Error(`cloudinary-destroy-${result.result || 'unknown'}`);
  }
  return result;
}

async function deleteCloudinaryUrls(urls) {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  if (!cloudName && process.env.FIRESTORE_EMULATOR_HOST) return 0;
  const publicIds = [
    ...new Set(
      (Array.isArray(urls) ? urls : [])
        .map((url) => publicIdFromUrl(url, cloudName))
        .filter(Boolean),
    ),
  ];
  for (const publicId of publicIds) await destroyPublicId(publicId);
  return publicIds.length;
}

module.exports = { publicIdFromUrl, destroyPublicId, deleteCloudinaryUrls };
