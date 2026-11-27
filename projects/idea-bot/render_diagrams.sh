#!/usr/bin/env bash
# Render the PlantUML diagrams to .svg and .png with PlantUML in Docker (xero
# has no Java). GitHub does not render .puml, so the README embeds the SVGs -
# commit the outputs after an edit.
#   projects/idea-bot/render_diagrams.sh
set -euo pipefail
cd "$(dirname "$0")"
files=(architecture.puml sequence_new_idea.puml message_routing.puml)
for fmt in svg png; do
  docker run --rm -u "$(id -u):$(id -g)" -e JAVA_TOOL_OPTIONS=-Duser.home=/tmp -v "$PWD:/data" -w /data \
    plantuml/plantuml:1.2024.7 -t"$fmt" "${files[@]}" 2>&1 | grep -v JAVA_TOOL_OPTIONS || true
done
ls -la ./*.svg ./*.png
