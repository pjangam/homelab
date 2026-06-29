#!/bin/bash
set -e

echo "=== Current font ==="
showconsolefont --info

# Try fonts largest to smallest, use first one that works
FONTS="ter-powerline-v24b ter-powerline-v22b ter-powerline-v20b ter-powerline-v18b ter-powerline-v16b"
CHOSEN=""

for FONT in $FONTS; do
    FILE="/usr/share/consolefonts/${FONT}.psf.gz"
    if [ ! -f "$FILE" ]; then
        echo "Downloading ${FONT}..."
        curl -sL "https://raw.githubusercontent.com/powerline/fonts/master/Terminus/PSF/${FONT}.psf.gz" \
            -o /tmp/${FONT}.psf.gz
        sudo cp /tmp/${FONT}.psf.gz /usr/share/consolefonts/
    fi
    if sudo setfont "$FILE" 2>/dev/null; then
        CHOSEN="$FONT"
        echo "Loaded: $FONT"
        break
    else
        echo "Skipped (unsupported): $FONT"
    fi
done

if [ -z "$CHOSEN" ]; then
    echo "ERROR: No compatible font found"
    exit 1
fi

echo "=== Font after change ==="
showconsolefont --info

# Persist via console-setup
grep -q '^FONT=' /etc/default/console-setup \
    && sudo sed -i "s/^FONT=.*/FONT=\"${CHOSEN}.psf.gz\"/" /etc/default/console-setup \
    || echo "FONT=\"${CHOSEN}.psf.gz\"" | sudo tee -a /etc/default/console-setup

echo "=== Done. Saved ${CHOSEN} to /etc/default/console-setup ==="
