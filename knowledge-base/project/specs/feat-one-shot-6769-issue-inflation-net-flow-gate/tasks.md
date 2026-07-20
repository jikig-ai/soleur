# Tasks — issue-inflation net-flow gate

Derived from
[`knowledge-base/project/plans/2026-07-20-fix-issue-inflation-net-flow-gate-plan.md`](../../plans/2026-07-20-fix-issue-inflation-net-flow-gate-plan.md)
(post-plan-review revision).

`Closes #6769`. **This PR files zero issues** and must pass the `NET > 0` gate it installs.

---

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 Read `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` header — the script shape being copied.
- [ ] 0.2 Read `.claude/hooks/ship-soak-followthrough-gate.sh`; confirm deny = `jq -n` JSON + `exit 0`.
- [ ] 0.3 Confirmed: `scripts/test-all.sh:316` auto-globs BOTH `plugins/soleur/test/*.test.sh` and `.claude/hooks/*.test.sh`.
- [ ] 0.4 Read `plugins/soleur/test/gitleaks-merge-commit.test.sh` header — the #6727 mutation-proof discipline.
- [ ] 0.5 Confirm `emit_incident`'s 6th arg (`kind`) accepts an arbitrary value, and that the weekly aggregator will not silently ignore an unknown `kind` (rows written but never read).
- [ ] 0.6 Confirm no validator rejects ADR `status: proposed`.
- [ ] 0.7 Re-verify next free ADR ordinal against `origin/main` (ADR-130 provisional).

## Phase 1 — Gate script (contract; ships FIRST)

- [ ] 1.1 **RED** — write `plugins/soleur/test/net-issue-flow.test.sh` before the script.
- [ ] 1.2 Create `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`; `set -uo pipefail`, `export LC_ALL=C`, header documenting stdout contract + exit policy.
- [ ] 1.3 CLOSING: keep regex `(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+`, `sort -u`.
- [ ] 1.4 FILED — **all four together**: (a) drop `--label deferred-scope-out`; (b) `--state open` → `--state all`; (c) **add `--limit 500`** (default 30 — the most dangerous defect found in review); (d) full ISO `PR_CREATED_AT`, **no `cut -c1-10`**.
- [ ] 1.5 Body filter: numeric-boundary bare reference `(^|[^0-9A-Za-z])#<PR>([^0-9]|$)` — **not** the `(Ref|Closes|Fixes)` keyword form (40% coverage, measured).
- [ ] 1.6 Override: `grep -qF '<!-- gate-override: net-issue-flow -->'` + `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1`.
- [ ] 1.7 Exit 1 when `NET > 0` and no override; else 0. **Fail-open** on gh error / unreadable body.
- [ ] 1.8 `emit_incident net-issue-flow transient …` on every fail-open path; one retry with backoff first (`--search` = Search API, 30 req/min).
- [ ] 1.9 Display block enumerates the actual issue numbers behind CLOSING and FILED.
- [ ] 1.10 **GREEN** — `bash plugins/soleur/test/net-issue-flow.test.sh`.

## Phase 2 — PreToolUse hook (lands INERT — not registered here)

- [ ] 2.1 **RED** — `.claude/hooks/ship-net-issue-flow-gate.test.sh` using the `ship-unpushed-commits-gate.test.sh` `assert_deny` / `assert_pass` harness.
- [ ] 2.2 Create `.claude/hooks/ship-net-issue-flow-gate.sh`. **Delegate to the Phase 1 script — do not re-implement.**
- [ ] 2.3 Command regex **widened to `gh\s+pr\s+(ready|merge)`** — the soak gate's `merge\s+.*--auto` form misses `--squash` (merge queue) and `--admin`.
- [ ] 2.4 Path via `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"`, **not** payload `.cwd`.
- [ ] 2.5 Wrap the delegated call in `timeout 8`.
- [ ] 2.6 Deny: `emit_incident` + `jq -n` `permissionDecision: "deny"` + `exit 0`. Reason offers 3 remedies.
- [ ] 2.7 Document in `.claude/hooks/README.md`.
- [ ] 2.8 **GREEN**. Hook stays unregistered until Phase 8.6.

## Phase 3 — SKILL.md prose (consumer)

- [ ] 3.1 Retitle `### Net-Issue-Flow Surfacing (advisory)` → `### Net-Issue-Flow Gate (blocking)`.
- [ ] 3.2 Replace inline bash with a markdown link to `./scripts/net-issue-flow.sh`.
- [ ] 3.3 Delete every "advisory" / "does NOT block" statement (~481, ~543, ~549) incl. the "Why advisory (not blocking)" paragraph.
- [ ] 3.4 Document override marker + env var, and the honest reachability table (which merge surfaces the hook does NOT cover).

