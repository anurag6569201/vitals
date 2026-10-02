#!/usr/bin/env bash
# One-shot Cloudflare setup for vitalsformac.com — run on your Mac from the Vitals folder:
#
#     bash site/scripts/cloudflare-setup.sh
#
# Safe to run again: every step skips what's already done.
# 1. Signs in to Cloudflare (a browser tab opens once — click Allow)
# 2. Creates the Pages project "vitals"
# 3. Creates the license signing key: the private half goes straight into a Cloudflare secret
#    (never printed, never saved), the public half is written into LicenseManager.swift
# 4. Builds and deploys the site + license API
# 5. Attaches vitalsformac.com and www.vitalsformac.com
# 6. Checks the live site and API
set -euo pipefail

PROJECT="vitals"
DOMAIN="vitalsformac.com"
SITE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$SITE/.." && pwd)"
SWIFT="$REPO/Vitals/Licensing/LicenseManager.swift"
cd "$SITE"
W() { npx --yes wrangler "$@"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

step "Installing"
npm install --no-audit --no-fund --silent

step "Signing in to Cloudflare"
if W whoami --json >/dev/null 2>&1; then echo "  already signed in"; else W login; fi

step "Pages project \"$PROJECT\""
if W pages project list 2>/dev/null | grep -qw "$PROJECT"; then
  echo "  already exists"
else
  W pages project create "$PROJECT" --production-branch main
fi

step "License signing key"
if W pages secret list --project-name "$PROJECT" 2>/dev/null | grep -q LICENSE_SIGNING_KEY; then
  echo "  LICENSE_SIGNING_KEY already set — keeping it"
else
  KEYFILE="$(mktemp)"; chmod 600 "$KEYFILE"
  trap 'rm -f "$KEYFILE"' EXIT
  PUB="$(node -e '
    const c = require("crypto"), fs = require("fs");
    const { privateKey, publicKey } = c.generateKeyPairSync("ed25519");
    fs.writeFileSync(process.argv[1], privateKey.export({ format: "pem", type: "pkcs8" }));
    process.stdout.write(publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("base64"));
  ' "$KEYFILE")"
  W pages secret put LICENSE_SIGNING_KEY --project-name "$PROJECT" < "$KEYFILE"
  rm -f "$KEYFILE"
  sed -i '' "s#static let licensePublicKey = \".*\"#static let licensePublicKey = \"$PUB\"#" "$SWIFT"
  echo "  Secret saved in Cloudflare. Public key written into Vitals/Licensing/LicenseManager.swift"
fi

step "Building and deploying"
npm run build
W pages deploy dist --project-name "$PROJECT" --branch main --commit-dirty=true

step "Custom domains"
TOKEN="$(W auth token --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).token||"")}catch{}})')"
api() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }
ACCOUNT="$(api https://api.cloudflare.com/client/v4/accounts | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).result[0].id)}catch{}})')"
if [ -z "$TOKEN" ] || [ -z "$ACCOUNT" ]; then
  echo "  Couldn't add domains automatically. Dashboard › Workers & Pages › $PROJECT › Custom domains › add $DOMAIN and www.$DOMAIN"
else
  for NAME in "$DOMAIN" "www.$DOMAIN"; do
    RESULT="$(api -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/pages/projects/$PROJECT/domains" -d "{\"name\":\"$NAME\"}")"
    if echo "$RESULT" | grep -q '"success":true'; then echo "  added $NAME"
    elif echo "$RESULT" | grep -qi 'already'; then echo "  $NAME already attached"
    else echo "  $NAME: $(echo "$RESULT" | head -c 300)"; echo "  → add it in the dashboard: Workers & Pages › $PROJECT › Custom domains"; fi
  done
fi

step "Checking"
echo "  Preview URL: https://$PROJECT.pages.dev"
for URL in "https://$PROJECT.pages.dev" "https://$DOMAIN"; do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "$URL/" || true)"
  API="$(curl -s -X POST -H 'Content-Type: application/json' -d '{"key":"x","machine":"x"}' "$URL/api/license/validate" || true)"
  echo "  $URL → page $CODE, API: ${API:0:80}"
done
echo
echo "Done. A new domain can take a few minutes to get its certificate — run this script again to re-check."
echo "Still to do in the dashboard: Email › Email Routing › forward support@$DOMAIN to your inbox."
echo "Future updates: cd site && npm run deploy"
