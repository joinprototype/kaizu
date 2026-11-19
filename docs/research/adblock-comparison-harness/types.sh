#!/bin/sh
# Empirically map WebKit resource-type values to request kinds via a loopback server.
D="${ADBLOCK_SCRATCH:?Set ADBLOCK_SCRATCH to a scratch folder}"
LOG=$D/out/server.log
python3 -I $D/server.py $LOG 8765 &
SP=$!
sleep 1
for v in none '[]' '["raw"]' '["fetch"]' '["ping"]' '["other"]' '["websocket"]' '["document"]' '["media"]' '["image"]'; do
  if [ "$v" = none ]; then RT=''; else RT=",\"resource-type\":$v"; fi
  echo "[{\"trigger\":{\"url-filter\":\"/t/\"$RT},\"action\":{\"type\":\"block\"}}]" > $D/out/probe-rules.json
  : > $LOG
  $D/swiftharness/h probe $D/out/probe-rules.json http://127.0.0.1:8765/page.html 4 >/dev/null 2>&1
  echo "== resource-type $v : requests that REACHED server:"
  grep -v '^/page' $LOG | sort -u | tr '\n' ' '
  echo
done
kill $SP
