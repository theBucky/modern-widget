# ADR 0001: Local AI usage accounting

Date: 2026-07-14

Status: Accepted

## Context

ModernWidget derives usage from session files written by Claude Code, Codex, and Pi. These files are local persistence formats, not billing APIs and not a shared schema. The three producers expose different token semantics and enough provider-specific behavior that a generic raw usage model makes invalid combinations easy to represent.

The report is a local reconstruction. It must use only fields persisted by each producer and must never invent missing billing dimensions.

## Decision

### Architecture

Each provider owns its complete ingestion boundary:

1. Discover only that provider's session roots and files.
2. Parse the provider's persisted schema into provider-specific strict types.
3. Resolve provider-specific pricing and deduplication.
4. Emit normalized events containing only `timestamp`, `totalTokens`, and `costUSD`.

Shared code owns file traversal, date bucketing, refresh orchestration, and report aggregation. It does not own a generic token or billing schema. Claude, Codex, and Pi raw events and billing types remain separate even when field names happen to match.

Unknown manually priced models are a no-op. Their events contribute neither tokens nor cost. No base-model fallback, fuzzy alias, or zero-cost partial event is emitted. A later app version with explicit model support can rescan the original session files after restart.

Price tables are embedded per provider and contain official regular prices only. Promotional windows, including the introductory Claude Sonnet 5 price, and historical fast-mode pricing are intentionally unsupported. Every manually priced model has a complete per-million-token table for input, output, cache reads, and every cache-write duration that provider defines. Source literals use ordinary decimal numbers; conversion from per-million prices happens once in the calculation.

The embedded tables are checked against official provider documentation and the provider catalogs in `models.dev/api.json`. `models.dev/models.json` contains model metadata but no cost fields. Runtime loading from either source is out of scope.

The final report stores one numeric `costUSD`. It has no estimated, confidence, or partial state.

### Claude

Claude usage is read from assistant message usage objects. The parser consumes normal input, output, cache reads, five-minute cache writes, and one-hour cache writes.

Five-minute and one-hour cache writes remain distinct billable quantities. The legacy flat `cache_creation_input_tokens` field is interpreted as a five-minute write only when the structured cache-creation object is absent.

Official long-context prices are selected per request using all Claude input categories, including cache reads and writes. The US data-residency modifier applies only when its explicit persisted field says it was used. Historical `speed` values do not change the regular catalog price.

Legacy `claude-3-5-haiku`, `claude-opus-4`, `claude-opus-4-1`, and `claude-sonnet-4` records are unsupported and follow the unknown-model no-op rule. `claude-mythos-5` and `claude-fable-5` share the same complete regular price table.

Claude message and request identifiers are used only for provider-specific deduplication. Non-sidechain records take precedence over replayed sidechain records.

### Codex

Codex usage is read from rollout JSONL written by the official client. GPT and Grok records use the same Responses API-derived persisted shape, but their price tables remain provider-specific.

`total_token_usage` is cumulative. Per-request usage is the non-negative delta from the previous cumulative snapshot, so an unchanged cumulative snapshot contributes nothing. `last_token_usage` is a per-request fallback for legacy records without a cumulative total; equal fallback values can represent distinct requests and are counted independently.

Forked rollouts may copy parent history. A `forked_from_id` or structured subagent `thread_spawn` relationship suppresses confirmed inherited history while preserving usage created by the child.

`cached_input_tokens` is a subset of `input_tokens`. Codex billing therefore uses:

* cached input: `cached_input_tokens`
* ordinary input: `input_tokens - cached_input_tokens`
* output: `output_tokens`

The GPT 5.6 family can bill prompt-cache writes separately. The Responses API exposes `cache_write_tokens`, but current Codex rollouts do not persist it. A cache miss does not prove a cache write, so ModernWidget does not infer cache writes and does not add a cache-write charge. The persisted ordinary input remains ordinary input. Complete cache-write rates still exist in the OpenAI table so model definitions cannot represent a partial price schema.

Codex rollouts also do not reliably persist the service tier that applied to each request. ModernWidget ignores configuration files and tier hints, prices every Codex request at the standard multiplier, and does not attempt to reproduce fast or priority surcharges.

Retired GPT 5, GPT 5.1, and GPT 5.2 model families are unsupported and follow the unknown-model no-op rule.

Long-context pricing is applied per request when official pricing defines a request-size threshold. It is not inferred from daily or session totals.

### Reference implementations

The official Codex client defines which rollout fields exist and is authoritative for persistence semantics. `ccusage` is treated only as a comparative implementation. Its useful traversal and cumulative-delta ideas are retained only after verification against producer data; generic provider schemas, fallback prices, missing-field guesses, and configuration-derived Codex tier pricing are not adopted.

### Pi

Pi's persisted usage is authoritative. ModernWidget sums `usage.totalTokens` and `usage.cost.total` from assistant messages and does not reconstruct Pi pricing from token categories or model names.

### Runtime and persistence

The app scans only the active history window and rejects stale files before parsing. Parsed immutable provider events may be cached by file fingerprint. Refresh fingerprints contain only inputs that can change the resulting report.

No derived usage database is introduced. Restarting the app rescans source logs, so newly supported models become visible without a migration. Fields discarded by the producer, such as historical Codex cache-write tokens or per-request service tier, cannot be recovered later.

Existing UI behavior, settings keys, report retention, and user data formats remain stable. Corrected totals and costs are expected behavior changes.

## Consequences

Provider parsers can evolve independently without widening a shared DTO. Unsupported records disappear cleanly instead of leaking token-only rows or fabricated zero costs into the report.

Codex totals intentionally exclude unobservable cache-write surcharges and tier multipliers. This is preferable to producing a precise-looking value from unsupported assumptions.

Adding a priced model requires an explicit complete provider table entry and behavioral coverage. Adding a new persisted field starts at the provider parser and does not alter the shared aggregation contract.

## Sources

* [OpenAI Prompt Caching](https://developers.openai.com/api/docs/guides/prompt-caching)
* [OpenAI model pricing](https://developers.openai.com/api/docs/pricing)
* [Anthropic pricing](https://docs.anthropic.com/en/docs/about-claude/pricing)
* [xAI Grok 4.5](https://docs.x.ai/developers/models/grok-4.5)
* [xAI pricing](https://docs.x.ai/developers/pricing)
* [models.dev provider catalog](https://models.dev/api.json)

The Codex persistence behavior is verified against a local checkout of the official client source and representative local rollout files.
