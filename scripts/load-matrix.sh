#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat >&2 <<'EOF'
uso:
  scripts/load-matrix.sh --confirm-staging --env-file ARQUIVO
    [--vuses "1,2,4,8,12"] [--duration SEGUNDOS]
EOF
  exit 2
}

confirmation=''
env_file=''
vuses='1,2,4,8,12'
duration='30'
while (($#)); do
  case "$1" in
    --confirm-staging) confirmation='staging'; shift ;;
    --env-file) env_file="${2:?valor ausente para --env-file}"; shift 2 ;;
    --vuses) vuses="${2:?valor ausente para --vuses}"; shift 2 ;;
    --duration) duration="${2:?valor ausente para --duration}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$confirmation" == staging && -n "$env_file" ]] || usage
[[ -f "$env_file" ]] || {
  printf 'arquivo env não encontrado: %s\n' "$env_file" >&2
  exit 1
}
[[ "$duration" =~ ^[1-9][0-9]*$ ]] || usage

IFS=',' read -r -a vu_values <<<"$vuses"
matrix_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
report_dir="$ROOT_DIR/relatorios/carga/matrix-$matrix_id"
mkdir -p "$report_dir"
manifest="$report_dir/matrix.json"
statuses=()
overall_status=0

for vus in "${vu_values[@]}"; do
  [[ "$vus" =~ ^[1-9][0-9]*$ ]] || {
    printf 'VUs inválidos: %s\n' "$vus" >&2
    exit 1
  }
  report="$report_dir/vus-${vus}.json"
  set +e
  "$ROOT_DIR/scripts/load-ramp.sh" \
    --confirm-staging \
    --scenario radar-cnpj \
    --plan calibration \
    --env-file "$env_file" \
    --vus "$vus" \
    --duration "$duration" \
    --fixture-mode all-miss \
    --expect-capacity-rejection \
    --report "$report"
  status=$?
  set -e
  [[ "$status" -eq 0 ]] || overall_status=1
  statuses+=("{\"vus\":${vus},\"exit_status\":${status},\"report\":\"$(basename "$report")\"}")
done

printf '{\n  "matrix_id": "%s",\n  "duration_seconds": %s,\n  "steps": [%s]\n}\n' \
  "$matrix_id" "$duration" "$(IFS=,; echo "${statuses[*]}")" >"$manifest"
printf 'Matriz concluída. Manifesto sanitizado: %s\n' "$manifest"
exit "$overall_status"
