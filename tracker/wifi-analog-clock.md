# WiFi-synced analog clock (ESP32 retrofit of a quartz movement)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** open a spare movement and confirm the coil can be freed from its quartz chip and pulsed by hand - that one bench test decides the project

**Why:** a wall clock that is simply always right, with no twice-a-year fiddling and no drift to correct by hand.
**State:** idea only. **Feasibility: settled - it works, and it is a well-trodden build.** Several independent projects do exactly this ([ESPCLOCK](https://hackaday.io/project/16742-espclock), [jim11662418/ESP8266-WiFi-Analog-Clock](https://github.com/jim11662418/ESP8266-WiFi-Analog-Clock), [randseq.org's write-up](https://www.randseq.org/2016/10/hacking-analog-clock-to-sync-with-ntp_29.html)).

#### How it works
It is simpler than it sounds. A cheap quartz movement drives its hands with a [Lavet-type stepping motor](https://en.wikipedia.org/wiki/Lavet-type_stepping_motor): one coil that gets an alternating-polarity pulse once a second. The retrofit is to cut the coil off the movement's own quartz chip and solder its two leads to an H-bridge driven by two ESP32 pins. Every pulse advances the second hand one step, so "set the clock" means "send the right number of pulses".

#### The two real problems
- **The board never knows where the hands are.** It only sends pulses; nothing reads the dial back. Two ways out: keep the position in flash and never lose power, or **home the hands** - a magnet on a hand past a reed switch or hall sensor, so on every boot it steps to 12:00 and then fast-forwards to NTP time. With power cuts as frequent as they are here, the homing sensor is the version worth building; storing position in flash alone means a clock that is confidently wrong after every outage.
- **Catching up is slow, and only forwards.** A Lavet motor cannot run backwards, and only steps reliably up to some tens of pulses a second. At ~20 steps/s, six hours of catching up takes about 18 minutes of whirring. Going back an hour means either 11 hours of fast-forward or stopping the hands and waiting for the time to come round. Fine for a clock that is right afterwards, but it is not instant.

#### Where it gets its time
`pool.ntp.org` needs the ISP; pointing it at xero instead makes it work during an internet outage, but then it needs xero. Either way it needs the router. xero does not serve NTP today (Pi-hole is DNS only), so the local-time-source version means running chrony there - small, and useful to more than this project.

**In India there is no radio-clock shortcut (checked 2026-09-18).** The cheap US "atomic" clocks are not WiFi at all - they receive [WWVB](https://en.wikipedia.org/wiki/WWVB), a 60kHz time signal from Colorado, which is why a self-setting clock there costs $20 and needs no network or app. That signal does not reach India, and India has no equivalent consumer broadcast: [CSIR-NPL](https://www.nplindia.in/index.php/science-technology/indian-standard-time-metrology-division/) disseminates IST as `ATA` on 5/10/15 MHz HF and over INSAT, neither of which any consumer clock receives. So a WWVB clock bought or imported here is just a quartz clock that never syncs. **WiFi is the only self-setting route on this side of the world** - or GPS, which is worth knowing about: a ~₹400 GPS module gives correct time with no internet and no WiFi, as long as the clock hangs somewhere with a view of the sky or a window.

#### What it actually buys
India has no DST, and a quartz movement drifts ~15s/month, so the payoff is not really accuracy. It is that the clock fixes itself after a battery change or a power cut. Note the trap: a plain quartz clock keeps ticking on its own AA through an outage, so a mains-powered retrofit **without** the homing sensor is worse than the clock it replaced.

#### Readymade options (checked 2026-09-18)
**India availability of the readymade ones: nothing confirmed.** Amazon.in and Flipkart carry plain quartz wall clocks (₹200-650) and digital WiFi clocks, but no self-setting analog WiFi clock turned up. The WiFi analog clocks that do exist (Primex, American Time, Innovation Wireless) are US commercial fittings sold B2B. So realistically the choice is the ESP32 retrofit or importing a CH899-class movement.

Readymade options do exist, in three shapes:
- **A whole WiFi analog clock.** [eYotto's 12" WiFi time-sync clock](https://www.amazon.com/eYotto-12-Inch-Non-Ticking-Operated-Automatic/dp/B0D3TNXV83) and the Bulova Connect C5000 (~$60) are the consumer ones; Primex and [TimeMachines](https://timemachinescorp.com/product/displays/) sell PoE/WiFi clocks for offices and schools. All US-market or commercial fittings. [Amazon.in lists "wifi clock"](https://www.amazon.in/wifi-clock/s?k=wifi+clock) but mostly digital ones - whether an analog WiFi clock is actually buyable here is unchecked, and worth five minutes before building anything.
- **A readymade WiFi clock *movement*,** which is the interesting one: it drops into an existing clock body exactly like the DIY retrofit, but with no surgery. [Heng-Rong's CH899 14.5mm WiFi movement](https://www.hr-clockparts.com/clock-movement/wifi-clock-movement.html) networks once a day and comes with hands. Chinese OEM/wholesale, so the question is whether one or two can be bought at all, and at what landed cost.
- **The catch with all of them:** a consumer WiFi clock almost certainly phones a vendor cloud and wants an app, which is the Tinxy problem again - it breaks in an ISP outage and cannot be pointed at xero. None of them can be a local-only device the way the retrofit can. A readymade movement bought for ~₹1000-2000 landed is still the lowest-effort answer if self-correcting is all that is wanted; the ESP32 retrofit is the answer if it should be local-only and answer to this homelab.

#### Parts
```parts
qty | item | est | note
2 | Quartz clock movement | 300-600 | local - two on purpose: the first is for practising the coil surgery. A clock already owned can be the second
1 | ESP32 dev board with USB | 400-600 | local - skip if the aarti lights board is freed after the festival
1 | Reed switch + small magnet | 50-100 | local - the homing sensor; a hall sensor works too
1 | Resistors (100R-1k assortment) | 20 | local - the coil is rated ~1.5V and gets driven from 3.3V
1 | DRV8833 or L293D H-bridge | 0-200 | local, and probably not needed - the coil can sit directly between two GPIO pins through a resistor, which is an H-bridge in software. Buy only if that reads too weak
```

**Cost: about ₹800-1300 all in, or ₹400-700 reusing the aarti board** - and no shop trip is gated on delivery, since every line is loose local stock. A clock body to put it in is on top of that if one is not already owned (₹200-650 for a plain wall clock).

#### Effort
**Roughly 8-12 hours, over two or three evenings, plus a few days of watching it.** Four phases, and the cheap ones come first on purpose:
- **Free the coil and pulse it by hand from the ESP32 - 1-2h.** This is the go/no-go test and the one where a movement gets destroyed, hence buying two.
- **Firmware - 2-4h,** less if an existing sketch is adapted rather than written: NTP, the one-pulse-per-second loop, fast-forward, and the position kept in flash.
- **Homing sensor - 2-3h,** and this is where it overruns. Aligning a magnet and reed switch against a moving hand is fiddly mechanical work, the same class of problem the fiber-optic option in the UPS LED project was rejected for.
- **Install, tidy, mount - 1-2h.**

Then it verifies itself slowly: leave it a few days against a known-good clock, and test an outage by pulling power and confirming it re-homes and catches up on its own.

#### Log
- 2026-09-18: noted and researched; feasibility settled, radio-clock and readymade options checked.
