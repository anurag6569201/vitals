// POST { key, machine, name } → { token }
// The direct-download edition activates a key on this Mac. One Mac per key.
import * as L from '../../../server/license.js';

export const onRequest = L.endpoint(async ({ key: rawKey, machine: rawMachine, name }, env) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  const record = await L.getLicense(env.DB, key);
  if (!record) throw L.fail(404, 'unknown_key', 'That license key wasn’t found. Check for typos.');
  if (record.revoked) throw L.fail(403, 'revoked', 'This key is no longer valid. Contact support if this looks wrong.');

  if (!(await L.isActivated(env.DB, key, machine))) {
    // One statement, so two Macs activating at once can't both get in.
    const result = await env.DB.prepare(
      `INSERT INTO activations (key, machine, name, activated)
       SELECT ?1, ?2, ?3, ?4 WHERE (SELECT COUNT(*) FROM activations WHERE key = ?1) < ?5`
    ).bind(key, machine, String(name || 'Mac').slice(0, 60), new Date().toISOString(), L.MAX_MACHINES).run();
    if (!result.meta || result.meta.changes !== 1) {
      throw L.fail(409, 'in_use', 'This key is already active on another Mac. Open Vitals there and choose “Remove License From This Mac”, then try again.');
    }
  }
  return [200, { token: L.activationToken(env, key, machine) }];
});
