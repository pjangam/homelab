# Git hooks: pre-commit PII/public-IP/PCI scan, reproducible hook install
**Status:** Done

**Why:** gitleaks (existing `pre-push` hook) only catches credential-shaped secrets - it wouldn't catch a public IP, a Tailscale hostname, a phone number, or a card number accidentally committed. Separately, that pre-push hook only ever lived in `.git/hooks/` (untracked, per-clone) with no install step anywhere - it would not have survived a fresh `git clone`.
**Outcome:** shipped 2026-08-23 - both hooks tracked in `.githooks/` with `git config core.hooksPath .githooks` (set automatically by `new_machine_setup.sh`), plus a new `.githooks/pre-commit` leak scan. Documented in `Readme.md` under "Git hooks (leak scanning)".

#### What the pre-commit hook does
Scans staged added lines for public IPv4s (private/loopback ranges and well-known DNS resolvers like `8.8.8.8`/`1.1.1.1` allowlisted), Tailscale `*.ts.net` hostnames (the doc placeholder `tailXXXXX.ts.net` allowlisted), emails outside a small allowlist, phone numbers, and card numbers (Luhn-checked to cut noise on generic digit strings) - blocks the commit with `git commit --no-verify` as the documented bypass for a confirmed false positive.

#### Verification
Dry-run tested against all currently-tracked repo content first to calibrate the allowlist before enabling; live-tested against both a deliberately planted leak (all four categories correctly caught) and a legitimate change (correctly passed clean).
