#!/usr/bin/env bash
# How long does a MirAIe login last? The ha-miraie-ac node logs in once when
# node-red starts and never again, and its 5-minute status refresh
# (nodered_refresh_flow.json) uses that same token - so the token's lifetime
# is how long after a node-red start the refresh keeps working.
#
# Does one fresh login with the node's own stored credentials (decrypted
# inside the node-red container, the same way Node-RED does it) and reports
# the token's lifetime. Never prints the token, the password or the mobile
# number. The node's existing session is not touched: the MirAIe phone app
# logs in alongside the node all the time.
#
#   projects/miraie-ac/check_miraie_token_lifetime.sh
set -uo pipefail

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"

ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "docker exec -i node-red node -" <<'JS'
const fs = require('fs'), crypto = require('crypto');
const secret = JSON.parse(fs.readFileSync('/data/.config.runtime.json'))._credentialSecret;
const blob = JSON.parse(fs.readFileSync('/data/flows_cred.json')).$;
// Node-RED's credential encryption: aes-256-ctr, key sha256(secret), IV is
// the first 32 hex chars, the rest is base64 ciphertext.
const key = crypto.createHash('sha256').update(secret).digest();
const decipher = crypto.createDecipheriv('aes-256-ctr', key, Buffer.from(blob.substring(0, 32), 'hex'));
const creds = JSON.parse(decipher.update(blob.substring(32), 'base64', 'utf8') + decipher.final('utf8'));
const flows = JSON.parse(fs.readFileSync('/data/flows.json'));
const node = flows.find(n => n.type === 'ha-miraie-ac');
const c = creds[node.id];

const body = { password: c.password, clientId: 'PBcMcfG19njNCL8AOgvRzIC8AjQa', scope: `an_${Math.floor(Math.random() * 1e9)}` };
body[node.authType || 'mobile'] = c.mobile;

(async () => {
  const issued = Date.now();
  const r = await fetch('https://auth.miraie.in/simplifi/v1/userManagement/login',
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await r.json();
  console.log(`login HTTP ${r.status}; response fields: ${Object.keys(data).join(', ')}`);
  for (const k of Object.keys(data)) {
    if (/expir|ttl|valid/i.test(k)) console.log(`  ${k} = ${JSON.stringify(data[k])}`);
  }
  const tok = data.accessToken || '';
  const parts = tok.split('.');
  if (parts.length === 3) {
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    const t = k => claims[k] ? new Date(claims[k] * 1000).toISOString() : '-';
    console.log(`  JWT iat ${t('iat')}  exp ${t('exp')}`);
    if (claims.exp && claims.iat) console.log(`  lifetime ${((claims.exp - claims.iat) / 3600).toFixed(1)}h`);
  } else {
    console.log(`  token is not a JWT (${tok.length} chars) - no expiry claim to read`);
  }
  console.log(`  issued at ${new Date(issued).toISOString()}`);
})().catch(e => { console.error(`login failed: ${e.message}`); process.exit(1); });
JS
