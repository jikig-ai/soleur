# Phase 0 evidence (2026-10-08)

Pricing refetch (https://platform.claude.com/docs/en/about-claude/pricing, fetched 2026-10-08):

- Haiku 5.5, prompts up to 100,000 tokens: input $0.10, 5m cache write $0.125, 1h write $0.20, cache hit $0.01, output $0.50 per MTok.
- Haiku 5.5, prompts over 100,000 tokens: input $0.50, 5m write $0.625, 1h write $1, cache hit $0.05, output $2.50 per MTok.
- Sonnet 5.5 cache hits: $0.10 per MTok, stated twice (table footnote 2: "0.05x the base input price", and the prompt-caching paragraph: "$0.10 USD on Claude Sonnet 5.5"). The repo row carried $0.20, so the Phase B item 4 correction applies.

Live probe: key = Doppler `ci` `ANTHROPIC_API_KEY` (the spend-limited `soleur-ci-eval` workspace key, ADR-244; not the production BYOK or operator key), read through `doppler run`, passed to curl via process substitution, synthesized inputs, N=5 per cell, model `claude-haiku-5-5`. Logged only status, stop_reason, block types, usage.

| Cell | Result (5 runs) |
|---|---|
| router, default, `max_tokens` 200 | 200 OK, `end_turn`, text block 5/5; 2 shapes seen (`text`, `thinking+text`); output tokens 21 to 148 (thinking can use most of the 200 budget) |
| router, `effort: low` + `format` json_schema | 200 OK (the combination is accepted), `end_turn`, text block 5/5, no thinking block, output tokens 17 to 21 |
| summarizer, default, `max_tokens` 256 | 200 OK, `end_turn`, text 5/5, 87 to 100 tokens |
| summarizer, `effort: low` | 200 OK, `end_turn`, text 5/5, 87 to 105 tokens |
| preflight, default, `max_tokens` 1 | 200 OK, `stop_reason: max_tokens` 5/5 (a 200 is the pass condition) |
| retrieval bench, default, `max_tokens` 512 | 200 OK, `end_turn`, `thinking+text`, 104 to 133 tokens, no truncation |
| retrieval bench, `effort: low` | 200 OK, text only, 61 to 76 tokens |
| leader loop, default, 4096, 2 tools, `cache_control` | 200 OK, `tool_use` 5/5, `thinking+tool_use+tool_use`, 455 to 555 tokens, no `max_tokens` stop |
| leader loop, `effort: low` | 200 OK, `tool_use` 5/5, 400 to 478 tokens |
| leader loop, security-flavored issue body, default | 200 OK, `tool_use` 5/5, no refusal (0 of 5), 627 to 775 tokens |

Decision-rule outcome (plan Phase 0 item 3 and 4):

- Router and summarizer ship `output_config.effort: "low"`; no budget raise (cell b never truncates).
- Leader loop: no truncation and no refusal observed, so the conditional Phase C item 3 (leader `effort` field, `promptVersion` bump) is NOT activated.
- Preflight: HTTP 200, so the action swaps to `claude-haiku-5-5`; the audit carve-out covers only the two SDK-path scripts.
- Retrieval bench: no truncation at 512, so no `effort` is added to its request body.
- `thinking: {"type": "disabled"}` was not probed and is not used.
