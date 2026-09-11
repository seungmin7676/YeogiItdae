const ADMIN_EMAILS = new Set([
  'admin1@hallym.ac.kr',
  'admin2@hallym.ac.kr',
  'admin3@hallym.ac.kr',
  'admin4@hallym.ac.kr',
  'admin5@hallym.ac.kr',
]);

function isAdminEmail(email) {
  return typeof email === 'string' && ADMIN_EMAILS.has(email.toLowerCase());
}

function isAdminUser(decoded) {
  return decoded?.email_verified === true && isAdminEmail(decoded.email);
}

module.exports = { ADMIN_EMAILS, isAdminEmail, isAdminUser };
