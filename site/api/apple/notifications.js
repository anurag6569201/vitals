// App Store Server Notifications V2 → set this URL in App Store Connect › App Information.
// A refund or revocation turns the matching license key off everywhere.
const L = require('../_lib');

module.exports = L.endpoint(async ({ signedPayload }) => {
  const note = L.verifyAppleJWS(signedPayload);
  const type = note.notificationType;
  if ((type === 'REFUND' || type === 'REVOKE') && note.data && note.data.signedTransactionInfo) {
    const t = L.verifyAppleJWS(note.data.signedTransactionInfo);
    if (t.bundleId === L.BUNDLE_ID && t.productId === L.PRO_PRODUCT_ID) {
      const key = await L.redis('GET', `claim:${t.originalTransactionId}`);
      if (key) {
        const record = await L.getJSON(`key:${key}`);
        if (record) {
          record.revoked = true;
          record.revokedAt = new Date().toISOString();
          record.revokedReason = type;
          await L.setJSON(`key:${key}`, record);
        }
      }
    }
  }
  // REFUND_REVERSED: re-enable.
  if (type === 'REFUND_REVERSED' && note.data && note.data.signedTransactionInfo) {
    const t = L.verifyAppleJWS(note.data.signedTransactionInfo);
    const key = await L.redis('GET', `claim:${t.originalTransactionId}`);
    const record = key && (await L.getJSON(`key:${key}`));
    if (record) { record.revoked = false; await L.setJSON(`key:${key}`, record); }
  }
  return [200, { ok: true }];
});
