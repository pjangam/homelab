#!/usr/bin/env bash
# Drives cron/check_certs.sh against synthetic certs with known expiry dates.
#
# This tests the REAL script (via its cert-directory argument) rather than a
# copy of its logic - a mirrored test would happily pass while the thing that
# actually runs is broken, which is the same class of mistake that let cert
# renewal fail silently for three months.
#
# Run: ./scripts/test_cert_expiry_check.sh
set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
failures=0

make_cert() {  # $1 = name, $2 = days from now until expiry (may be negative)
  local name="$1" days="$2"
  python3 scripts/make_test_cert.py "$TMP/$name.crt" "$TMP/$name.key" "$days" || {
    echo "FIXTURE ERROR: could not create $name cert"; exit 2; }
  # Guard against false passes: an absent or unreadable fixture would make the
  # checker silent, and a test asserting silence would then "pass" while
  # testing nothing. This is exactly how the first version of this test lied.
  openssl x509 -in "$TMP/$name.crt" -noout >/dev/null 2>&1 || {
    echo "FIXTURE ERROR: $name cert is not readable by openssl"; exit 2; }
}

check() {  # $1 = description, $2 = expected substring ("" = expect no output)
  local desc="$1" want="$2" out
  out=$(./cron/check_certs.sh "$TMP" 2>&1)
  if [ -z "$want" ]; then
    if [ -z "$out" ]; then echo "PASS  $desc"; else
      echo "FAIL  $desc"; echo "      expected silence, got: $out"; failures=$((failures+1)); fi
  else
    if echo "$out" | grep -qF "$want"; then echo "PASS  $desc"; else
      echo "FAIL  $desc"; echo "      expected to contain '$want', got: ${out:-<silence>}"; failures=$((failures+1)); fi
  fi
  rm -f "$TMP"/*.crt "$TMP"/*.key
}

make_cert healthy 89   ; check "89d cert is silent"                    ""
make_cert fresh   30   ; check "30d cert is silent (just renewed)"     ""
make_cert edge    22   ; check "22d cert is silent (above threshold)"  ""
make_cert warn    20   ; check "20d cert warns"                        "expires in 20d"
make_cert soon    5    ; check "5d cert warns"                         "expires in 5d"
make_cert gone    -3   ; check "expired cert reports as EXPIRED"       "EXPIRED"

# A cert directory that doesn't exist must be silent, not an error - other
# machines running healthcheck.sh have no certs/ at all.
out=$(./cron/check_certs.sh "$TMP/nonexistent" 2>&1)
if [ -z "$out" ]; then echo "PASS  missing cert dir is silent"; else
  echo "FAIL  missing cert dir should be silent, got: $out"; failures=$((failures+1)); fi

# Malformed cert must be reported, not silently skipped.
echo "not a certificate" > "$TMP/broken.crt"
check "malformed cert is reported" "unreadable or malformed"

echo; echo "FAILURES: $failures"
exit $((failures > 0))
