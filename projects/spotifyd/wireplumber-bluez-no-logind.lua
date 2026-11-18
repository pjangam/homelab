-- WirePlumber 0.4 on xero: keep Bluetooth audio up with nobody logged in.
-- By default (with-logind) WirePlumber only runs its Bluetooth monitor while
-- the user's login session is active, so the Apollo One speaker dropped every
-- time an ssh session closed and came back at the next ssh login (found
-- 2026-11-18: endpoints unregistered at a logout, registered at a login).
-- Installed by install_wireplumber_bt.sh to
-- ~/.config/wireplumber/bluetooth.lua.d/ (runs after the stock 50-*.lua).
bluez_monitor.properties["with-logind"] = false

-- Never suspend the Bluetooth output. PipeWire suspends an idle sink after
-- 5s; the A2DP stream and the speaker's amp then take ~1-2s to wake, which
-- swallowed short spoken replies ("Turned on the switch" came out as a
-- blip, 2026-11-18).
table.insert(bluez_monitor.rules, {
  matches = { { { "node.name", "matches", "bluez_output.*" } } },
  apply_properties = { ["session.suspend-timeout-seconds"] = 0 },
})
