const nodemailer = require('nodemailer');

// 메일 구현을 얇은 어댑터 뒤에 둬 API 핸들러가 라이브러리의 패키지
// 내보내기 방식에 결합되지 않게 한다. 테스트에서는 이 모듈만 대체하므로
// 실제 SMTP 접속 없이도 메일 내용과 발송 흐름을 검증할 수 있다.
function createTransport(options) {
  return nodemailer.createTransport(options);
}

module.exports = { createTransport };
