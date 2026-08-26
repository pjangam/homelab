# wol-sender Pi GPIO pinout

Standard 40-pin header layout (Raspberry Pi 3B, same physical layout as
2/4/Zero/5) - kept here as a reference point so this doesn't need
re-Googling every time a new button/sensor gets wired in.

## Currently in use

| Pin(s) | GPIO | Used for |
|---|---|---|
| 11 + 9 | GPIO17 + GND | Toggle switch → white noise (`scripts/toggle-button-mqtt.py`) |
| 13 + 14 | GPIO27 + GND | Sleep button (`scripts/scene-buttons-mqtt.py`) |
| 15 + 14 | GPIO22 + GND | Awake button (`scripts/scene-buttons-mqtt.py`) |
| 2 or 4 (5V) + a GND | - | Cooling fan (always-on load, exact pin not recorded) |

All three buttons wire directly between a GPIO pin and GND - no resistor
needed, each script sets the pin's internal pull-up in software
(`gpiozero.Button(pin, pull_up=True)`).

## Full 40-pin layout

```
            3.3V  [ 1] [ 2]  5V
   GPIO2 (SDA)    [ 3] [ 4]  5V
   GPIO3 (SCL)    [ 5] [ 6]  GND
         GPIO4    [ 7] [ 8]  GPIO14 (TXD)
     >>>  GND  <<<[ 9] [10]  GPIO15 (RXD)
  >>> GPIO17 <<<   [11] [12]  GPIO18
  >>> GPIO27 <<<   [13] [14]  >>>  GND  <<<
  >>> GPIO22 <<<   [15] [16]  GPIO23
            3.3V  [17] [18]  GPIO24
  GPIO10 (MOSI)    [19] [20]  GND
   GPIO9 (MISO)    [21] [22]  GPIO25
  GPIO11 (SCLK)    [23] [24]  GPIO8 (CE0)
           GND    [25] [26]  GPIO7 (CE1)
   ID_SD (rsvd)    [27] [28]  ID_SC (rsvd)
         GPIO5    [29] [30]  GND
         GPIO6    [31] [32]  GPIO12
        GPIO13    [33] [34]  GND
        GPIO19    [35] [36]  GPIO16
        GPIO26    [37] [38]  GPIO20
           GND    [39] [40]  GPIO21
```

Pins 27/28 (`ID_SD`/`ID_SC`) are reserved for HAT identification EEPROMs -
avoid using them for general I/O even though they're electrically usable.

## Next free pins for a future button

GPIO23 (pin 16), GPIO24 (pin 18), GPIO5 (pin 29), GPIO6 (pin 31) are all
free, adjacent to an existing GND pin, and not reserved for SPI/I2C/UART -
good candidates for the next physical button without reshuffling anything
already wired.
