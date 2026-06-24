
  1. Xorg was hung since Jun 19 — it got stuck during modesetting/i915 initialization and never completed startup. SDDM was waiting for Xorg to be ready, so the greeter and autologin
  never launched. Screen stayed black.
  2. Restarting SDDM wasn't enough — when you restarted SDDM, it killed and respawned Xorg, but the kernel's DRM/i915 GPU state was already in a bad state from the original hang. Only a
  full reboot cleared the GPU state so Xorg could initialize cleanly.

  This is a known class of issue with the N5105 (Jasper Lake) — same family of problems as the C-state freeze fix you already have in GRUB. The autologin config (User=pramod) we added is
  also now active, so future boots will go straight to the desktop.

  If this happens again without a reboot in between, go straight to sudo reboot — SDDM restarts alone can't recover from a hung i915 DRM state.

