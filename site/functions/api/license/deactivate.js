// POST { key, machine } → { ok } — frees the key so it can move to another Mac.
import * as L from '../../../server/license.js';

export const onRequest = L.endpoint(async ({ key: rawKey, machine: rawMachine }, env) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  await env.DB.prepare('DELETE FROM activations WHERE key = ? AND machine = ?').bind(key, machine).run();
  return [200, { ok: true }];
});
