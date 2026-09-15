#!/usr/bin/env python3
"""Move scripts/ into scripts/<project>/, one group at a time (2026-09-15).

For each file in the requested groups:
  1. git mv scripts/NAME -> scripts/GROUP/NAME
  2. rewrite every `scripts/NAME` reference across tracked text files, plus
     HA's gitignored automations/scripts YAML (descriptions name scripts)
  3. in the moved file itself, add one level to every repo-root calculation -
     `$(dirname "$0")/..` and `Path(__file__).parent.parent` now resolve to
     scripts/ instead of the repo root, which fails quietly rather than loudly

It does NOT touch installed systemd unit copies in ~/.config/systemd/user -
those are copies, not symlinks, so they are re-installed by hand and the
service restarted and checked. It prints any remaining `..` in moved files
for review, since not every root calculation has a pattern here.

  scripts/repo-tools/reorganise_scripts.py --dry-run esp32-tools clawlight
  scripts/repo-tools/reorganise_scripts.py esp32-tools clawlight
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent

GROUPS = {
    "aarti-lights": ["aarti_audio.py", "aarti-classify.py", "aarti-render.py",
                     "aarti-sound-lab.py", "wled.sh", "wled-audio-monitor.py"],
    "esp32-tools": ["flash-wled-audioreactive.sh", "watch-usb-serial.sh", "read-esp32-serial.py"],
    "healthcheck": ["publish_healthcheck_mqtt.py", "verify_healthcheck_entities.sh",
                    "test_healthcheck_dashboard_verify.sh", "add_stats_dashboard_tile.py",
                    "healthcheck_last_run.sh"],
    "notify": ["push_ntfy.sh", "send_email.sh", "setup_ntfy_users.sh", "verify_ntfy_topics.sh"],
    "miraie-ac": ["check_miraie_ac_available.sh", "fix_miraie_ac.sh",
                  "diagnose_miraie_ac.sh", "test_miraie_ac_verdict.sh"],
    "spotifyd": ["check_spotifyd_advertising.sh", "wait_for_network.sh", "test_wait_for_network.sh",
                 "test_spotifyd_advertising_check.sh", "test_healthcheck_spotifyd_advertising.sh",
                 "apply_spotifyd_advertising_dashboard_tile.sh"],
    "white-noise": ["white-noise-mqtt.py", "volume-mqtt.py",
                    "skip_white_noise_auto_off_tonight.sh", "apply_toggle_white_noise_automations.sh"],
    "pi-buttons": ["white-noise-buttons-mqtt.py", "scene-buttons-mqtt.py", "deploy_button_bridges_pi.sh",
                   "deploy_white_noise_buttons_pi.sh", "apply_white_noise_button_automations.sh",
                   "apply_scene_button_automations.sh", "capture_white_noise_button_presses.sh",
                   "diagnose_white_noise_buttons.sh", "setup_toggle_button_env.sh"],
    "wol-sender": ["fix_wol_sender_overlay_hang.sh", "persist_wol_setting.sh", "set_wol_sender_static_ip.sh",
                   "setup_wol_sender_nopasswd_sudo.sh", "update_wol_sender.sh", "wol_listener.py",
                   "start_nodered_on_pi.sh", "watchdog_nodered_pi.sh"],
    "clawlight": ["clawlight-led.py", "deploy_clawlight_led_pi.sh", "test_clawlight_focus_e2e.sh",
                  "test_clawlight_focus.py", "test_clawlight_ignore.sh", "test_clawlight_notify.py",
                  "verify_clawlight_notify.sh", "watch_clawlight_pushes.sh"],
    "network": ["diagnose_dns_paths.sh", "diagnose_macbook_dns.sh", "fix_macbook_dns.sh",
                "mac-dns-recorder.sh", "setup-mac-dns-recorder.sh", "test_mac_dns_recorder.sh",
                "watch-peer-dns.sh", "tailscale-dns-probe.sh", "fix_tailscale_resolvconf.sh",
                "render_ts_serve_config.sh"],
    "certs-backup": ["make_test_cert.py", "test_cert_expiry_check.sh", "test_backup_restart_guard.sh"],
    "dev-shell": ["setup-tmux-shell.sh", "test_setup_tmux_shell.sh", "qwen_delegate_repl.py"],
    "repo-tools": ["find_script_references.sh", "convert_apple_to_bitwarden.py"],
}

# Gitignored, but its automation descriptions name scripts by path.
EXTRA_FILES = ["HOMEASSISTANT_CONFIG/automations.yaml", "HOMEASSISTANT_CONFIG/scripts.yaml"]

# One more level on repo-root calculations inside a moved file. Each pattern
# is anchored on the `..` that currently means "repo root from scripts/".
ROOT_BUMPS = [
    (re.compile(r'(dirname "\$0"\)/\.\.)(?=[/"\) ])'), r"\1/.."),
    (re.compile(r'(dirname "\$\(readlink -f "\$0"\)"\)/\.\.)(?=[/"\) ])'), r"\1/.."),
    (re.compile(r'(dirname -- "\$\{BASH_SOURCE\[0\]\}"\)/\.\.)(?=[/"\) ])'), r"\1/.."),
    (re.compile(r"Path\(__file__\)\.resolve\(\)\.parent\.parent(?!\.parent)"),
     "Path(__file__).resolve().parent.parent.parent"),
    (re.compile(r'(os\.path\.dirname\(os\.path\.abspath\(__file__\)\), "\.\.")(?!, "\.\.")'), r'\1, ".."'),
]


def tracked_text_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=REPO, capture_output=True, check=True).stdout
    for rel in out.decode().split("\0"):
        if not rel or rel.startswith("data/"):
            continue
        p = REPO / rel
        if p.is_file() and not p.is_symlink():
            yield p
    for rel in EXTRA_FILES:
        if (REPO / rel).is_file():
            yield REPO / rel


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    groups = [a for a in args if a != "--dry-run"]
    unknown = [g for g in groups if g not in GROUPS]
    if not groups or unknown:
        sys.exit(f"usage: {sys.argv[0]} [--dry-run] GROUP...; unknown: {unknown}; groups: {', '.join(GROUPS)}")

    moves = [(name, g) for g in groups for name in GROUPS[g]]
    for name, g in moves:
        if not (REPO / "scripts" / name).is_file():
            sys.exit(f"missing scripts/{name} (already moved?) - nothing changed")

    # Rewrite references first (content only), then move - so a failure part
    # way leaves files in place rather than moved-but-unreferenced.
    ref_res = [(re.compile(r"(?<![\w-])scripts/" + re.escape(name) + r"(?![\w-])"),
                f"scripts/{g}/{name}") for name, g in moves]
    changed = {}
    for p in tracked_text_files():
        try:
            text = p.read_text()
        except (UnicodeDecodeError, PermissionError):
            continue
        new = text
        for rx, repl in ref_res:
            new = rx.sub(repl, new)
        if new != text:
            changed[p] = new

    for p, new in changed.items():
        print(f"refs  {p.relative_to(REPO)}")
        if not dry:
            try:
                p.write_text(new)
            except PermissionError:
                # HA's YAML is root-owned (written by the container). Only its
                # automation descriptions name scripts, so warn rather than
                # abort half-way - the first run died here after rewriting
                # every other reference but before moving any file.
                print(f"SKIPPED (not writable) {p.relative_to(REPO)} - update by hand if wanted")

    for name, g in moves:
        src, dst = f"scripts/{name}", f"scripts/{g}/{name}"
        print(f"move  {src} -> {dst}")
        if dry:
            continue
        (REPO / "scripts" / g).mkdir(exist_ok=True)
        subprocess.run(["git", "mv", src, dst], cwd=REPO, check=True)
        f = REPO / dst
        text = f.read_text()
        new = text
        for rx, repl in ROOT_BUMPS:
            new = rx.sub(repl, new)
        if new != text:
            f.write_text(new)
            print(f"root  {dst}: repo-root calculation deepened")
        for i, line in enumerate(new.splitlines(), 1):
            if ".." in line and not line.lstrip().startswith("#"):
                print(f"REVIEW {dst}:{i}: {line.strip()[:110]}")


if __name__ == "__main__":
    main()
