
#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

IMMICH_SERVER_URL="https://homelab-fbx.lasea.fr:25405/photos/api"
INTERVAL=20  # seconds


API_KEY="${API_KEY:-}"

# ============================================================
# Parameters/config validation
# ============================================================

if [[ -z "$API_KEY" ]]; then
    echo "Error: API_KEY environment variable is not set." >&2
    exit 1
fi

if [[ $# -ne 1 || ! "$1" =~ ^(face|search|wait)$ ]]; then
    echo "Usage: $0 {face|search|wait}" >&2
    exit 1
fi

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed." >&2
        exit 1
    fi
done

MODE="$1"

# ============================================================
# Functions
# ============================================================

api_request() {
    curl --silent --show-error --fail --insecure \
        -H "x-api-key: ${API_KEY}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        "$@"
}

start_job() {
    local queue="$1"

    echo "Starting $queue..."

    api_request -X PUT \
        -d '{"command":"start","force":true}' \
        "${IMMICH_SERVER_URL}/jobs/${queue}"

    echo
}

# ============================================================
# Main
# ============================================================

case "$MODE" in
    face)
        QUEUES=(faceDetection facialRecognition)
        ;;
    search)
        QUEUES=(smartSearch)
        ;;
    wait)
        QUEUES=(faceDetection facialRecognition smartSearch)
        ;;
esac

startDate=$(date +%s)

echo "Start time: $(date +"%H:%M:%S")"
echo "Mode: $MODE"

case "$MODE" in
    face)
        start_job "faceDetection"
        ;;
    search)
        start_job "smartSearch"
        ;;
esac

while true; do
    status=$(api_request "${IMMICH_SERVER_URL}/jobs")

    if ! jq -e . >/dev/null <<< "$status"; then
        echo "Error: Invalid JSON response." >&2
        exit 1
    fi

    all_done=true

    for queue in "${QUEUES[@]}"; do
        counts=$(jq -er --arg q "$queue" \
            '.[$q].jobCounts | [.waiting, .active] | @tsv' \
            <<< "$status") || {
                echo "Error: Missing job counts for $queue." >&2
                exit 1
            }

        read -r waiting active <<< "$counts"

        echo "$(date +"%H:%M:%S") $queue: waiting=$waiting active=$active"

        if (( waiting > 0 || active > 0 )); then
            all_done=false
        fi
    done

    if [[ "$all_done" == true ]]; then
        break
    fi

    echo "Waiting ${INTERVAL} seconds..."
    sleep "$INTERVAL"
done

endDate=$(date +%s)
duration=$((endDate - startDate))

echo "End time: $(date +"%H:%M:%S")"
echo "DURATION: $duration seconds"

echo "$duration" > time.txt
