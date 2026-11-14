#!/usr/bin/env bash
# Render the PlantUML diagrams (architecture.puml, sequence_play_song.puml, intent_routing.puml)
# to .svg and .png with PlantUML in Docker (xero has no Java). GitHub does not
# render .puml, so the README embeds the SVGs - commit the outputs after an edit.
#   projects/voice-assistant/render_architecture.sh
set -euo pipefail
cd "$(dirname "$0")"
for fmt in svg png; do
  docker run --rm -u "$(id -u):$(id -g)" -e JAVA_TOOL_OPTIONS=-Duser.home=/tmp -v "$PWD:/data" -w /data \
    plantuml/plantuml:1.2024.7 -t"$fmt" architecture.puml sequence_play_song.puml intent_routing.puml 2>&1 | grep -v JAVA_TOOL_OPTIONS || true
done
ls -la architecture.svg architecture.png sequence_play_song.svg sequence_play_song.png intent_routing.svg intent_routing.png
