// POST { key, machine } → { valid, reason? } — the app re-checks every couple of weeks.
const L = require('../_lib');

module.exports = L.endpoint(async ({ key: rawKey, machine: rawMachine }) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  const record = await L.getJSON(`key:${key}`);
  if (!record) return [200, { valid: false, reason: 'unknown_key' }];
  if (record.revoked) return [200, { valid: false, reason: 'revoked' }];
  if (!(record.machines || []).some((m) => m.id === machine)) return [200, { valid: false, reason: 'not_activated' }];
  return [200, { valid: true }];
});
