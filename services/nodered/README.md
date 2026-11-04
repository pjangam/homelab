# Node-RED

The flow engine behind the MirAIe AC bridge. It **runs on the wol-sender Pi**
(`192.168.1.124:1880`), not on xero - moved there 2026-08-22, so there is no
`node-red` service in `docker-compose.yml` and the old `node-red-data` volume
is left in place on disk only.

Everything about the bridge it carries - the flows, the login, the watchdog,
the refresh flow and the failure modes - is in
[`projects/miraie-ac/README.md`](../../projects/miraie-ac/README.md). This
folder is just the install:

- [`InstallationSteps.md`](InstallationSteps.md) - Node.js via nvm, then
  Node-RED.
- `package.json` / `package-lock.json` - the palette's own dependencies.
- `image*.png` - screenshots the install steps refer to.

The editor requires login (`adminAuth` in `settings.js`, enabled 2026-08-22
once it became reachable over Wi-Fi rather than only from xero); the password
is in Vaultwarden as "Node-RED admin".
