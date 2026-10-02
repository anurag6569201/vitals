// POST { transaction: "<StoreKit 2 Transaction.jwsRepresentation>" } → { key }
// Called by the Mac App Store edition after purchase. One key per purchase: asking again
// (another Mac, a reinstall) returns the same key.
const L = require('../_lib');

module.exports = L.endpoint(async ({ transaction }) => {
  const t = L.verifyAppleJWS(transaction);
  if (t.bundleId !== L.BUNDLE_ID) throw L.fail(400, 'wrong_app', 'That purchase is for a different app.');
  if (t.productId !== L.PRO_PRODUCT_ID) throw L.fail(400, 'wrong_product', 'That purchase isn’t Vitals Pro.');
  if (t.revocationDate) throw L.fail(403, 'not_valid', 'This purchase is no longer valid.');

  const otid = String(t.originalTransactionId);
  const existing = await L.redis('GET', `claim:${otid}`);
  if (existing) {
    const record = await L.getJSON(`key:${existing}`);
    if (record && record.revoked) throw L.fail(403, 'not_valid', 'This purchase is no longer valid.');
    return [200, { key: existing }];
  }
  const key = L.newKey();
  // NX: if two requests race, only one key is ever created for a purchase.
  const won = await L.redis('SET', `claim:${otid}`, key, 'NX');
  if (won !== 'OK') return [200, { key: await L.redis('GET', `claim:${otid}`) }];
  await L.setJSON(`key:${key}`, {
    source: 'appstore', originalTransactionId: otid, environment: t.environment || 'Production',
    created: new Date().toISOString(), revoked: false, machines: [],
  });
  return [200, { key }];
});
