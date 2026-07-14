# Coding usage JSON caveats

Claude Code, Codex, and Pi persist different schemas. Parse each source into strict provider types, finish pricing and deduplication inside that provider, then emit only `timestamp`, `totalTokens`, and `costUSD` to shared aggregation.

## Shared rules

* Reject files older than the active history window before parsing.
* Treat malformed records as unusable input. Token addition remains saturating.
* Use embedded official regular prices only. Do not add promotional price windows.
* Store prices as ordinary per-million-token decimals, with every category present on every model record.
* Omit an unknown manually priced model entirely. Do not emit token-only or zero-cost partial events.
* Keep provider identifiers and raw billing categories out of the shared report model.

## Claude

Session JSONL is discovered under `~/.claude/projects`.

```json
{
  "timestamp": "2026-06-18T02:00:00.000Z",
  "requestId": "req_123",
  "isSidechain": false,
  "message": {
    "role": "assistant",
    "id": "msg_123",
    "model": "claude-sonnet-5",
    "usage": {
      "input_tokens": 100,
      "output_tokens": 25,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 10,
        "ephemeral_1h_input_tokens": 5
      },
      "cache_read_input_tokens": 40,
      "inference_geo": "us"
    }
  }
}
```

Claude rules:

* Count assistant records containing `timestamp`, `message.model`, and `message.usage`.
* Keep normal input, output, cache reads, five-minute cache writes, and one-hour cache writes distinct until pricing completes.
* Prefer structured cache creation. Use legacy `cache_creation_input_tokens` as a five-minute write only when the structured object is absent.
* Apply the data-residency modifier only when it is explicitly persisted on the event. Ignore historical fast-mode pricing and use regular catalog prices.
* Apply official long-context rates per request using normal input plus cache reads and writes.
* Deduplicate with Claude message and request identifiers. A main-chain record wins over its sidechain copy.
* Filter by event date before deduplication so an out-of-window copy cannot hide an in-window event.
* Treat unsupported legacy models and models without a complete catalog price as unknown-model no-ops.

## Codex

Rollout JSONL is discovered under the standard Codex home:

* `~/.codex/sessions`
* `~/.codex/archived_sessions`
* `~/.codex` when neither child directory exists

```json
{
  "timestamp": "2026-06-18T02:00:00.250Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": 120,
        "cached_input_tokens": 40,
        "output_tokens": 30,
        "reasoning_output_tokens": 8,
        "total_tokens": 150
      },
      "model": "gpt-5.5"
    }
  }
}
```

Codex rules:

* `total_token_usage` is cumulative. Subtract the previous cumulative snapshot to obtain one request. Use `last_token_usage` only when cumulative usage is absent.
* Resolve the model from the token event, its `info` object, or the preceding `turn_context`.
* Clamp `cached_input_tokens` to `input_tokens`, then price the remainder as ordinary input.
* Do not infer cache writes. Codex rollouts do not persist `cache_write_tokens`, and a cache miss is still ordinary input.
* Do not read `config.toml` or infer service tier. Price every observable Codex request at standard rates.
* Keep OpenAI and xAI price catalogs separate even though Codex persists both through the same Responses-derived token shape.
* Apply long-context price tiers to each request, never a session or daily total.
* Suppress confirmed inherited fork history identified by `forked_from_id` or structured subagent `thread_spawn` metadata.
* Active session files take precedence over archived copies with the same relative path.

## Pi

Session JSONL is discovered under `~/.pi/agent/sessions`.

```json
{
  "type": "message",
  "timestamp": "2026-06-18T02:00:00.000Z",
  "message": {
    "role": "assistant",
    "usage": {
      "totalTokens": 180,
      "cost": {
        "total": 0.0042
      }
    }
  }
}
```

Pi rules:

* Count only assistant messages containing both `usage.totalTokens` and `usage.cost.total`.
* Treat both persisted values as authoritative.
* Ignore model names and token category fields. Never reconstruct Pi pricing locally.

## Benchmark

```bash
script/benchmark_coding_usage.sh --mode real
script/benchmark_coding_usage.sh --mode fixture --fixture-files 90 --fixture-lines 400
```

The benchmark reports `scan`, `load.cold`, `load.cached`, `startup.cold`, and `refresh.no_change` with minimum, mean, p50, p95, and maximum milliseconds. Optional `--max-*-p95-ms` arguments turn the fixture run into a regression gate.
