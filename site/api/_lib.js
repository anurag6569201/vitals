// Vitals license server — shared helpers. Runs as Vercel serverless functions (Node 18+),
// with no npm dependencies. Storage: any Upstash-compatible Redis REST endpoint
// (Vercel KV / Upstash). See RELEASE.md › "Licenses across editions".
const crypto = require('crypto');

const BUNDLE_ID = 'com.anuragsingh.vitals';
const PRO_PRODUCT_ID = 'com.anuragsingh.vitals.pro';
/** One key works on one Mac at a time (deactivate to move it). */
const MAX_MACHINES = 1;
/** SHA-256 fingerprint of "Apple Root CA - G3", which signs every StoreKit 2 / App Store Server JWS. */
const APPLE_ROOT_G3_SHA256 =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

// ---------- HTTP ----------

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

async function readJSON(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') return JSON.parse(req.body || '{}');
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString('utf8');
  return text ? JSON.parse(text) : {};
}

/** Wraps a handler: POST only, JSON in/out, errors become clean JSON. */
function endpoint(fn) {
  return async (req, res) => {
    if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
    try {
      const body = await readJSON(req);
      const [status, out] = await fn(body);
      send(res, status, out);
    } catch (err) {
      if (!err.status) console.error(err);   // expected refusals aren't errors
      send(res, err.status || 500, { error: err.code || 'server_error', message: err.publicMessage || 'Something went wrong. Try again in a moment.' });
    }
  };
}

function fail(status, code, publicMessage) {
  const err = new Error(code);
  err.status = status; err.code = code; err.publicMessage = publicMessage;
  return err;
}

// ---------- Storage (Redis REST) ----------

async function redis(...command) {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) throw fail(500, 'not_configured', 'The license server is not set up yet.');
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
  });
  const json = await r.json();
  if (json.error) throw new Error('redis: ' + json.error);
  return json.result;
}

async function getJSON(key) {
  const raw = await redis('GET', key);
  return raw ? JSON.parse(raw) : null;
}
const setJSON = (key, value) => redis('SET', key, JSON.stringify(value));

// ---------- Apple JWS verification ----------

function b64url(input) {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

/**
 * Verifies a JWS signed by the App Store (StoreKit 2 transactions, App Store Server
 * Notifications): checks the x5c chain leaf → intermediate → Apple Root CA G3 (pinned by
 * fingerprint), certificate dates, and the ES256 signature. Returns the decoded payload.
 */
function verifyAppleJWS(jws) {
  if (typeof jws !== 'string' || jws.split('.').length !== 3) throw fail(400, 'bad_receipt', 'That purchase receipt looks malformed.');
  const [h, p, s] = jws.split('.');
  let header;
  try { header = JSON.parse(b64url(h).toString('utf8')); } catch { header = null; }
  if (!header) throw fail(400, 'bad_receipt', 'That purchase receipt looks malformed.');
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw fail(400, 'bad_receipt', 'That purchase receipt is not from the App Store.');
  }
  const [leaf, intermediate, root] = header.x5c.map((c) => new crypto.X509Certificate(Buffer.from(c, 'base64')));
  const now = Date.now();
  const inDate = (cert) => new Date(cert.validFrom).getTime() <= now && now <= new Date(cert.validTo).getTime();
  const chainOK =
    root.fingerprint256 === APPLE_ROOT_G3_SHA256 &&
    root.verify(root.publicKey) &&
    intermediate.verify(root.publicKey) &&
    leaf.verify(intermediate.publicKey) &&
    [leaf, intermediate, root].every(inDate);
  if (!chainOK) throw fail(400, 'bad_receipt', 'That purchase receipt is not signed by Apple.');
  const signatureOK = crypto.verify('sha256', Buffer.from(`${h}.${p}`), { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' }, b64url(s));
  if (!signatureOK) throw fail(400, 'bad_receipt', 'That purchase receipt failed verification.');
  return JSON.parse(b64url(p).toString('utf8'));
}

// ---------- Keys & activation tokens ----------

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // no 0/O, 1/I
function newKey() {
  const bytes = crypto.randomBytes(16);
  let chars = '';
  for (let i = 0; i < 16; i++) chars += ALPHABET[bytes[i] % ALPHABET.length];
  return `VITALS-${chars.slice(0, 4)}-${chars.slice(4, 8)}-${chars.slice(8, 12)}-${chars.slice(12, 16)}`;
}

function normalizeKey(raw) {
  const key = String(raw || '').trim().toUpperCase().replace(/\s+/g, '');
  if (!/^VITALS-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/.test(key)) {
    throw fail(400, 'bad_key', 'That doesn’t look like a Vitals license key.');
  }
  return key;
}

/**
 * Signed proof that `key` is active on `machine`, checked offline by the app with the
 * embedded public key. Ed25519; private key in LICENSE_SIGNING_KEY (PEM).
 */
function activationToken(key, machine) {
  const pem = process.env.LICENSE_SIGNING_KEY;
  if (!pem) throw fail(500, 'not_configured', 'The license server is not set up yet.');
  const payload = Buffer.from(JSON.stringify({ key, machine, iat: Math.floor(Date.now() / 1000) }));
  const signature = crypto.sign(null, payload, crypto.createPrivateKey(pem.replace(/\\n/g, '\n')));
  const enc = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${enc(payload)}.${enc(signature)}`;
}

function cleanMachine(raw) {
  const id = String(raw || '');
  if (!/^[a-f0-9]{64}$/.test(id)) throw fail(400, 'bad_machine', 'This Mac could not be identified.');
  return id;
}

module.exports = {
  BUNDLE_ID, PRO_PRODUCT_ID, MAX_MACHINES,
  endpoint, fail, redis, getJSON, setJSON, verifyAppleJWS, newKey, normalizeKey, activationToken, cleanMachine,
};
