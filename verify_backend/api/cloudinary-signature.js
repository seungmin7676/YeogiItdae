const crypto = require('crypto');
const { setCors, requireUser } = require('../_lib');

// 지금까지는 클라이언트가 unsigned upload preset으로 Cloudinary에 직접
// 업로드했다. unsigned preset은 cloud name/preset 이름만 알면(APK/웹
// 번들을 열어보면 누구나 알 수 있다) 앱을 거치지 않고도 임의 파일을 올릴
// 수 있어, 이 계정의 무료 티어 용량/대역폭을 앱과 무관한 제3자가 소진시킬
// 수 있는 위험이 있었다. 로그인한 사용자에게만 짧은 시간(서명에 포함된
// timestamp 기준 Cloudinary 기본 1시간) 유효한 서명을 발급해, 업로드
// preset을 "서명 필요"로 바꾸고 이 서명 없이는 업로드가 거부되게 한다.
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const apiSecret = process.env.CLOUDINARY_API_SECRET;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const uploadPreset = process.env.CLOUDINARY_UPLOAD_PRESET;
  if (!apiSecret || !apiKey || !cloudName || !uploadPreset) {
    return res.status(500).json({ error: 'cloudinary-not-configured' });
  }

  const timestamp = Math.floor(Date.now() / 1000);
  // Cloudinary 서명 규칙: 서명에 포함할 파라미터(file/cloud_name/api_key
  // 제외)를 키 이름 알파벳 순으로 정렬해 이어붙이고, 끝에 API secret을
  // 붙여 SHA-1 해시한다.
  const paramsToSign = `timestamp=${timestamp}&upload_preset=${uploadPreset}`;
  const signature = crypto
    .createHash('sha1')
    .update(paramsToSign + apiSecret)
    .digest('hex');

  return res.status(200).json({
    signature,
    timestamp,
    apiKey,
    cloudName,
    uploadPreset,
  });
};
