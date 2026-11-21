#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.staging.yml"
PROJECT='emporio-staging'

usage() {
  cat >&2 <<'EOF'
uso:
  scripts/load-ramp.sh --confirm-staging \
    --scenario public|api-radar|radar-cnpj|login-rate-limit \
    [--plan calibration|full] [--env-file ARQUIVO] [--report ARQUIVO]
EOF
  exit 2
}

confirmation=''
scenario=''
plan='calibration'
env_file=''
report=''
while (($#)); do
  case "$1" in
    --confirm-staging) confirmation='staging'; shift ;;
    --scenario) scenario="${2:?valor ausente para --scenario}"; shift 2 ;;
    --plan) plan="${2:?valor ausente para --plan}"; shift 2 ;;
    --env-file) env_file="${2:?valor ausente para --env-file}"; shift 2 ;;
    --report) report="${2:?valor ausente para --report}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$confirmation" == staging ]] || { printf '%s\n' 'é obrigatória a confirmação --confirm-staging' >&2; exit 1; }
[[ "$scenario" =~ ^(public|api-radar|radar-cnpj|login-rate-limit)$ ]] || usage
[[ "$plan" =~ ^(calibration|full)$ ]] || usage
command -v docker >/dev/null 2>&1 || { printf '%s\n' 'docker não encontrado' >&2; exit 1; }
docker info >/dev/null 2>&1 || { printf '%s\n' 'daemon Docker inacessível' >&2; exit 1; }
if [[ -n "$env_file" && ! -f "$env_file" ]]; then
  printf 'arquivo env não encontrado: %s\n' "$env_file" >&2
  exit 1
fi

case "$scenario" in
  public)
    required_network="${PROJECT}_apps"
    service='loadtest'
    base_url='https://api-staging.emporiob2b.com.br'
    mode='public'
    script='/opt/emporio/loadtests/api-radar.js'
    ;;
  api-radar)
    required_network="${PROJECT}_apps"
    service='loadtest-api-radar'
    base_url='http://api:8080'
    mode='internal'
    script='/opt/emporio/loadtests/api-radar.js'
    ;;
  radar-cnpj)
    required_network="${PROJECT}_radar-net"
    service='loadtest-radar'
    base_url='http://radar:8000'
    mode='direct-radar'
    script='/opt/emporio/loadtests/radar-cnpj.js'
    ;;
  login-rate-limit)
    required_network="${PROJECT}_apps"
    service='loadtest'
    base_url='https://api-staging.emporiob2b.com.br'
    mode='public'
    script='/opt/emporio/loadtests/login-rate-limit.js'
    plan='calibration'
    ;;
esac

docker network inspect "$required_network" >/dev/null 2>&1 || {
  printf 'rede do staging ausente: %s; suba o staging antes da execução\n' \
    "$required_network" >&2
  exit 1
}

# Redes declaradas exclusivamente por services de profile não são criadas no
# deploy normal. `docker compose run` cria a rede declarada pelo serviço
# profile antes de iniciar o container; não exija o egress previamente.

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
work_dir="${TMPDIR:-/tmp}/emporio-loadtest-$run_id"
mkdir -p "$work_dir"
raw_summary="$work_dir/k6-summary.json"
raw_stats="$work_dir/container-stats.tsv"
raw_events="$work_dir/container-events.tsv"
container_name="emporio-loadtest-$run_id"
stats_pid=''
events_pid=''
# Invoked indirectly by EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  [[ -z "$stats_pid" ]] || kill "$stats_pid" >/dev/null 2>&1 || true
  [[ -z "$events_pid" ]] || kill "$events_pid" >/dev/null 2>&1 || true
  docker rm "$container_name" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

duration=60
[[ "$plan" == full && "$scenario" != login-rate-limit ]] && duration=420
"$ROOT_DIR/scripts/sample-container-stats.sh" --duration "$duration" --output "$raw_stats" &
stats_pid=$!
docker events \
  --filter 'label=com.docker.compose.project=emporio-staging' \
  --format '{{.Time}}\t{{.Action}}\t{{.Actor.Attributes.name}}' >"$raw_events" &
events_pid=$!

