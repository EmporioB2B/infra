#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
uso: scripts/sample-container-stats.sh --duration SEGUNDOS --output ARQUIVO [--interval SEGUNDOS]
EOF
  exit 2
}

duration=''
output=''
interval=5
while (($#)); do
  case "$1" in
    --duration) duration="${2:?valor ausente para --duration}"; shift 2 ;;
    --output) output="${2:?valor ausente para --output}"; shift 2 ;;
    --interval) interval="${2:?valor ausente para --interval}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$duration" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[1-9][0-9]*$ && -n "$output" ]] || usage
command -v docker >/dev/null 2>&1 || { printf '%s\n' 'docker não encontrado' >&2; exit 1; }
mkdir -p "$(dirname "$output")"

start="$(date +%s)"
{
  printf 'timestamp\tcontainer\tcpu_percent\tmemory_usage\tmemory_percent\tblock_io\tnetwork_io\tpids\n'
  while :; do
    now="$(date +%s)"
    (( now - start >= duration )) && break
    mapfile -t ids < <(docker ps --filter 'label=com.docker.compose.project=emporio-staging' --format '{{.ID}}')
    if ((${#ids[@]})); then
      docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.BlockIO}}\t{{.NetIO}}\t{{.PIDs}}' "${ids[@]}" |
        while IFS=$'\t' read -r name cpu memory memory_percent block_io network_io pids; do
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$cpu" "$memory" \
            "$memory_percent" "$block_io" "$network_io" "$pids"
        done
    fi
    sleep "$interval"
  done
} >"$output"
