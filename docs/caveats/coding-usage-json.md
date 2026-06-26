# Coding Usage JSON Caveats

This app reads local usage logs from Claude, Codex, and Pi. These logs are not a shared schema. Keep the parsing model source-specific, and normalize at the loader boundary before data reaches `CodingTokenCounts`.

## Shared rules

- Scan only recently modified files from the active history window. Old files are ignored before JSON parsing.
- Parse each source with its real field names. Do not introduce a generic usage DTO across Claude, Codex, and Pi.
- Treat corrupt numeric records as bad input, not as a reason to crash. Token sums use saturating arithmetic.
- `CodingTokenCounts.add` also saturates, so per-record normalization and final aggregation both tolerate malformed large values.
- Date scoping belongs before any dedupe step that can choose between equivalent records from different timestamps.
- Pricing model normalization is intentionally conservative. Unknown dated model variants should not be silently priced as a broader base model unless the version boundary rules match.

## Claude

Files are JSONL transcripts under Claude config directories:

- `$CLAUDE_CONFIG_DIR/projects`
- `$XDG_CONFIG_HOME/claude/projects`
- `~/.claude/projects`

If `CLAUDE_CONFIG_DIR` points directly at `projects`, the loader normalizes it to the parent config directory.

Typical record:

```json
{
  "timestamp": "2026-06-18T02:00:00.000Z",
  "requestId": "req_123",
  "isSidechain": false,
  "message": {
    "id": "msg_123",
    "model": "claude-sonnet-4-20250514",
    "usage": {
      "input_tokens": 100,
      "output_tokens": 25,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 10,
        "ephemeral_1h_input_tokens": 5
      },
      "cache_read_input_tokens": 40,
      "service_tier": "priority"
    }
  }
}
```

Important details:

- Count only records with `timestamp`, `message`, and a `message.usage` object.
- `cache_creation.ephemeral_5m_input_tokens` and `cache_creation.ephemeral_1h_input_tokens` are preferred when the `cache_creation` object exists.
- The older flat `cache_creation_input_tokens` fallback is treated as 5 minute cache creation only, and 1 hour cache creation is zero.
- `usage.service_tier == "priority"` uses fast pricing.
- Deduplication is keyed by `message.id` plus `requestId`, with an extra collapse for same-message records when either side is a sidechain.
- Non-sidechain entries beat sidechain entries. For equal sidechain state, higher `totalTokens` wins, then higher cost wins.
- Date filtering must happen before `dedupeClaudeEntries`. If an out-of-window duplicate wins first, the accumulator drops it and the valid in-window record disappears.

## Codex

Files are JSONL session logs under:

- `$CODEX_HOME/sessions`
- `$CODEX_HOME/archived_sessions`
- `$CODEX_HOME` when neither session directory exists
- `~/.codex/...` when `CODEX_HOME` is not set

Active sessions are scanned before archived sessions. File dedupe is scoped by Codex home and relative path, so archived duplicates of active files are ignored. Event dedupe is also scoped by Codex home.

Typical token event:

```json
{
  "timestamp": "2026-06-18T02:00:00.250Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "last_token_usage": {
        "input_tokens": 120,
        "cached_input_tokens": 40,
        "output_tokens": 30,
        "reasoning_output_tokens": 8
      },
      "model": "gpt-5.2-codex"
    }
  }
}
```

Other relevant lines:

```json
{
  "timestamp": "2026-06-18T01:59:59.000Z",
  "type": "turn_context",
  "payload": {
    "model": "gpt-5.2-codex"
  }
}
```

```json
{
  "timestamp": "2026-06-18T02:00:00.000Z",
  "type": "session_meta",
  "payload": {
    "source": {
      "subagent": {
        "thread_spawn": {
          "parent_thread_id": "parent"
        }
      }
    }
  }
}
```

Important details:

- `payload.info.last_token_usage` is already a delta.
- `payload.info.total_token_usage` is cumulative. Convert it to a delta by subtracting the previous cumulative snapshot.
- `payload.model`, `payload.info.model`, and previous `turn_context` model lines can all supply model context.
- `cached_input_tokens` is clamped to `input_tokens` at the raw usage boundary. Downstream code can subtract without underflow guards.
- Fractional timestamp precision matters. Do not collapse events just because they share the same second.
- Subagent transcripts can replay parent cumulative token history immediately after a real `session_meta.payload.source.subagent.thread_spawn` record. Suppress that replay, but do not suppress arbitrary text containing `"thread_spawn"`.
- `config.toml` fast pricing is read only from the top-level `service_tier` setting before the first TOML table. `fast` and `priority` mean fast pricing. Scoped/table overrides are intentionally ignored.

## Pi

Files are JSONL session logs under:

- `$PI_AGENT_DIR`
- `~/.pi/agent/sessions`

Typical record:

```json
{
  "type": "message",
  "timestamp": "2026-06-18T02:00:00.000Z",
  "message": {
    "role": "assistant",
    "model": "gpt-5.4",
    "usage": {
      "input": 100,
      "output": 50,
      "cacheRead": 10,
      "cacheWrite": 20,
      "cacheWrite1h": 8,
      "totalTokens": 180
    }
  }
}
```

Important details:

- Count only assistant messages with a `usage` object. User messages with usage are ignored.
- Pi uses camelCase fields, not Claude/Codex snake case.
- If `output` is zero, infer output from `totalTokens - (input + cacheWrite + cacheRead)` using saturating arithmetic.
- `totalTokens` is the max of the raw `totalTokens` and the locally reconstructed `input + cacheWrite + cacheRead + output`.
- `cacheWrite1h` is clamped to at most `cacheWrite`. The remainder is treated as 5 minute cache creation.
- Keep output, non-output, and total sums saturating. Plain `UInt64` addition can trap on malformed-but-numeric logs.
