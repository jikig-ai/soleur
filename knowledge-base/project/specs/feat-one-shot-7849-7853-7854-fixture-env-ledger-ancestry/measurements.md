# Measurements — feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry

Taken at plan time, 2026-09-07, against the operator's live checkout. Every figure here is a
baseline the implementation phase re-derives before acting on it.

## M-1 — the aggregator orphan gate

```
INCIDENTS_REPO_ROOT=<main checkout> bash scripts/rule-metrics-aggregate.sh --dry-run
rc=5
::warning::Dropped 77 malformed line(s) (kept 18548)
ERROR: orphan rule_id(s) in incidents jsonl not tagged in AGENTS.md:
  adr-033-inngest-cron-canonical, brand-hex-commit-gate, cq-docs-cli-verification,
  cq-never-skip-hooks, cq-when-lefthook-hangs-in-a-worktree-60s, durable-reminder-prefer-inngest,
  encryption-posture-design-time-default, git-commit-secret-scan, guardrails-block-commit-on-main,
  guardrails-block-delete-branch, guardrails-block-recursive-delete, guardrails-block-rm-rf-worktrees,
  guardrails-require-milestone, guardrails-worktree-write-guard, kb-domain-allowlist-guard,
  post-dispatch-watch-gate, pre-ask-technical-fork-gate, pre-merge-auto-close-scan,
  prod-write-defer-doppler-prd-secrets, prod-write-defer-doppler-secrets-stdout,
  prod-write-defer-git-push-main, prod-write-defer-terraform-apply, skill-security-scan
```

**23 ids. 22 have a live wired emitter under `.claude/hooks/`.** Only
`prod-write-defer-doppler-prd-secrets` does not — it is a renamed sibling of
`prod-write-defer-doppler-secrets-stdout`.

`knowledge-base/project/rule-metrics.json` carries `generated_at: 2026-09-04T15:30:02Z` and is
committed, so it has been silently stale for three days.

## M-2 — ledger contamination

| Corpus | Lines | `gh pr merge 123` | `lib/auth/foo.ts` | `gdpr-gate-*` rows |
|---|---|---|---|---|
| active `.claude/.rule-incidents.jsonl` | 1086 | 109 | 0 | 0 |
| merged (active + 2 `.gz` archives) | 18 625 | **143** | 0 | 0 |

The gdpr-gate rows #7853 measured (8/run, 47 accumulated) have **rotated out**. The live
contamination is a different emitter: `test/pre-merge-rebase.test.ts` driving
`.claude/hooks/pre-merge-rebase.sh`'s `rf-never-skip-qa-review-before-merging` and
`hr-when-a-command-exits-non-zero-or-prints` deny paths with `$CMD` verbatim.

`post-dispatch-watch-gate` carries 896 rows, of which 109 match the fabricated payload and **787 do
not** — so the M-1 orphan count is robust against the quarantine, and there is no ordering
dependency between the ledger fix and the aggregator fix.

## M-3 — the redirect mechanism works

```
SB=$(mktemp -d); mkdir -p "$SB/.claude"
INCIDENTS_REPO_ROOT="$SB" bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh \
  .claude/hooks/lib/incidents.sh scripts/rule-metrics-aggregate.sh \
  plugins/soleur/test/lib/git-fixture-env.ts
```

- `$SB/.claude/.rule-incidents.jsonl`: **2 rows**
- real ledger: **1086 lines, unchanged**

## M-4 — the one-hop ancestry delta

A script walking `/proc` from its own `$$`, and a child it spawns doing the same:

```
SUITE_walk_from_own_pid: 1=bash 2=bash 3=claude 4=bash 5=herdr ...
HOOK_walk_from_own_pid:  1=bash 2=bash 3=bash 4=claude 5=bash 6=herdr ...
```

The hook process sits exactly **one hop deeper**. Both walks are capped at 8
(`MAX_WALK_HOPS=8`; the suite's hand-rolled loop `for _hop in 1 2 3 4 5 6 7 8`), so at any depth
where claude sits at suite-hop 8 the hook needs hop 9 and reports `claude_pid_not_found`.

**This is why #7854's option 2 cannot work:** matching the traversal *limit* leaves the *origin*
one process apart.

## M-5 — tripwire registration set (five, not four)

| Runtime | Anchor |
|---|---|
| bun (repo root) | `bunfig.toml` — `preload = ["./plugins/soleur/test/lib/git-tripwire.ts"]` |
| bun (`cd plugins/soleur`) | `plugins/soleur/bunfig.toml` — `preload = ["./test/lib/git-tripwire.ts"]` |
| vitest | `apps/web-platform/vitest.config.ts:39` — `globalSetup: ["./test/global-setup-git-tripwire.ts"]` (**not** `setupFiles`) |
| shell | `plugins/soleur/test/test-helpers.sh:6-42` — `exit 97` prelude |
| python | `tests/conftest.py`, fired on import from `tests/scripts/_git_fixture_env.py` |

## M-6 — the entry-point set is enumerated twice, both hardcoded

- `plugins/soleur/test/hook-git-env-coverage.test.sh` — a YAML parse of `lefthook.yml` `run:`
  commands, plus one hardcoded `scripts/test-all.sh` block (its N2 check).
- `plugins/soleur/test/git-env-list-parity.test.sh` — a hardcoded three-file loop over
  `lefthook.yml`, `scripts/test-all.sh`, `scripts/hooks/pre-push`.

`.github/scripts/test/run-all.sh` (invoked from `.github/workflows/pr-quality-guards.yml:25` and
from `scripts/test-all.sh:2019`) is in **neither**, and carries no scrub.

## M-7 — ADR ordinal

Max `ADR-<n>` claimed across every `origin/*` ref at plan time: **203**. ADR-204 is provisional and
must be re-derived immediately before merge.
