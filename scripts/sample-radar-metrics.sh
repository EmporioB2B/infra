#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
uso: scripts/sample-radar-metrics.sh --duration SEGUNDOS --output ARQUIVO
  [--interval SEGUNDOS] [--url URL]
EOF
  exit 2
}

duration=''
output=''
interval=5
url='http://10.254.31.30:8082/metrics'
while (($#)); do
  case "$1" in
    --duration) duration="${2:?valor ausente para --duration}"; shift 2 ;;
    --output) output="${2:?valor ausente para --output}"; shift 2 ;;
    --interval) interval="${2:?valor ausente para --interval}"; shift 2 ;;
    --url) url="${2:?valor ausente para --url}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$duration" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[1-9][0-9]*$ && -n "$output" ]] || usage
command -v curl >/dev/null 2>&1 || { printf '%s\n' 'curl não encontrado' >&2; exit 1; }
mkdir -p "$(dirname "$output")"

start="$(date +%s)"
{
  while :; do
    now="$(date +%s)"
    (( now - start >= duration )) && break
    printf '# sample %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    set +e
    metrics="$(curl --fail --silent --show-error --max-time 5 "$url" 2>/dev/null)"
    curl_status=$?
    set -e
    if [[ "$curl_status" -eq 0 ]]; then
      printf '%s\n' "$metrics" |
        awk '/^(radar_rfb_|# (HELP|TYPE) radar_rfb_)/ { print }'
    else
      printf '# scrape_error curl_exit=%s\n' "$curl_status"
    fi
    sleep "$interval"
  done
} >"$output"
