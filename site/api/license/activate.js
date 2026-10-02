// POST { key, machine, name } → { token }
// The direct-download edition activates a key on this Mac. One Mac per key.
const L = require('../_lib');

module.exports = L.endpoint(async ({ key: rawKey, machine: rawMachine, name }) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  const record = await L.getJSON(`key:${key}`);
  if (!record) throw L.fail(404, 'unknown_key', 'That license key wasn’t found. Check for typos.');
  if (record.revoked) throw L.fail(403, 'revoked', 'This key is no longer valid. Contact support if this looks wrong.');

  const machines = record.machines || [];
  if (!machines.some((m) => m.id === machine)) {
    if (machines.length >= L.MAX_MACHINES) {
      throw L.fail(409, 'in_use', 'This key is already active on another Mac. Open Vitals there and choose “Remove License From This Mac”, then try again.');
    }
    machines.push({ id: machine, name: String(name || 'Mac').slice(0, 60), activated: new Date().toISOString() });
    record.machines = machines;
    await L.setJSON(`key:${key}`, record);
  }
  return [200, { token: L.activationToken(key, machine) }];
});
