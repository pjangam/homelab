#!/usr/bin/env bash
# Build the local image "indicconformer" (Dockerfile.indicconformer): Immich's
# ML image (onnxruntime, numpy, huggingface_hub) + the onnx-asr wheel. Used by
# the stt-fallback container (docker-compose.yml) and bench_indicconformer.sh.
# Downloads the wheel itself because pip from xero to pypi.org stalls
# (2026-11-15): resumes until complete, then checks the sha256.
#   projects/voice-assistant/build_indicconformer_image.sh
set -euo pipefail
cd "$(dirname "$0")"
ctx=$(mktemp -d); trap 'rm -rf "$ctx"' EXIT
whl="$ctx/onnx_asr-0.12.0-py3-none-any.whl"
for _ in $(seq 1 15); do
  curl -s -C - -m 60 -o "$whl" https://files.pythonhosted.org/packages/6a/60/2fa469a2ee674c35ab48821a1039762ae7b9d0b88188ac1012e779477f76/onnx_asr-0.12.0-py3-none-any.whl || true
  [ "$(stat -c%s "$whl" 2>/dev/null)" = 3980006 ] && break
done
echo "5e7ceca454609819ea7833f61e2302e0c8f6ece4f8a78b66c5daba53cb51de4a  $whl" | sha256sum -c --quiet
docker build -t indicconformer -f Dockerfile.indicconformer "$ctx"
