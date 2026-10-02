#!/usr/bin/env node
// Generates the Ed25519 key pair for Vitals license activation tokens. Run once:
//   node scripts/license-keys.js
// • LICENSE_SIGNING_KEY (private) → `npx wrangler pages secret put LICENSE_SIGNING_KEY` (Cloudflare). Never commit it.
// • Public key → Vitals/Licensing/LicenseManager.swift › LicenseConfig.licensePublicKey
const crypto = require('crypto');
const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
const pem = privateKey.export({ format: 'pem', type: 'pkcs8' }).toString();
const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
console.log('LICENSE_SIGNING_KEY (paste into: npx wrangler pages secret put LICENSE_SIGNING_KEY, keep secret):\n');
console.log(pem.trim().replace(/\n/g, '\\n'));
console.log('\nlicensePublicKey (paste into LicenseConfig):\n');
console.log(raw);
