// POST { key, machine } → { ok } — frees the key so it can move to another Mac.
const L = require('../_lib');

module.exports = L.endpoint(async ({ key: rawKey, machine: rawMachine }) => {
  const key = L.normalizeKey(rawKey);
  const machine = L.cleanMachine(rawMachine);
  const record = await L.getJSON(`key:${key}`);
  if (record) {
    record.machines = (record.machines || []).filter((m) => m.id !== machine);
    await L.setJSON(`key:${key}`, record);
  }
  return [200, { ok: true }];
});
