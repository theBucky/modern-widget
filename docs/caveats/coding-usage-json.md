# Coding usage JSON contracts

Claude Code, Codex, and Pi persist session history, not billing records. ModernWidget therefore treats each format as a separate ingestion contract: consume only fields the producer writes, finish provider-specific accounting locally, then emit `timestamp`, `totalTokens`, and `costUSD` to shared aggregation. Missing billing dimensions are never inferred.

Pricing policy and supported model families are fixed by [ADR 0001](../adr/0001-local-ai-usage-accounting.md). This document describes the persisted shapes and the accounting traps around them.

## Shared boundary

| Producer | Physical JSONL roots | Billable record |
| --- | --- | --- |
| Claude Code | `~/.claude/projects` | assistant `message.usage` |
| Codex | `~/.codex/sessions`, `~/.codex/archived_sessions`, or `~/.codex` when neither child exists | `event_msg` with `payload.type == "token_count"` |
| Pi | `~/.pi/agent/sessions` | assistant `message` with persisted token and cost totals |

Production uses these default roots under the current user's home directory. It does not read provider configuration or environment variables to discover alternate homes, and it does not follow symlinked trees.

- Only regular `.jsonl` files participate. The rolling report covers today and the preceding 29 local calendar days.
- A file must be recent enough to contain billable usage, and each emitted event must also fall inside the report window. Codex has one non-billable exception for resolving an older fork parent.
- Unknown keys are skipped, but the complete JSON document must remain structurally valid. A malformed consumed field rejects its record instead of becoming zero.
- Token arithmetic saturates at integer bounds. Numeric cost parsing is locale-independent and rejects non-finite or negative persisted costs.
- Parsed files are cached by path, modification time, change time, size, device, and inode. This invalidates same-size rewrites even when a producer preserves the modification time.
- An unknown manually priced model is a no-op. It contributes neither tokens nor cost, because a token-only or zero-cost partial event would not be an absolute total.

## Claude Code

A usable Claude line has this shape. Fields outside the example are irrelevant to accounting.

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
      "cache_read_input_tokens": 40,
      "cache_creation_input_tokens": 15,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 10,
        "ephemeral_1h_input_tokens": 5
      },
      "inference_geo": "us",
      "service_tier": "standard",
      "speed": "standard"
    }
  }
}
```

The parser requires a valid timestamp, an assistant message, a known model, and a usage object. Present token fields must be non-negative integers. Missing token categories are zero.

- `input_tokens`, `output_tokens`, `cache_read_input_tokens`, five-minute cache writes, and one-hour cache writes remain separate through pricing. `totalTokens` is their saturating sum.
- Structured `cache_creation` wins whenever it is present. The legacy flat `cache_creation_input_tokens` is a five-minute write only when the structured object is absent; the two forms are never added together.
- `inference_geo == "us"` enables the data-residency modifier only for models whose official table supports it. Persisted `speed` and `service_tier` values do not alter the regular price.
- Long-context selection is per message and uses every input category, including cache reads and writes. A threshold applies only when the explicit model table defines one.
- Deduplication runs after date filtering. `message.id` and `requestId` identify copies, `isSidechain == false` wins over a replayed sidechain record, and an out-of-window copy cannot hide an in-window event.

## Codex

Codex accounting spans three line types. A rollout can contain many unrelated `response_item` and `world_state` lines; they are ignored.

```jsonl
{"timestamp":"2026-06-18T01:00:00.000Z","type":"session_meta","payload":{"id":"session-id","forked_from_id":"parent-id","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-id"}}}}}
{"timestamp":"2026-06-18T01:00:00.100Z","type":"turn_context","payload":{"turn_id":"turn-id","model":"gpt-5.5"}}
{"timestamp":"2026-06-18T01:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":40,"output_tokens":30,"reasoning_output_tokens":8,"total_tokens":150}}}}
```

`session_meta.payload.id` identifies the rollout. A fork parent comes from `forked_from_id` or the structured `source.subagent.thread_spawn.parent_thread_id`; scalar `source` values carry no parent identity. The current model comes from the token payload, its `info` object, or the preceding `turn_context`, in that order.

Each accepted `last_token_usage` or `total_token_usage` object must contain integer `input_tokens`, `cached_input_tokens`, and `output_tokens`. `reasoning_output_tokens` and `total_tokens` are derived fields and are ignored.

- `total_token_usage` is cumulative. The billable request is its non-negative delta from the previous cumulative snapshot; an unchanged snapshot emits nothing.
- `last_token_usage` is a per-request fallback only when no cumulative total is present. It advances the cumulative baseline before a later total arrives, preventing the fallback request from being counted twice.
- A zero snapshot can still update model and cumulative state. Independent rollouts are never deduplicated merely because their token values match.
- `cached_input_tokens` is clamped to `input_tokens`. Cached input is priced at the cache-read rate, ordinary input is `input_tokens - cached_input_tokens`, and output remains separate.
- OpenAI and xAI models share this persisted token shape but not a price catalog. Long-context selection is per derived request, never per rollout or day.

### Fork replay

Forked rollouts copy parent turns and cumulative snapshots without storing a replay boundary. The child and parent histories are compared to find the longest exact replay prefix. Inherited token snapshots advance model and cumulative state but do not emit usage; the first real child snapshot and every later child request remain billable.

The parent must be available to establish that boundary. A recent child may reference a parent whose file is older than the report window, so Codex retains old file metadata and parses only the referenced parent. Discovery of such an old parent relies on the official rollout filename ending in its session UUID. Parent events are never emitted.

If a fork relationship is explicit but the parent cannot be resolved, the fork emits nothing. Guessing a replay boundary would silently classify indistinguishable inherited and child snapshots as billable usage.

Active session files take precedence over archived files with the same relative path.

### Unobservable charges

Codex rollouts persist cache reads but not `cache_write_tokens`. GPT 5.6 cache writes may be billable, but a cache miss is still ordinary input and does not prove a write. ModernWidget therefore records no cache-write charge.

Rollouts also do not reliably persist the service tier used by each request. Configuration and launch settings cannot recover historical per-request tier selection, so every observable Codex request uses the regular multiplier. Fast and priority surcharges are not inferred.

## Pi

Pi already persists the final usage cost on each assistant message.

```json
{
  "type": "message",
  "timestamp": "2026-06-18T02:00:00.000Z",
  "message": {
    "role": "assistant",
    "provider": "anthropic",
    "model": "claude-sonnet-5",
    "usage": {
      "input": 100,
      "output": 25,
      "cacheRead": 40,
      "cacheWrite": 15,
      "totalTokens": 180,
      "cost": {
        "input": 0.0003,
        "output": 0.000375,
        "cacheRead": 0.000012,
        "cacheWrite": 0.00005625,
        "total": 0.00074325
      }
    }
  }
}
```

The parser requires `type == "message"`, a valid timestamp, `message.role == "assistant"`, integer `usage.totalTokens`, and finite non-negative `usage.cost.total`. A record with both totals equal to zero is ignored.

Each qualifying assistant message contributes its persisted `totalTokens` and `cost.total` once. Model, provider, token categories, and cost components are deliberately ignored: reconstructing Pi pricing would duplicate the producer's calculation and create a second source of truth.
