// Vitals license server — shared helpers for Cloudflare Pages Functions (functions/api/*).
// Storage: Cloudflare D1 (binding DB, schema in migrations/). Signing key: secret LICENSE_SIGNING_KEY.
// See RELEASE.md › "Licenses across editions".
import { Buffer } from 'node:buffer';
import crypto from 'node:crypto';

export const BUNDLE_ID = 'com.anuragsingh.vitals';
export const PRO_PRODUCT_ID = 'com.anuragsingh.vitals.pro';
/** One key works on one Mac at a time (deactivate to move it). */
export const MAX_MACHINES = 1;
/** SHA-256 fingerprint of "Apple Root CA - G3", which signs every StoreKit 2 / App Store Server JWS. */
export const APPLE_ROOT_G3_SHA256 =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

// ---------- HTTP ----------

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

export function fail(status, code, publicMessage) {
  const err = new Error(code);
  err.status = status;
  err.code = code;
  err.publicMessage = publicMessage;
  return err;
}

/**
 * Wraps a handler as a Pages Function: POST only, JSON in/out, errors become clean JSON.
 * `fn(body, env)` returns [status, body].
 */
export function endpoint(fn) {
  return async ({ request, env }) => {
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    try {
      const text = await request.text();
      let body;
      try { body = text ? JSON.parse(text) : {}; } catch { throw fail(400, 'bad_json', 'The request was malformed.'); }
      if (!env.DB) throw fail(500, 'not_configured', 'The license server is not set up yet.');
      const [status, out] = await fn(body, env);
      return json(status, out);
    } catch (err) {
      if (!err.status) console.error(err); // expected refusals aren't errors
      return json(err.status || 500, {
        error: err.code || 'server_error',
        message: err.publicMessage || 'Something went wrong. Try again in a moment.',
      });
    }
  };
}

// ---------- Storage (D1) ----------

export async function getLicense(db, key) {
  return db.prepare('SELECT * FROM licenses WHERE key = ?').bind(key).first();
}

export async function getLicenseForPurchase(db, originalTransactionId) {
  return db.prepare('SELECT * FROM licenses WHERE original_transaction_id = ?').bind(originalTransactionId).first();
}

export async function isActivated(db, key, machine) {
  const row = await db.prepare('SELECT 1 AS ok FROM activations WHERE key = ? AND machine = ?').bind(key, machine).first();
  return !!row;
}

// ---------- Apple JWS verification ----------

function b64url(input) {
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

/**
 * Verifies a JWS signed by the App Store (StoreKit 2 transactions, App Store Server
 * Notifications): checks the x5c chain leaf → intermediate → Apple Root CA G3 (pinned by
 * fingerprint), certificate dates, and the ES256 signature. Returns the decoded payload.
 * `rootFingerprint` is only overridden by the test suite.
 */
export async function verifyAppleJWS(jws, rootFingerprint = APPLE_ROOT_G3_SHA256) {
  if (typeof jws !== 'string' || jws.split('.').length !== 3) throw fail(400, 'bad_receipt', 'That purchase receipt looks malformed.');
  const [h, p, s] = jws.split('.');
  let header;
  try { header = JSON.parse(b64url(h).toString('utf8')); } catch { header = null; }
  if (!header) throw fail(400, 'bad_receipt', 'That purchase receipt looks malformed.');
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw fail(400, 'bad_receipt', 'That purchase receipt is not from the App Store.');
  }
  let leaf, intermediate, root;
  try {
    [leaf, intermediate, root] = header.x5c.map((c) => new crypto.X509Certificate(Buffer.from(c, 'base64')));
  } catch {
    throw fail(400, 'bad_receipt', 'That purchase receipt is not signed by Apple.');
  }
  const now = Date.now();
  const inDate = (cert) => new Date(cert.validFrom).getTime() <= now && now <= new Date(cert.validTo).getTime();
  const chainOK =
    root.fingerprint256 === rootFingerprint &&
    root.verify(root.publicKey) &&
    intermediate.verify(root.publicKey) &&
    leaf.verify(intermediate.publicKey) &&
    [leaf, intermediate, root].every(inDate);
  if (!chainOK) throw fail(400, 'bad_receipt', 'That purchase receipt is not signed by Apple.');
  // ES256 signature (raw r||s), checked with Web Crypto — the Workers-native path.
  const subtle = globalThis.crypto.subtle;
  const spki = leaf.publicKey.export({ type: 'spki', format: 'der' });
  const verifyKey = await subtle.importKey('spki', spki, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  const signatureOK = await subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, verifyKey, b64url(s), new TextEncoder().encode(`${h}.${p}`));
  if (!signatureOK) throw fail(400, 'bad_receipt', 'That purchase receipt failed verification.');
  return JSON.parse(b64url(p).toString('utf8'));
}

// ---------- Keys & activation tokens ----------

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // no 0/O, 1/I
export function newKey() {
  const bytes = crypto.randomBytes(16);
  let chars = '';
  for (let i = 0; i < 16; i++) chars += ALPHABET[bytes[i] % ALPHABET.length];
  return `VITALS-${chars.slice(0, 4)}-${chars.slice(4, 8)}-${chars.slice(8, 12)}-${chars.slice(12, 16)}`;
}

export function normalizeKey(raw) {
  const key = String(raw || '').trim().toUpperCase().replace(/\s+/g, '');
  if (!/^VITALS-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/.test(key)) {
    throw fail(400, 'bad_key', 'That doesn’t look like a Vitals license key.');
  }
  return key;
}

/**
 * Signed proof that `key` is active on `machine`, checked offline by the app with the
 * embedded public key. Ed25519; private key in the LICENSE_SIGNING_KEY secret (PEM).
 */
export function activationToken(env, key, machine) {
  const pem = env.LICENSE_SIGNING_KEY;
  if (!pem) throw fail(500, 'not_configured', 'The license server is not set up yet.');
  const payload = Buffer.from(JSON.stringify({ key, machine, iat: Math.floor(Date.now() / 1000) }));
  const signature = crypto.sign(null, payload, crypto.createPrivateKey(pem.replace(/\\n/g, '\n')));
  const enc = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${enc(payload)}.${enc(signature)}`;
}

export function cleanMachine(raw) {
  const id = String(raw || '');
  if (!/^[a-f0-9]{64}$/.test(id)) throw fail(400, 'bad_machine', 'This Mac could not be identified.');
  return id;
}
