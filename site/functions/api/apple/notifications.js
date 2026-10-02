// App Store Server Notifications V2 → set https://<your domain>/api/apple/notifications in
// App Store Connect › App Information (Production and Sandbox).
// A refund or revocation turns the matching license key off everywhere; a reversed refund turns it back on.
import * as L from '../../../server/license.js';

export const onRequest = L.endpoint(async ({ signedPayload }, env) => {
  const note = await L.verifyAppleJWS(signedPayload);
  const type = note.notificationType;
  const signed = note.data && note.data.signedTransactionInfo;
  if (!signed) return [200, { ok: true }];
  const t = await L.verifyAppleJWS(signed);
  if (t.bundleId !== L.BUNDLE_ID || t.productId !== L.PRO_PRODUCT_ID) return [200, { ok: true }];
  const otid = String(t.originalTransactionId);

  if (type === 'REFUND' || type === 'REVOKE') {
    await env.DB.prepare(
      'UPDATE licenses SET revoked = 1, revoked_at = ?, revoked_reason = ? WHERE original_transaction_id = ?'
    ).bind(new Date().toISOString(), type, otid).run();
  } else if (type === 'REFUND_REVERSED') {
    await env.DB.prepare(
      'UPDATE licenses SET revoked = 0, revoked_at = NULL, revoked_reason = NULL WHERE original_transaction_id = ?'
    ).bind(otid).run();
  }
  return [200, { ok: true }];
});
