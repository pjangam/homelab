# clawlight on the Pi (physical LED) + the clawlight tests

The hardware half of clawlight and its test suite. The server, the web light
and the Mac focus agent are in the top-level
[`clawlight/`](../../clawlight/README.md); this folder is still under
`scripts/` because the whole wol-Pi and Mac group moves together later - see
[`scripts/README.md`](../README.md).

| | |
|---|---|
| `clawlight-led.py` | drives a red/green LED on the Pi's GPIO from clawlight state - same source of truth as the web light |
| `deploy_clawlight_led_pi.sh` | run **on xero**: installs the script, its MQTT credentials and the unit on the Pi. Credentials are generated from xero's `.env.mqtt`, so the Pi cannot drift from the broker's actual password |
| `tune_led.sh` | pick an LED setting by eye - stops the service, steps through candidate values, prints each as a ready-made line to paste back into `clawlight-led.py`, restarts |
| `show_led_states.sh` | what each state looks like |
| `watch_clawlight_pushes.sh`, `verify_clawlight_notify.sh` | is the ntfy push path working? |
| `test_clawlight_*.py` / `*.sh` | the suite: focus, notify, phone jump, shells, server URL, ignore rules, LED |

The unit itself is `systemd/wol-sender/clawlight-led.service`. Installed units
are copies, not symlinks - a repo edit changes nothing until it is re-deployed.
