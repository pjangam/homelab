#!/usr/bin/env bash
# Dry test of move_thumbs_to_boot.sh with fake zfs, compose and docker in a
# temporary folder. Touches nothing real.  Run: services/immich/test_move_thumbs.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
fails=0

ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

reset() {
  rm -rf "${root:?}"/*
  mkdir -p "$root/bin" "$root/pool/thumbs/user/ab" "$root/boot"
  echo one > "$root/pool/thumbs/user/ab/a.webp"
  echo twotwo > "$root/pool/thumbs/user/ab/b.webp"
  echo > "$root/pool/thumbs/.immich"
  printf 'SECRET=keepme\nUPLOAD_LOCATION=/x' > "$root/env"
  touch "$root/dataset-exists"

  cat > "$root/bin/zfs" <<EOF
#!/usr/bin/env bash
case \$1 in
  list) [ -e "$root/dataset-exists" ] ;;
  destroy) [ ! -e "$root/immich-running" ] || { echo busy >&2; exit 1; }; rm "$root/dataset-exists" ;;
esac
EOF
  cat > "$root/bin/compose" <<EOF
#!/usr/bin/env bash
case \$1 in
  stop) rm -f "$root/immich-running" ;;
  up) touch "$root/immich-running"; grep -q IMMICH_THUMBS "$root/env" && echo boot > "$root/mounted" || echo pool > "$root/mounted" ;;
esac
EOF
  cat > "$root/bin/docker" <<EOF
#!/usr/bin/env bash
[ -e "$root/immich-running" ] && [ "\$(cat "$root/mounted" 2>/dev/null)" = boot ] && [ -f "$root/boot/thumbs/.on-boot-disk" ]
EOF
  chmod +x "$root"/bin/*
}

run() {
  DRY_TEST=1 WAIT_S=4 MIN_FREE_GB=${FREE:-0} DEST="$root/boot/thumbs" POOL_DIR="$root/pool" \
    DATASET=fake/thumbs ENV_FILE="$root/env" ZFS="$root/bin/zfs" COMPOSE="$root/bin/compose" \
    DOCKER="$root/bin/docker" "$here/move_thumbs_to_boot.sh" "$@" >"$root/out" 2>&1
}

reset; mkdir "$root/pool/thumbs.old"
run run; ok "refuses while thumbs.old exists" "[ $? != 0 ] && [ ! -e $root/boot/thumbs ]"

reset; FREE=999999 run run
ok "refuses when the boot disk would fill" "[ $? != 0 ] && [ ! -e $root/boot/thumbs ] && ! grep -q IMMICH_THUMBS $root/env"

reset; run run; rc=$?
ok "run succeeds" "[ $rc = 0 ]"
ok "files copied, including the dot file" "cmp -s $root/pool/thumbs/user/ab/b.webp $root/boot/thumbs/user/ab/b.webp && [ -e $root/boot/thumbs/.immich ]"
ok ".env gains the line on its own line" "grep -qx 'IMMICH_THUMBS_LOCATION=$root/boot/thumbs' $root/env && grep -qx 'UPLOAD_LOCATION=/x' $root/env"
ok "Immich running on the new folder" "[ -e $root/immich-running ] && [ \$(cat $root/mounted) = boot ]"
ok "old dataset kept" "[ -e $root/dataset-exists ]"
before=$(wc -l < "$root/env"); run run
ok "second run changes nothing" "[ \$(wc -l < $root/env) = $before ]"

run finish; rc=$?
ok "finish destroys the dataset with Immich stopped" "[ $rc = 0 ] && [ ! -e $root/dataset-exists ]"
ok "Immich running after finish" "[ -e $root/immich-running ]"
run rollback
ok "rollback refused after finish" "[ $? != 0 ] && grep -q 'finish already ran' $root/out"

reset; run run
echo new > "$root/boot/thumbs/user/ab/new.webp"
run rollback; rc=$?
ok "rollback succeeds" "[ $rc = 0 ]"
ok "rollback keeps new thumbnails" "[ -e $root/pool/thumbs/user/ab/new.webp ]"
ok "rollback leaves no marker in the dataset" "[ ! -e $root/pool/thumbs/.on-boot-disk ]"
ok ".env restored, other lines kept" "! grep -q IMMICH_THUMBS $root/env && grep -q SECRET=keepme $root/env"
ok "boot copy removed, Immich on datapool" "[ ! -e $root/boot/thumbs ] && [ \$(cat $root/mounted) = pool ]"

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
