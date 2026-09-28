#!/usr/bin/env bash
# Picks which clawlight server URL to report to, and is sourced by both
# set-status.sh and focus-agent.sh so the two can never disagree about it.
#
# WHY THIS EXISTS
#
# Reporting needs no Tailscale: server.py binds 0.0.0.0:8126, so xero answers
# on the LAN directly and the tailnet URL is only Caddy's TLS wrapper in front
# of it. That matters because Tailscale on the MacBook keeps stopping (see
# PROJECTS.md, "the M2 cannot resolve xero.<tailnet>"), and when it does every
# hook on that machine silently reports nowhere - set-status.sh swallows
# network errors by design, so the light just quietly stops mentioning the Mac.
#
# But a bare LAN IP in the hooks is only correct AT HOME. On a cafe or office
# network 192.168.1.123 is somebody else's machine, and the report payload
# carries the session id, the project path and the tmux session name. Worse, if
# nothing holds that address the POST burns the full `curl -m 3` - ten hooks a
# turn, so every turn drags.
#
# So: prefer the LAN when we can prove we are on the home LAN, and fall back to
# the tailnet URL when we cannot. The proof is the default gateway's MAC
# address, which is
#   - local and instant: two cheap commands, no round trip, nothing to leak;
#   - independent of DNS, which is precisely what keeps breaking here (gating
#     on a hostname would reintroduce the same silent stop it is escaping);
#   - actually ours, unlike the subnet - 192.168.1.0/24 is the most common home
#     range there is, so an IP or netmask check would happily post to a cafe
#     router's .123.
#
# Anything unexpected - no gateway, an empty ARP cache, a MAC that does not
# match - falls back rather than guessing. Failing closed here costs at most
# one dropped report (the next hook event re-sends the state), while failing
# open sends your project paths to a stranger.
#
# Environment:
#   CLAWLIGHT_SERVER_URL        - the fallback, and the only variable needed on
#                                 a machine with no LAN shortcut. Default
#                                 http://localhost:8126, which is right on xero
#                                 (the server runs there) and wrong everywhere
#                                 else, hence the tailnet URL on other hosts.
#   CLAWLIGHT_LAN_URL           - used INSTEAD of the above while on the home
#                                 LAN, e.g. http://192.168.1.123:8126
#   CLAWLIGHT_HOME_GATEWAY_MAC  - the home router's MAC, as printed by
#                                 `arp -n <gateway>` / `ip neigh`. Both of
#                                 these must be set for the shortcut to engage;
#                                 with neither, behaviour is exactly as before.

# Lower-case and zero-pad to aa:bb:cc:dd:ee:ff, because the two sides are
# spelled differently: macOS `arp` prints an octet under 0x10 as one digit
# ("f8:c4:f3:e0:82:3f" but "8:0:20:..."), while `ip neigh` and anything you
# copy off a router label pad it. Comparing the raw strings would miss.
clawlight_norm_mac() {
  printf '%s' "${1:-}" | tr 'A-F' 'a-f' | awk -F: '
    NF == 6 {
      out = ""
      for (i = 1; i <= 6; i++) {
        o = $i
        if (length(o) == 1) o = "0" o
        out = out (i > 1 ? ":" : "") o
      }
      print out
    }'
}

# The MAC of whatever is currently our default gateway, normalised, or empty.
# Deliberately reads the ARP cache rather than probing: the gateway is in it
# on any network we are actually using, and a probe would cost latency on the
# hook path for no gain.
clawlight_gateway_mac() {
  local gw="" mac=""
  local mac_re='([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}'

  if command -v ip >/dev/null 2>&1; then
    gw="$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')"
    [ -n "$gw" ] && mac="$(ip neigh show "$gw" 2>/dev/null | grep -oE "$mac_re" | head -1)"
  fi
  if [ -z "$mac" ] && command -v route >/dev/null 2>&1; then
    [ -n "$gw" ] || gw="$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')"
    [ -n "$gw" ] && mac="$(arp -n "$gw" 2>/dev/null | grep -oE "$mac_re" | head -1)"
  fi

  clawlight_norm_mac "$mac"
}

# True only when both LAN variables are set AND the gateway proves we are home.
clawlight_on_home_lan() {
  [ -n "${CLAWLIGHT_LAN_URL:-}" ] || return 1
  [ -n "${CLAWLIGHT_HOME_GATEWAY_MAC:-}" ] || return 1

  local want seen
  want="$(clawlight_norm_mac "$CLAWLIGHT_HOME_GATEWAY_MAC")"
  [ -n "$want" ] || return 1          # unparseable config: fall back, don't guess
  seen="$(clawlight_gateway_mac)"
  [ -n "$seen" ] || return 1          # no gateway / cold ARP cache

  [ "$seen" = "$want" ]
}

# The URL to use right now. Call it per report (set-status.sh) or per reconnect
# (focus-agent.sh) rather than once at start-up: the answer changes when the
# laptop is carried out of the house, and a long-lived agent that cached it
# would keep aiming at a LAN address on a foreign network.
clawlight_server_url() {
  if clawlight_on_home_lan; then
    printf '%s' "$CLAWLIGHT_LAN_URL"
  else
    printf '%s' "${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
  fi
}
