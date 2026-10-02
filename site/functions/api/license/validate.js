// POST { key, machine } → { valid, reason? } — the app re-checks every couple of weeks.
import * as L from '../../../server/license.js';

export const onRequest = L.endpoint(async ({ key: rawKey, machine: rawMachine }, env) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  const record = await L.getLicense(env.DB, key);
  if (!record) return [200, { valid: false, reason: 'unknown_key' }];
  if (record.revoked) return [200, { valid: false, reason: 'revoked' }];
  if (!(await L.isActivated(env.DB, key, machine))) return [200, { valid: false, reason: 'not_activated' }];
  return [200, { valid: true }];
});
