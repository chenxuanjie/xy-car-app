#!/bin/sh
set -eu

/opt/vehicle-discovery/bin/python -m uvicorn --app-dir /srv vehicle_discovery:app \
    --uds /tmp/xy-car-discovery.sock --workers 1 --ws websockets-sansio \
    --ws-max-size 16384 --timeout-graceful-shutdown 4 &
discovery_pid=$!
/docker-entrypoint.sh "$@" &
web_pid=$!

stop() {
    trap '' TERM INT
    kill "$web_pid" "$discovery_pid" 2>/dev/null || true
    wait "$web_pid" "$discovery_pid" || true
}

trap 'stop; exit 0' TERM INT
status=0
wait -n || status=$?
stop
exit "$status"