set +e
compose_args=(-f "$COMPOSE_FILE")
[[ -z "$env_file" ]] || compose_args=(--env-file "$env_file" "${compose_args[@]}")
docker compose "${compose_args[@]}" --profile loadtest run \
  --name "$container_name" \
  --no-deps \
  -e "K6_BASE_URL=$base_url" \
  -e "K6_MODE=$mode" \
  -e "K6_PLAN=$plan" \
  "$service" run --summary-export=/tmp/k6-summary.json "$script"
status=$?
set -e

docker cp "$container_name:/tmp/k6-summary.json" "$raw_summary" >/dev/null 2>&1 || true
kill "$events_pid" >/dev/null 2>&1 || true
wait "$events_pid" || true
wait "$stats_pid" || true
[[ -s "$raw_summary" ]] || { printf '%s\n' 'k6 não produziu resumo sanitizado' >&2; exit "$status"; }
image_inventory="$work_dir/images.tsv"
: >"$image_inventory"
for repository in \
  ghcr.io/emporiob2b/backend-java \
  ghcr.io/emporiob2b/front-angular \
  ghcr.io/emporiob2b/radar-middleware \
  ghcr.io/emporiob2b/infra-loadtest \
  grafana/k6 \
  postgres \
  cloudflare/cloudflared \
  prom/prometheus; do
  docker image ls --digests --format '{{.Repository}}\t{{.Tag}}\t{{.Digest}}' "$repository" \
    >>"$image_inventory" 2>/dev/null || true
done

if [[ -z "$report" ]]; then
  report="$ROOT_DIR/relatorios/carga/${run_id}-${scenario}.json"
fi
mkdir -p "$(dirname "$report")"
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
infra_sha="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'uncommitted')"
python3 - "$raw_summary" "$raw_stats" "$raw_events" "$image_inventory" "$report" "$run_id" "$scenario" "$plan" "$mode" "$status" "$started_at" "$finished_at" "$infra_sha" <<'PY'
import json
import pathlib
import sys

summary_path, stats_path, events_path, images_path, report_path, run_id, scenario, plan, mode, status, started_at, finished_at, infra_sha = sys.argv[1:]
summary = json.loads(pathlib.Path(summary_path).read_text())
metrics = summary.get("metrics", {})
duration = metrics.get("http_req_duration", {})
requests = metrics.get("http_reqs", {})
checks = metrics.get("checks", {})

containers = {}
for line in pathlib.Path(stats_path).read_text().splitlines()[1:]:
    fields = line.split("\t")
    if len(fields) != 8:
        continue
    _, name, cpu, memory, memory_percent, block_io, network_io, pids = fields
    containers.setdefault(name, []).append({
        "cpu_percent": cpu,
        "memory_usage": memory,
        "memory_percent": memory_percent,
        "block_io": block_io,
        "network_io": network_io,
        "pids": pids,
    })

images = []
for line in pathlib.Path(images_path).read_text().splitlines():
    repository, tag, digest = line.split("\t", 2)
    images.append({"repository": repository, "tag": tag, "digest": digest})

events = []
for line in pathlib.Path(events_path).read_text().splitlines():
    fields = line.split("\t")
    if len(fields) == 3 and fields[1] in {"oom", "restart", "die"}:
        events.append({
            "timestamp": fields[0],
            "action": fields[1],
            "container": fields[2],
        })

result = {
    "execution_id": run_id,
    "infra_sha": infra_sha,
    "scenario": scenario,
    "mode": mode,
    "plan": plan,
    "started_at_utc": started_at,
    "finished_at_utc": finished_at,
    "exit_status": int(status),
    "request_count": requests.get("count", 0),
    "throughput": requests.get("rate", 0),
    "latency_ms": {
        "p50": duration.get("med"),
        "p95": duration.get("p(95)"),
        "p99": duration.get("p(99)"),
    },
    "checks": {
        "passes": checks.get("passes", 0),
        "fails": checks.get("fails", 0),
    },
    "images": images,
    "container_events": events,
    "container_stats_samples": containers,
    "limitations": [
        "CPU e memória são amostras de docker stats no host, não métricas Prometheus.",
        "O resultado é exploratório e não representa capacidade aprovada.",
    ],
}
pathlib.Path(report_path).write_text(json.dumps(result, indent=2) + "\n")
PY

printf 'Relatório sanitizado: %s\n' "$report"
exit "$status"
