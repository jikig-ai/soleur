# Canonical jq Clause: Exclude Agent-Authored Issues

Canonical exclusion filter for any workflow that reads open issues from the GitHub
tracker and feeds them into an automation loop (auto-fix, auto-triage, scheduled
monitors). Drop any issue whose labels include `ux-audit` OR any label whose name
starts with `agent:`.

See [agent-authored-exclusion.md](./agent-authored-exclusion.md) for the governance
rationale and the label convention.

## Canonical clause

Two branches: `ux-audit` is the legacy stream tag (load-bearing for current
tracker state — see
[agent-authored-exclusion.md](./agent-authored-exclusion.md) "Retroactive
stream-tag dependency"); `agent:*` is the canonical prefix for future streams.

```jq
map(select(
  (.labels | map(.name) | index("ux-audit") | not) and
  (.labels | map(.name) | any(startswith("agent:")) | not)
))
```

## Inline form (for per-priority `select(...)` blocks)

```jq
(.labels | map(.name) | index("ux-audit") | not) and
(.labels | map(.name) | any(startswith("agent:")) | not)
```

## Correctness properties

- Both branches are OR'd via `and (... not)` — an issue is kept iff it has NEITHER
  the `ux-audit` tag NOR any `agent:*` label. Removing either branch regresses
  real tracker state (see note above).
- The filter preserves input order. When composed with `sort_by(.createdAt) | .[0]`
  (as in `scheduled-bug-fixer.yml`), filter BEFORE sort so the FIFO contract
  holds.
- `startswith("agent:")` is a jq string method, not a regex. Implicitly
  left-anchored; colon is a literal — no escaping required.
- `index("ux-audit")` matches exact label name only; no substring semantics.

## `gh --jq` pitfall

`gh issue list --jq '<expr>'` accepts one jq expression STRING. It does NOT
forward jq flags (`--arg`, `--argjson`) — those get parsed as unknown `gh`
arguments. This clause uses only hard-coded string literals (`"ux-audit"`,
`"agent:"`) so the pitfall does not apply.

If a future adopter parameterizes the excluded label set (e.g. for a per-repo
config), variable substitution MUST use `export VAR=...; jq '... $ENV.VAR ...'`
via a pipe — NOT `gh issue list --jq ... --arg VAR ...`. See
[2026-03-03-scheduled-bot-fix-workflow-patterns.md](../../../../knowledge-base/project/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md).

## Shell-escape safety

Inside GitHub Actions `run:` blocks, avoid `!= ""` in `gh --jq` expressions —
`!` gets mangled by shell history expansion under some runners. This clause uses
only predicate-negation forms (`index(...) | not`, `any(...) | not`); there is no
bare `!` anywhere in the expression.

## Consumers

- `.github/workflows/scheduled-bug-fixer.yml` — per-priority selection loop
- `.github/workflows/scheduled-daily-triage.yml` — triage prompt's initial
  `gh issue list` invocation

Any new workflow that consumes open issues for automation MUST adopt this clause
verbatim (or the inline form). Copy-paste is intentional: the correctness
properties and the load-bearing `ux-audit` branch are documented in one place,
and touching the clause in one workflow without touching the others is a
governance-loop regression risk.

## Local fixture test

Runnable without network; use as a regression check after any edit to this
clause:

```bash
cat <<'EOF' | jq 'map(select(
  (.labels | map(.name) | index("ux-audit") | not) and
  (.labels | map(.name) | any(startswith("agent:")) | not)
)) | map(.number)'
[
  {"number": 1, "title": "normal bug",        "labels":[{"name":"type/bug"},{"name":"priority/p3-low"}]},
  {"number": 2, "title": "ux-audit finding",  "labels":[{"name":"ux-audit"},{"name":"domain/product"}]},
  {"number": 3, "title": "agent finding",     "labels":[{"name":"agent:ux-design-lead"},{"name":"type/feature"}]},
  {"number": 4, "title": "both labels",       "labels":[{"name":"ux-audit"},{"name":"agent:ux-design-lead"}]},
  {"number": 5, "title": "bug mentions agent","labels":[{"name":"type/bug"},{"name":"priority/p2-medium"}]}
]
EOF
```

Expected output: `[1, 5]` — issues #2, #3, #4 all dropped. "agent" in issue #5's
title is not a label, so it is kept.
