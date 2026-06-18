#!/usr/bin/env bash
set -euo pipefail

mode="real"
iterations="5"
warmups="1"
fixture_files="90"
fixture_lines="400"
max_scan_p95_ms=""
max_load_p95_ms=""
max_startup_p95_ms=""
max_refresh_p95_ms=""

usage() {
    cat <<'USAGE'
usage: script/benchmark_coding_usage.sh [options]

options:
  --mode real|fixture                 benchmark local usage logs or generated fixture
  --iterations n                      measured runs, default 5
  --warmups n                         warmup runs, default 1
  --fixture-files n                   fixture file count, default 90
  --fixture-lines n                   lines per fixture file, default 400
  --max-scan-p95-ms n                 fail if scan p95 exceeds n ms
  --max-load-p95-ms n                 fail if load p95 exceeds n ms
  --max-startup-p95-ms n              fail if startup p95 exceeds n ms
  --max-refresh-p95-ms n              fail if no-change refresh p95 exceeds n ms
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            mode="${2:?missing --mode value}"
            shift 2
            ;;
        --iterations)
            iterations="${2:?missing --iterations value}"
            shift 2
            ;;
        --warmups)
            warmups="${2:?missing --warmups value}"
            shift 2
            ;;
        --fixture-files)
            fixture_files="${2:?missing --fixture-files value}"
            shift 2
            ;;
        --fixture-lines)
            fixture_lines="${2:?missing --fixture-lines value}"
            shift 2
            ;;
        --max-scan-p95-ms)
            max_scan_p95_ms="${2:?missing --max-scan-p95-ms value}"
            shift 2
            ;;
        --max-load-p95-ms)
            max_load_p95_ms="${2:?missing --max-load-p95-ms value}"
            shift 2
            ;;
        --max-startup-p95-ms)
            max_startup_p95_ms="${2:?missing --max-startup-p95-ms value}"
            shift 2
            ;;
        --max-refresh-p95-ms)
            max_refresh_p95_ms="${2:?missing --max-refresh-p95-ms value}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$mode" in
    real|fixture)
        ;;
    *)
        echo "--mode must be real or fixture" >&2
        exit 2
        ;;
esac

CODING_USAGE_BENCHMARK=1 \
CODING_USAGE_BENCHMARK_MODE="$mode" \
CODING_USAGE_BENCHMARK_ITERATIONS="$iterations" \
CODING_USAGE_BENCHMARK_WARMUPS="$warmups" \
CODING_USAGE_BENCHMARK_FIXTURE_FILES="$fixture_files" \
CODING_USAGE_BENCHMARK_FIXTURE_LINES="$fixture_lines" \
CODING_USAGE_BENCHMARK_MAX_SCAN_P95_MS="$max_scan_p95_ms" \
CODING_USAGE_BENCHMARK_MAX_LOAD_P95_MS="$max_load_p95_ms" \
CODING_USAGE_BENCHMARK_MAX_STARTUP_P95_MS="$max_startup_p95_ms" \
CODING_USAGE_BENCHMARK_MAX_REFRESH_P95_MS="$max_refresh_p95_ms" \
swift test --filter CodingUsageBenchmarkTests
