const {
  initAdmin,
  setCors,
  requireUser,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
  isVerifiedHallymUser,
} = require('../_lib');
const { publicIdFromUrl, destroyPublicId } = require('../_cloudinary');
const { isAdminUser } = require('../_admin_access');

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });
  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'delete-media'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!isVerifiedHallymUser(decoded)) {
    return res.status(403).json({ error: 'verified-hallym-user-required' });
  }
  if (!(await enforceRateLimit(admin, req, res, {
    scope: 'delete-media-user',
    identifier: decoded.uid,
    max: 60,
    windowMs: 60 * 60 * 1000,
  }))) return;

  const urls = Array.isArray(req.body?.urls) ? req.body.urls : [];
  if (urls.length < 1 || urls.length > 10 || urls.some((url) => typeof url !== 'string')) {
    return res.status(400).json({ error: 'invalid-urls' });
  }
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  if (
    !cloudName ||
    !process.env.CLOUDINARY_API_KEY ||
    !process.env.CLOUDINARY_API_SECRET
  ) {
    return res.status(500).json({ error: 'cloudinary-not-configured' });
  }
  const isAdmin = isAdminUser(decoded);
  const publicIds = [...new Set(urls.map((url) => publicIdFromUrl(url, cloudName)).filter(Boolean))];
  if (publicIds.length !== urls.length) {
    return res.status(400).json({ error: 'invalid-cloudinary-url' });
  }
  if (!isAdmin && publicIds.some((id) => !id.startsWith(`latte/${decoded.uid}/`))) {
    return res.status(403).json({ error: 'media-not-owned' });
  }
  for (const publicId of publicIds) await destroyPublicId(publicId);
  return res.status(200).json({ ok: true, deleted: publicIds.length });
};