## Phase 4 — Cost-of-filing threshold + instrumentation

- [ ] 4.1 Sweep every site (map: `review/SKILL.md` 496, 500, 507, 509, 513, 532, 740, 750, 1055; `review/workflows/review.workflow.js:279`; `ship/SKILL.md:539`; `work/SKILL.md:887`; `compound/SKILL.md:79`). **The grep is the enumerator, not this list.**
- [ ] 4.2 Cover hyphenated + `>` forms (`≤30-line`, `>30 lines`, `≤2-file`, `>2 files`).
- [ ] 4.3 Restate the bookkeeping-vs-edit arithmetic at `review/SKILL.md:500` — it changes at 100 lines.
- [ ] 4.4 Add `emit_incident cost-of-filing "$DISPOSITION" ... cost_of_filing` (`flip`|`file`) **in `review.workflow.js`**, not SKILL.md prose.
- [ ] 4.5 Verify: `git grep -nE '(≤|>) ?30[ -]?line|(≤|>) ?2[ -]?file' -- plugins/soleur/skills/` → 0.

## Phase 5 — action-required sink (#6769)

- [ ] 5.1 Add `--assignee "${OPERATOR_GH_LOGIN}"` to **both** `gh issue create` arms in `operator-digest/assets/operator-digest.workflow.yml:94-100`. **Do NOT call the subscription API** — token lacks `notifications` (measured).
- [ ] 5.2 `operator-digest/SKILL.md` §4: add `createdAt,labels`; sort age-desc; render `(NNN days old)`; band >90d / 30-90d / <30d. **SLA arm only — no auto-close.**
- [ ] 5.3 Exclude `decision-challenge` from the action-needed harvest; render separately (never drop).
- [ ] 5.4 Record the retain-not-retire decision in ADR-130 + PR body.
- [ ] 5.5 Route the one-time optional watch subscription through the deferred-operator-step path.

## Phase 6 — ADR + C4

- [ ] 6.1 Write `ADR-130-gate-moratorium.md`, `status: proposed`: argument + counter-argument + synthesis. Decides nothing.
- [ ] 6.2 Fold the D4 meta-work drain-window proposal into ADR-130 as its second proposed policy. **Do NOT create `decision-challenges.md`** — `ship/SKILL.md:1299` would file an issue from it and trip AC16.
- [ ] 6.3 Record the two plan-review dissents (cut-the-ADR; swap-the-metric) in ADR-130's operator-decision section.
- [ ] 6.4 Add the `github -> founder` digest-delivery relationship to `model.c4`. No `views.c4` edit needed.
- [ ] 6.5 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 7 — Follow-through enrollment (fail-closed at /ship)

- [ ] 7.1 `scripts/followthroughs/filed-per-pr-soak-6769.sh`; exit 0=PASS / 1=FAIL / *=TRANSIENT. **Two criteria:** (a) filed-per-PR ≤ 0.95 over PR-attributable filings; (b) total open issue count at merge+14d ≤ count at merge.
- [ ] 7.2 Directive on #6769: `<!-- soleur:followthrough script=scripts/followthroughs/filed-per-pr-soak-6769.sh earliest=<merge+14d> secrets=GH_TOKEN -->` + `follow-through` label.
- [ ] 7.3 `GH_TOKEN` already wired at `scheduled-followthrough-sweeper.yml:56` — no new secret.

## Phase 8 — Mutation evidence, THEN registration

- [ ] 8.1 Build a synthetic `NET = +3` PR body.
- [ ] 8.2 Run the gate; **capture the verbatim failing output**.
- [ ] 8.3 Add the override marker; re-run; capture the passing output.
- [ ] 8.4 Commit both to `specs/<branch>/mutation-evidence.md` (#6727 convention).
- [ ] 8.5 Cite it in the PR body.
- [ ] 8.6 **ONLY NOW** register the hook in `.claude/settings.json` after `ship-soak-followthrough-gate.sh`. Flag the config change in the PR body. (Registering earlier would run Phases 3–7 under a live unproven gate that this PR must itself pass.)

## Phase 9 — Exit

- [ ] 9.1 `bash scripts/test-all.sh` green.
- [ ] 9.2 Verify AC16: this PR's own NET ≤ 0, no override marker present.
- [ ] 9.3 Confirm zero issues filed by this PR.
