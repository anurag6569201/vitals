// POST { transaction: "<StoreKit 2 Transaction.jwsRepresentation>" } → { key }
// Called by the Mac App Store edition after purchase. One key per purchase: asking again
// (another Mac, a reinstall) returns the same key.
import * as L from '../../../server/license.js';

export const onRequest = L.endpoint(async ({ transaction }, env) => {
  const t = await L.verifyAppleJWS(transaction);
  if (t.bundleId !== L.BUNDLE_ID) throw L.fail(400, 'wrong_app', 'That purchase is for a different app.');
  if (t.productId !== L.PRO_PRODUCT_ID) throw L.fail(400, 'wrong_product', 'That purchase isn’t Vitals Pro.');
  if (t.revocationDate) throw L.fail(403, 'not_valid', 'This purchase is no longer valid.');

  const otid = String(t.originalTransactionId);
  // UNIQUE(original_transaction_id): if two requests race, only one key is ever created.
  await env.DB.prepare(
    `INSERT INTO licenses (key, source, original_transaction_id, environment, created)
     VALUES (?, 'appstore', ?, ?, ?) ON CONFLICT(original_transaction_id) DO NOTHING`
  ).bind(L.newKey(), otid, t.environment || 'Production', new Date().toISOString()).run();

  const record = await L.getLicenseForPurchase(env.DB, otid);
  if (!record) throw L.fail(500, 'server_error', 'Something went wrong. Try again in a moment.');
  if (record.revoked) throw L.fail(403, 'not_valid', 'This purchase is no longer valid.');
  return [200, { key: record.key }];
});
