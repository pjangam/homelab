-- WirePlumber 0.4 on xero: keep Bluetooth audio up with nobody logged in.
-- By default (with-logind) WirePlumber only runs its Bluetooth monitor while
-- the user's login session is active, so the Apollo One speaker dropped every
-- time an ssh session closed and came back at the next ssh login (found
-- 2026-11-18: endpoints unregistered at a logout, registered at a login).
-- Installed by install_wireplumber_bt.sh to
-- ~/.config/wireplumber/bluetooth.lua.d/ (runs after the stock 50-*.lua).
bluez_monitor.properties["with-logind"] = false
