---
title: "fix: GitHub community-monitor collector data gaps (E2BIG + stderr poisoning + fabricated stats)"
date: 2026-07-19
type: fix
lane: cross-domain
issue: 6695
brand_survival_threshold: none
status: draft
revision: v3 (post silent-failure review — D5 rebuilt as a deterministic sidecar; see Review Reconciliation)
---

# fix: GitHub community-monitor collector data gaps

Ref #6695 (scheduled digest issue — reference, do not auto-close; its Discord/X/Bluesky/
LinkedIn/HN content is unrelated to this fix).

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-6695-github-collector-data-gaps/` directory exists.

> **Citation convention:** this plan cites **content anchors**, not line numbers
> (`cq-cite-content-anchor-not-line-number`). v1 already carried two drifted line cites.

## Enhancement Summary

**Deepened on:** 2026-07-19 · **Passes:** plan-review panel (advisor `fable` + simplicity +
correctness), silent-failure review, halt gates 4.6–4.9, learnings sweep, sibling sweep,
verify-the-negative.

### Key improvements

1. **The fix now actually closes the hole it targets (v3).** v2's monitored signal rested on
   `resolveOutputAwareOk`, which — read end-to-end — is a presence-only check that returns GREEN
   for both the fabrication and the honest-failure path. As specified, a collector failure would
   have stayed **100 % invisible to Sentry**. Replaced by a deterministic collector-status
   sidecar with no LLM in the path, plus a real fabrication detector (D5b).
2. **Scope cut ~55 % (v2).** Pagination (RC4) and the `days` change (RC5) were removed after
   measurement at the *production* window (`days=1`) showed no truncation occurs. v1's
   "-87 % undercount" was measured at `days=41` and was the load-bearing argument for both.
3. **Three would-be regressions caught before implementation.** v1's `2>&1` sweep would have
   broken `cmd_discussions`' graceful path and blanked five error diagnostics; v1's AC3
   (`grep -c '2>&1'` → 0) *mandated* that regression; and v2's D7 wording would have leaked a
   tempfile on every run (EXIT traps are singular — the second replaces the first).
4. **Prior art reconciled.** This bug class was solved twice here; the 2026-03-28 learning's
   wrong threshold model (`ARG_MAX` vs `MAX_ARG_STRLEN`) is *why* the fix was never
   back-propagated. Correcting it is in scope.
5. ~~**Scope claim verified, not asserted.**~~ **This was itself unverified — see the
   correction in Sibling sweep.** The sweep ran the right grep and then under-reported
   its own output by two sites, one of which (`scripts/compound-promote.sh`) was already
   broken at 8.2× the ceiling. Fixed in this PR; the at-risk second site is a follow-up.
6. **Every verification command was executed** against the current tree and its expected value
   recorded — including a reviewer-suggested fix that turned out to be buggy itself. v1's ACs
   were written but never run; that was v1's defining failure.

### New considerations discovered

- The binding limit is **`MAX_ARG_STRLEN` (128 KB/arg)**, not `ARG_MAX` (2 MB) — the defect
  fires on **10 commits**, which is why it recurs every run.
- **Every signal v2 created terminated in the LLM's context window.** The collector runs as a
  Bash tool call inside the spawned `claude`; its stderr never reaches `spawnResult.stderrTail`.
- `--slurpfile`'s dangerous failure is **partial** unwrapping (`count: 1` with a full items
  array, exit 0) — not the full non-unwrap, which errors loudly.
- An exit-0 error body (404/403/410) renders `new_stargazers_count: 0`, indistinguishable from a
  quiet day. `check_rate_limit` matches only `rate limit`.
- `make_gh_stub` handles only `gh run list` — the test foundation was asserted, not designed.
- Halt gate 4.6 correctly rejected the draft: `apps/web-platform/server/` is a sensitive path.
- An unrelated `/tmp` leak (9,470 files, 1.9 GB) filled the tmpfs mid-session — separate follow-up.

## Overview

Three reported failures, all reproduced live. The fix is small and mechanical:
**two `--argjson` call sites, one `2>&1`, and one prompt contradiction.**

### Root causes (reproduced at the *production* configuration)

The cron invokes every GitHub subcommand with **`days=1`** (`cron-community-monitor.ts`,
anchor `bash plugins/soleur/skills/community/scripts/community-router.sh github activity 1`),
daily at 08:00 UTC. All measurements below are at `days=1`.

| # | Defect | Mechanism | Evidence |
|---|---|---|---|
| RC1 | `activity` + `contributors` die with "Argument list too long" | jq `--argjson` places the whole payload in **one `execve` argument**. The binding limit is **`MAX_ARG_STRLEN` = 131,072 B *per argument*** (32 × 4096-B pages) — **not** `ARG_MAX` (2,097,152 B) | Bisected: 131,071 → OK, 131,072 → E2BIG. At `days=1`: commits = **142,236 B** in one arg (only **10 items**); issues = **448,247 B** (**56 items**) |
| RC2 | `repo-stats` "stargazer parse error" | `cmd_repo_stats` pipes `gh api … 2>&1` into `jq -s`, merging **stderr into the JSON stream**; any stderr byte poisons the parse | `( echo '[{"a":1}]'; echo noise >&2 ) 2>&1 \| jq -s 'add // []'` → `parse error`, exit **5** |
| RC3 | Digest printed stale stars/forks/watchers "(stale)" and claimed a 41-day period | **No code or prose authorizes either.** The script exits loudly; the LLM filled a *mandatory* table from a 6-week-old digest and invented a period | Prompt anchor `The ## GitHub Activity section must include` has no failure clause; LinkedIn's `To distinguish` anchor does. Anchor `If any command in a batch fails, log the error and continue.` grants the standing permission |

**RC1 is driven by per-object payload size, not item count** — 10 commits already breach the
128 KB per-argument ceiling. That is why the failure is deterministic and recurring
(16 digests mention a GitHub gap), and why item-count pagination is orthogonal to it.

## Review Reconciliation — v1 → v2

Plan review (advisor + simplicity + correctness panels) overturned v1's central scope
argument. Each finding below was **independently verified** before being accepted or rejected.

| v1 claim | Verification | v2 response |
|---|---|---|
| "A jq-only fix yields a silent 87 % undercount (100 vs 768 commits)" — used to justify adding pagination | **Wrong.** The 768/741 figures were measured at `days=41`; production is `days=1`, where the endpoints return **10 commits / 56 issues / 14 in-window PRs** — all far under the 100 cap. v1's own `days=1` measurement showed 10 and 56 and was not reconciled | **RC4 (full pagination) cut.** Replaced by a 3-line cap-detection guard (D2) that makes a *future* truncation loud instead of engineering around one that does not occur |
| "Raise `days` from 1" (RC5) | **Wrong and self-contradictory.** `days=1` is correct for a daily cron. The 41-day claim is RC3's fabrication class, not config drift. v1 named no target value because none is defensible | **RC5 cut.** Replaced by D4b: the digest must echo `period_days` from collector JSON instead of inventing a window |
| AC3: `grep -c '2>&1'` → **0** | **Unachievable and harmful.** True count is **9**; two are legitimate `>/dev/null 2>&1` discard idioms in `validate_gh`, and the `cmd_discussions` site is load-bearing for its graceful "Discussions not enabled" path | Rewritten as a form-anchored AC scoped to the actual defect shape (`gh api … 2>&1` feeding a pipe). **Only the `repo-stats` site changes** |
| "Sweep `2>&1` → `2>/dev/null` at 7 sites" | **Would destroy every error message.** Those sites use the captured stderr as the diagnostic (`$(echo "$issues" \| head -c 200)`), and it directly contradicts D3's `…_CAUSE=` requirement | **Separate-stderr-tempfile shape (D3)** adopted and stated explicitly. Note this means Precedent A is *not* lifted verbatim — it throws stderr away, a defect to fix while lifting |
| "Tests stub `gh` per `make_gh_stub`" | **Unusable.** `test-helpers.sh` `make_gh_stub` handles **only `gh run list`**; every `gh api`/`gh auth status` call hits its `exit 1`. v1's Phase 0 precondition was vacuous | New `make_gh_api_stub` is an explicit **deliverable** in Files to Edit |
| D1 `--slurpfile` is a drop-in swap | **Not a drop-in.** `--slurpfile x f` wraps file contents in an array, so `$x` is `[[…]]` and every `$issues[]` / `$commits[]` reference must become `$issues[0][]` | Unwrapping shape pinned explicitly (D1) |
| D5 layer 3 "wire `reportSilentFallback`" | **Vague; collector runs in the agent sandbox**, so its exit code never reaches the handler | v2 rebuilt it on `resolveOutputAwareOk` — **also wrong; see the v2 → v3 table below** |
| AC2 expected output ("`$repo`, `$since`, `$days` scalars") | **Wrong** — `$repo`/`$since` use `--arg`, not `--argjson` | AC rewritten as a mechanical count |
| v1 line-number cites for the prompt (`:205-208`, `:214-216`) | **Already drifted** — actual anchors are at 202 and 212 | All cites converted to content anchors |
| AC2 regex won't match continuation lines | **Rejected — the regex is correct.** `grep -nE '^\s*--argjson'` matches all 7 sites (4-space indent). Portability note adopted: use `^[[:space:]]*` | Kept, with the POSIX class |
| Auto-glob claim, all seven `2>&1` line numbers, Precedent A, latent `rm -f` leak, D-shape assertion precedent, router passthrough | **All verified correct** | Retained |

## Review Reconciliation — v2 → v3

A silent-failure review read `resolveOutputAwareOk` end-to-end (the one mechanism v2 admitted it
had **not** read, and gated Phase 0 on). Its verdict: **every failure signal v2 created
terminates at the LLM.** Each finding below was independently re-verified before acceptance.

| v2 claim | Verification | v3 response |
|---|---|---|
| D5: treat "digest contains `collection failed:`" as a non-ok condition inside `resolveOutputAwareOk` | **Not expressible.** `verifyScheduledIssueCreated` requests only `labels`/`since`/`sort`/`per_page` and returns `issues.some(i => updated_at >= sinceMs)` — a pure presence check. Never reads the issue body or the digest. Fabrication and honest-failure paths **both return GREEN** | **D5 replaced** by a machine-readable collector-status sidecar. A collector failure would otherwise have stayed 100 % invisible to Sentry — the fix would have *relocated* the hole |
| D2: cap warning routed `stderr → digest → heartbeat` | **Every hop broken.** Collector stderr is captured by the Bash tool into the model's context, never reaching `spawnResult.stderrTail`; no prompt edit asks the LLM to surface it; and the heartbeat hop does not exist | D2 rerouted through the sidecar, **or cut** — an unread warning plus an overstating Observability block is worse than no D2 |
| RC3 fixed by prompt edits alone | **No deterministic check exists.** AC8 verifies the instruction was *written*, not obeyed. Every v2 AC was satisfiable by a run that fabricated every number | **D5b fabrication detector added** — collector `exit != 0` + a Repository Stats number in the digest → Sentry + RED |
| AC1 "emit non-empty JSON" catches the `--slurpfile` hazard (per the Risks table) | **Contradiction.** AC1 had no count assertion; `count: 1` *is* non-empty JSON at exit 0. Worse, the silent shape is **partial** unwrapping — verified `{"count":1,"items":[…3 items…]}`, exit 0 | AC1 rewritten to assert `count == (items|length)` |
| Test 3.1 covers the large-payload path | **One binding of five**, across three commands. `prs` mis-unwrapped while `issues` is correct yields a partially-correct digest — the hardest thing for an operator to notice | Test 1 made parametric over all three commands / five bindings |
| D6 shape assertion scoped to `$repo_data` | **Leaves a live hole.** A 404/403/410 body reaches jq as an object; `check_rate_limit` matches only `rate limit`; `$stargazers` unguarded ⇒ `new_stargazers_count: 0` reads as a quiet day | D6 extended to every fetch site via `check_array_response` |
| D7 "every tempfile uses `trap … EXIT`" | **Itself a leak.** EXIT traps are global and singular — the second `trap` replaces the first. Verified: two naive traps → **1 file leaked** | D7 rewritten: **one** trap listing all files |
| *(reviewer's own suggested `_mktemp` accumulator helper)* | **Rejected — also buggy.** The array append happens inside `$( )`, so the parent's array is empty. Verified: array size **0**, **2** files leaked | Plan pins the verified-correct shapes instead |
| AC3 `grep -Pzoc` presented as a count | **It is boolean** (`-z` makes the whole file one record; `-o` is inert with `-c`) | Documented; adequate for `1 → 0` but noted as unable to detect a *second* new instance |

**What the review affirmed:** the RC1 bisection, the v1→v2 scope cut, D4c (amend the
contradicting instruction rather than append), and the AC2/AC3 counter-assertions guarding
`cmd_discussions` and `validate_gh`.

## Verified design decisions

**D1 — `--slurpfile` over `--argjson`, with the unwrapping shape pinned.** Verified to 10 MB
(`jq-1.8.1`). Reads via a file descriptor, so no `execve` argument is involved and the 128 KB
ceiling does not apply. **`--slurpfile x f` wraps the file's contents in an array**, so the jq
program must dereference `$x[0]`, or the file must be written pre-merged. Choose one shape and
apply it consistently — every `$issues[]`, `$prs[]`, `$commits[]`, `$stargazers[]` reference in
the affected jq programs changes. Getting this wrong yields a silent `count: 1`.

**D2 — Cap detection, routed through the D5 sidecar (not stderr).** Full pagination is
unjustified (see Review Reconciliation), but the 100-item cap is a *latent* silent undercount if
the repo grows or a run covers a longer window. After each fetch, if the response returns
**exactly `per_page` items**, record it.

> **v2 routed this warning to stderr. That was theater.** Per D5, collector stderr terminates in
> the LLM's context; nothing in the D4 prompt edits asks the LLM to surface a truncation notice,
> and a cap warning is not even a *failure*, so the standing `log the error and continue`
> instruction gives it no reason to. v2's Observability block claimed the route
> `stderr → digest → heartbeat`; **every hop of that route was broken.** An inaccurate
> observability claim is worse than an acknowledged gap, because the next responder trusts it.

The warning is emitted as a `warn` field on the D5 status record
(`{"collector":"github","command":"activity","warn":"truncated_at_per_page"}`), which reaches
Sentry deterministically. **If the sidecar is descoped, D2 must be cut too** — an unread warning
plus an Observability block that overstates it is worse than no D2 at all
(`cq-silent-fallback-must-mirror-to-sentry`, `hr-observability-layer-citation`).

**D3 — Separate stderr capture (supersedes a blanket `2>&1` sweep).** The defect is *stderr
merged into a JSON pipe*, not stderr capture per se. Fix the shape, preserving diagnostics:

```bash
if ! gh api "…" >"$out" 2>"$err"; then
  echo "GITHUB_COLLECTOR_CAUSE=$(head -c 200 "$err" | tr '\n' ' ')" >&2
```

**Only the `repo-stats` stargazer site changes.** The `validate_gh` `>/dev/null 2>&1` idioms
and the `cmd_discussions` error-classification capture are correct and stay. Note Precedent A
(`cmd_fetch_interactions`) discards stderr and prints a contentless error — lifting it verbatim
would propagate a diagnosability defect, so it is lifted *with* this improvement.

**D4 — Fix RC3 at the prompt layer, where the defect actually lives.**
(a) Give the GitHub section a failure clause mirroring the LinkedIn one that demonstrably
works (anchor `To distinguish`): require `collection failed: <reason>` and **forbid
carry-forward from a prior digest**.
(b) Require `period_days` to be stated **from the collector JSON**, never inferred.
(c) **Amend the standing permission** (anchor `If any command in a batch fails, log the error
and continue.`). Appending a failure clause without amending this leaves two contradictory
instructions and the LLM will keep resolving toward the vaguer one — the single most likely
way this fix silently fails.

**D5 — Collector-status sidecar (deterministic signal, no LLM in the path).**

> **v2's D5 was wrong and is replaced.** v2 proposed treating "digest contains
> `collection failed:`" as a non-ok condition inside the existing `resolveOutputAwareOk`
> verify-output step, and gated Phase 0 on reading that mechanism. It has now been read
> end-to-end (`_cron-shared.ts`, `verifyScheduledIssueCreated`): it issues
> `GET /repos/{owner}/{repo}/issues` with only `labels`/`since`/`sort`/`per_page` and returns
> `issues.some(i => new Date(i.updated_at).getTime() >= sinceMs)` — a **pure presence check on
> `updated_at`**. It never reads the issue body, never reads the digest, and exposes no
> content-predicate parameter. Both RC3 outcomes therefore terminate identically:
>
> | Path | Issue filed? | `resolveOutputAwareOk` | Heartbeat |
> |---|---|---|---|
> | LLM fabricates stars | yes | `true` | **GREEN** |
> | LLM honestly writes `collection failed:` | yes | `true` | **GREEN** |
>
> Shipped as v2 specified, **a collector failure would still be 100 % invisible to Sentry** —
> the fix would have relocated the silent-fallback hole, not closed it.

The root problem is that *every* signal v2 created (D2's cap warning, D3's
`GITHUB_COLLECTOR_CAUSE=`, D4's `collection failed:` line) terminates in **the LLM's context
window**. The collector runs as a `Bash` tool call *inside* the spawned `claude`; its stderr is
captured by the Bash tool, not by the `claude` process's own `child.stderr`, so it never reaches
`spawnResult.stderrTail` either.

**Fix: a machine-readable status sidecar that bypasses the LLM entirely.** The collector appends
one JSONL record per invocation (success *and* failure) to a path given by an env var; the
handler reads it from `spawnCwd` before teardown:

```bash
# github-community.sh — emitted on every dispatch, success or failure
_record_status() {   # $1=command  $2=exit  $3=cause
  [[ -n "${SOLEUR_COLLECTOR_STATUS_DIR:-}" ]] || return 0
  mkdir -p "$SOLEUR_COLLECTOR_STATUS_DIR"
  jq -nc --arg c "$1" --argjson e "$2" --arg r "${3:-}" \
    '{collector:"github",command:$c,exit:$e,cause:$r}' \
    >> "$SOLEUR_COLLECTOR_STATUS_DIR/collector-status.jsonl"
}
```

Handler: any record with `exit != 0` → `reportSilentFallback` **and** force `heartbeatOk = false`.
The status file is written outside `COMMUNITY_MONITOR_ALLOWED_PATHS` and is never committed —
the handler reads it directly from `spawnCwd`.

**M4 — do not inherit the verify-output fail-open.** `resolveOutputAwareOk`'s `catch` branch
returns `spawnOk` when the GitHub verify-read throws (a deliberate fail-open, tracked in #5139).
Set `heartbeatOk = false` from the collector status **independently** of that return value, and
emit `reportSilentFallback` unconditionally rather than only when the heartbeat goes red — the
Sentry report is the durable record; the heartbeat is the page.

**D5b — Deterministic fabrication detector (closes RC3 for real).** D4's prompt edits are a
probability shift, not an enforcement mechanism, and every v2 acceptance criterion was
satisfiable by a run that fabricated every number. The sidecar makes a real check possible for
the first time — roughly ten lines on top of D5:

> collector recorded `repo-stats exit != 0` **AND** the digest contains a Repository Stats
> number → `reportSilentFallback` + heartbeat **RED**.

Without this, RC3 is discouraged, not fixed — and the `## User-Brand Impact` section names the
exact harm ("the operator makes positioning and prioritization calls on fabricated traction
data") while shipping no control against it. This is a gap, not an acceptable residual.

**D6 — Shape assertion at *every* fetch site, not just `repo_data`.** Adopt the
`linkedin-community.sh` precedent (anchor `Shape validation BEFORE any`).

> **v2 scoped this to `$repo_data` only, leaving a live exit-0-with-error-body hole.**
> `check_rate_limit` matches only `.message` containing `rate limit`. A `404 Not Found`,
> `403 SAML enforcement`, or `410 Gone` body reaches jq as
> `{"message":"Not Found","documentation_url":…}`. On the stargazer path, `jq -s 'add // []'`
> over a single-object slurp yields that object, `check_rate_limit` does not match it, and
> `$stargazers` is unguarded — so `new_stargazers_count` renders a plausible **`0`** and the
> digest reports "0 new stargazers this period", indistinguishable from a genuine quiet day.

Close the whole class in one helper rather than one assertion per site:

```bash
check_array_response() {   # $1=payload  $2=what
  if ! echo "$1" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "GITHUB_COLLECTOR_CAUSE=$2 returned non-array: $(echo "$1" | jq -r '.message // "unknown"' 2>/dev/null | head -c 200)" >&2
    exit 1
  fi
}
```

Keep the `(.stargazers_count | type) == "number"` assertion on `$repo_data` (an object, not an
array) as the object-shaped counterpart.

**D7 — ONE `trap` listing every tempfile — not one trap per file.**

> **v2's wording ("Every tempfile uses `trap 'rm -f …' EXIT`") was itself a leak.** Bash EXIT
> traps are **global and singular**: a second `trap … EXIT` *replaces* the first.
> `cmd_activity` and `cmd_contributors` each need two tempfiles under D1, so the naive form
> silently leaks the first one on **every** run — reintroducing the exact `/tmp`-exhaustion
> class D7 exists to prevent. Verified: two naive traps → **1 file leaked**.

Verified-correct shape (register all files in a single trap):

```bash
a=$(mktemp); b=$(mktemp)
trap 'rm -f "$a" "$b"' EXIT     # ONE trap, all files -> 0 leaked (verified)
```

A parent-scope array (`_T+=("$f")` appended **outside** any command substitution, with
`trap 'rm -f "${_T[@]:-}"' EXIT`) also works and scales. **Do not** use a `_mktemp()` helper
that appends to the array and returns the path via `$( )` — the append happens in a subshell
and is lost, so the parent's array is empty and every file leaks. Verified: that shape reports
array size **0** and leaks **2**.

**`EXIT`, never `RETURN`** — a `RETURN` trap does not fire on `exit`, so the `exit 1` failure
branches leak the spool. Verified: `RETURN` leaked 1, `EXIT` leaked 0.

Motivation: during planning `/tmp` hit 100 % (4 GB) and broke tool output — **9,470 leaked
`mktemp` files (1.9 GB)** from `workspaces-luks-freeze.test.sh`. Unrelated to #6695, but a
first-hand demonstration. `cmd_fetch_interactions` carries the same latent flaw (`rm -f` on
success paths only) and is fixed while in the file.

## Research Insights (deepen-plan)

### Prior art — and the factual error that made the first fix incomplete

**This exact bug class was already solved in this repo, twice**, and the collector still carries it:

- [`2026-03-28-gh-api-paginate-argument-list-too-long.md`](../../project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md)
  fixed `cmd_fetch_interactions` in **this very file** (it is Precedent A) — but attributed the
  limit to **`ARG_MAX` (~2 MB)** and concluded: *"The existing `cmd_repo_stats()` uses
  `--argjson` for stargazers: **This works because stargazers are small**."*
- [`2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md`](../../project/learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md)
  (#5523/#5528) got it right: **`MAX_ARG_STRLEN` ≈ 128 KB — NOT `getconf ARG_MAX` 2 MB, which is
  the total envp+argv ceiling.** My independent bisection (131,071 → OK, 131,072 → E2BIG)
  reproduces this exactly.

**The 2026-03-28 learning's wrong threshold model is *why* the fix was never back-propagated.**
Judged against a 2 MB ceiling, the sibling call sites look safe; judged against the real 128 KB
per-argument ceiling, `cmd_activity` and `cmd_contributors` were already over it. The
`2026-03-28` file should be corrected as part of this work — leaving it encodes the model that
caused the incomplete fix. *(Note the second learning's Solution section already cites
`github-community.sh:294` as its pattern precedent — the repo has been circling this file.)*

### Sibling sweep — scope claim verified, not assumed

The 2026-06-18 learning's Key Insight is that *"X is unaffected" is a hypothesis, not a fact* —
grep the byte-identical idiom across siblings before trusting scope. Executed:

```bash
for f in plugins/soleur/skills/community/scripts/*.sh; do grep -nE '^[[:space:]]*--argjson' "$f"; done
grep -rnE '\-\-argjson [a-z_]+ "\$' --include=*.sh . | grep -v node_modules
```

| Site | Payload | Verdict |
|---|---|---|
| `github-community.sh` ×7 | issues / prs / commits / stargazers | **Defect — in scope** (5 unbounded) |
| `bsky-community.sh` `--argjson record` | one post record | Bounded — safe |
| `linkedin-community.sh` `total_followers`, `share_statistics` | scalar + one stats object | Bounded — safe |
| `linkedin-setup.sh` ×3 | scalars | Bounded — safe |
| `scripts/skill-freshness-aggregate.sh` `inventory_json`, `invocations_json` | ~90 skill **names**; `group_by(.skill)`-aggregated to one record per skill | Bounded **by skill count, not log size** — safe |
| `scripts/audit-bot-codeql-coverage.sh` accumulator | payload arrives via `printf … \| jq` (**stdin**); only scalars on argv | Safe by construction |

> **CORRECTED AT REVIEW (this claim was false).** The table above is a partial
> transcription of the grep's own output. The sweep omitted two hits and then
> declared the scope "verified" — reproducing, one paragraph after citing it,
> the exact failure the 2026-06-18 learning exists to prevent. The methodology
> was right; the transcription was not.
>
> | Omitted site | Measured | Status |
> |---|---|---|
> | `scripts/compound-promote.sh:186` `--argjson corpus "$CORPUS_JSON"` | **1,073,302 B** across 1,972 learning files — **8.2× the 131,072 B ceiling** | **ALREADY BROKEN.** Reproduced. Fixed in this PR: `CORPUS_NDJSON` was already a tempfile, so `--slurpfile` is a two-line drop-in (its 22-case suite still passes). The production path is unaffected — the runtime moved to `cron-compound-promote.ts`, which builds the payload in-process with `JSON.stringify` and has no argv limit. |
> | `scripts/domain-model-drift.sh:107` `--argjson facts` | ~72 KB, ~55 % of ceiling | **At risk, not broken.** Filed as **#6720** rather than fixed here: there is no existing tempfile to slurp, so the fix is a spool restructure plus a cap decision, not a binding swap. |
>
> **Result: two siblings shared the defect, one of them live.** The corrected
> claim is that no *community collector* sibling shares it — `bsky`, `linkedin`,
> and `linkedin-setup` bind genuinely bounded payloads, which the table's
> per-site reasoning does establish.

### Implementation details lifted from the prior fix

- **`trap … EXIT`, never `RETURN`** — a `RETURN` trap does not fire on `exit`, so the `exit 1`
  failure branches would leak the spool file. This is the concrete form D7 requires.
  *Independently re-verified at deepen time (not taken on the learning's word): a function with
  `trap … RETURN` hitting `exit 1` leaked **1** file; the identical function with `trap … EXIT`
  leaked **0**.*
- **Spool + single post-loop collapse** — `mktemp` spool then one `jq -s 'add // []'`; file I/O
  has no argv size limit.

### Hazard for this plan's own ACs (from the prior fix's session errors)

The 2026-06-18 work hit a **structural-guard grep that matched its own explanatory comment** — a
guard grepping for a forbidden literal FAILed because a comment *describing* the old form
contained that literal. **AC2 and AC3 grep for `--argjson` and `2>&1` in the script and are
directly exposed to this.** Implementation constraint: when documenting the change, **never
write the forbidden literal in a comment in the same file** — say "the old per-page argjson
accumulation", not the literal token. See
[`2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`](../../project/learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md).

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/community/scripts/github-community.sh` | RC1: tempfile + `--slurpfile` at the **5 unbounded bindings** — `issues`+`prs` (`cmd_activity`), `commits`+`issues` (`cmd_contributors`), `stargazers` (`cmd_repo_stats`) (D1). RC2: separate-stderr shape at the **stargazer fetch only** (D3). D2 cap detection, D6 shape assertion, D7 traps (incl. the existing `cmd_fetch_interactions` leak). `repo_data` + `days` stay `--argjson` (bounded) |
| `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` | D4a/b/c prompt edits at the three content anchors; D5 output-aware failure signal |
| `plugins/soleur/test/test-helpers.sh` | **New `make_gh_api_stub`** — dispatches on `$1 == "api"` by URL substring; handles `auth status` → exit 0; **three required modes**: (a) large valid payload, (b) valid stdout + stderr noise, (c) **exit 0 with an error JSON body** (`{"message":"Not Found"}`). Mode (c) exercises the exit-0-error-body path. (It was originally justified as "what makes H3 testable"; H3's premise is retracted — see Work-Phase Corrections — but the mode is still needed, since that body must produce a *named cause* rather than an opaque jq error.) Shared by ~21 suites, so additive only |
| `knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md` | **Correct the threshold model.** It attributes the limit to `ARG_MAX` (~2 MB) and concludes the sibling `--argjson` sites are safe "because stargazers are small". The real ceiling is `MAX_ARG_STRLEN` (131,072 B **per argument**). That error is why this fix was never back-propagated — leaving it uncorrected reproduces the incomplete fix |

## Files to Create

| File | Purpose |
|---|---|
| `plugins/soleur/skills/community/test/github-community.test.sh` | Regression suite. Auto-globbed by `scripts/test-all.sh` (`plugins/soleur/skills/*/test/*.test.sh` in the `want_scripts` loop) — **verified, no manual registration** |

## Implementation Phases

Ordered by dependency: the script contract lands before its consumers.

### Phase 0 — Preconditions (verify, do not assume)

- Confirm `jq --version` ≥ 1.6 supports `--slurpfile` (verified `jq-1.8.1` locally).
- ~~Confirm the D5 extension point by reading `resolveOutputAwareOk`.~~ **Done at deepen time —
  it cannot express the condition** (presence-only check on `updated_at`). D5 is now the
  collector-status sidecar; no Phase 0 gate remains. Confirm instead that the handler can read a
  file from `spawnCwd` **before** `teardownEphemeralWorkspace`, and note that `safe-commit-pr` is
  gated on `if (heartbeatOk && !spawnResult.abortedByTimeout)` — so the sidecar read must not be
  placed behind that gate or it becomes unreachable on exactly the runs that matter.
- Re-run the RC1 and RC2 repros to establish a RED baseline before changing anything.

### Phase 1 — RED: regression tests first (`cq-write-failing-tests-before`)

Build `make_gh_api_stub`, then write three cases (fixtures **synthesized**, never captured —
`cq-test-fixtures-synthesized-only`). Set `TMPDIR` to a **private per-test directory** so the
cleanup assertions cannot false-fail on a shared `/tmp` (the D7 anecdote is exactly this hazard).

1. **Large payload (RC1) — parametric over all three commands.** Stub a payload exceeding
   **131,072 B** in a single argument. Assert exit 0 **and the `count == (items|length)`
   invariant** (AC1) for each. *Fails today with "Argument list too long."*
   **Must cover all five bindings** — `issues`+`prs` (`cmd_activity`), `commits`+`issues`
   (`cmd_contributors`), `stargazers` (`cmd_repo_stats`) — not one. Each carries an independent
   chance of the partial-unwrap mistake, and the nastiest uncovered case is `prs` mis-unwrapped
   while `issues` is correct: issue counts right, PR counts read `1`. A partially-correct digest
   is the hardest thing for an operator to notice — it looks exactly like a quiet day.
   AC2's `--slurpfile` count proves the *mechanism* was swapped at five sites; it proves nothing
   about whether the jq program was correspondingly rewritten at each.
2. **stderr noise on the stargazer path (RC2)** — stub valid JSON on stdout **and** noise on
   stderr. Assert `repo-stats` parses, and that the diagnostic still carries the cause (D3).
   *Fails today with `parse error`.*
3. **Exit-0-with-error-body (RC3/D6/H3)** — stub **exit 0** with `{"message":"Not Found",…}`.
   Assert non-zero exit and that **no numeric `stargazers_count` / `new_stargazers_count` is
   emitted**. Without this, the "0 new stargazers" fabrication path stays open.
4. **Multi-tempfile cleanup on a failure path (D7/M1)** — exercise a **two-tempfile** command
   (`activity` or `contributors`) with a forced mid-command failure; assert the private `TMPDIR`
   is empty. A single-tempfile test cannot detect the trap-replacement leak.
5. **Sidecar status record (D5)** — assert a JSONL record with the correct `exit` is appended for
   both a success and a failure invocation when `SOLEUR_COLLECTOR_STATUS_DIR` is set, and that
   nothing is written when it is unset.

Per `cq-assert-anchor-not-bare-token`, anchor on call-form/`^[[:space:]]*` and mutation-test
each assertion. **Mutation-testing happens at the end of Phase 2**, once there is a fix to break.

### Phase 2 — GREEN: script fixes

Apply D1, D2, D3, D6, D7 to `github-community.sh`. Then mutation-test the Phase 1 assertions.

### Phase 3 — Consumer wiring (after the contract exists)

`cron-community-monitor.ts`: D4a/b/c prompt edits (all three anchors — the amendment to the
standing permission is not optional), then the D5 signal.

### Phase 4 — Verify

Run all five subcommands against `jikig-ai/soleur` at `days=1` and confirm each returns real
data. Confirm `bash scripts/test-all.sh` (`TEST_GROUP=scripts`) is green.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `github activity 1`, `contributors 1`, `repo-stats 1` each exit 0 against the live repo
  **and satisfy the count/items internal-consistency invariant**. *(All three fail today.)*

  ```bash
  bash plugins/soleur/skills/community/scripts/community-router.sh github activity 1 \
    | jq -e '.issues.count == (.issues.items|length)
             and .pull_requests.count == (.pull_requests.items|length)
             and .issues.count > 0'
  ```

  **Why not "non-empty JSON":** v2's AC1 asserted only exit 0 + non-empty output, while the
  Risks table credited it with catching the `--slurpfile` hazard — it could not. The dangerous
  shape is **partial** unwrapping (projection fixed, `length` left as-is), which is **silent**:
  verified `{"count": 1, "items": [ …3 full items… ]}` at exit 0. (Full non-unwrapping is
  comparatively safe — jq hard-errors on `.number` against an array.) Partial is also the
  *likelier* mistake, because five bindings are being rewritten by hand across three functions.
  `count == (items|length)` catches it at every site with one assertion and no fixture coupling.
- **AC2** No `--argjson` receives an unbounded payload. The five unbounded bindings
  (`issues` ×2, `prs`, `commits`, `stargazers`) must use `--slurpfile`; the two **bounded**
  ones may remain `--argjson` (`days`, a scalar; `repo_data`, a single repo object measured at
  **7,013 B** against the 131,072 B ceiling). Verify:

  ```bash
  S=plugins/soleur/skills/community/scripts/github-community.sh
  grep -cE '^[[:space:]]*--argjson (issues|prs|commits|stargazers)' "$S"   # 5 today -> 0
  grep -c -- '--slurpfile' "$S"                                            # 0 today -> 5
  ```

  *Executed at plan time: **5** and **0** respectively.* Do **not** assert a bare
  `grep -c -- '--argjson'` total — `repo_data` and `days` are legitimately bounded, so a
  fixed total would false-fail a correct implementation. (`$repo`/`$since` use `--arg` and are
  unaffected either way.)
- **AC3** No `gh api` call merges stderr into a pipe feeding `jq`. The defect **spans three
  lines**, so a line-oriented grep cannot see it — the check must be multiline-aware. Verify:

  ```bash
  grep -Pzoc '(?s)gh api[^)]*?2>&1[^)]*?\| *jq' \
    plugins/soleur/skills/community/scripts/github-community.sh   # 1 today -> 0 after fix
  ```

  *Executed at plan time: returns **1**, matching only the stargazer site.* (Requires GNU
  `grep -P`; the portable fallback is
  `awk '/stargazers=\$\(gh api/,/jq -s/' "$S" | grep -c '2>&1'`, also verified → **1**.)

  **Caveat:** `grep -Pzoc` is a **boolean, not a count** — `-z` treats the whole file as one
  record (and `-o` is inert alongside `-c`), so it can only ever return `0` or `1`. That is
  adequate for the `1 → 0` transition asserted here, but it **cannot detect a newly-introduced
  second instance**. Prefer the awk fallback, or `grep -Pzo … | grep -c ''`, if a true count
  is wanted later.

  **Counter-assertions — these must NOT change** (a naive `grep -c '2>&1' → 0` sweep would
  break all of them; v1 prescribed exactly that):
  - `grep -c '>/dev/null 2>&1' …` → **2** (the `validate_gh` discard idioms, lines 21/27).
  - `cmd_discussions`' `2>&1` error-classification capture still present (see AC4).
  - The five `gh api … 2>&1` variable captures at the `issues`/`prs`/`commits`/`repo_data`
    sites still present — they are the error *diagnostic*, not the defect.
- **AC4** `cmd_discussions` still returns its graceful `{"discussions": []}` payload (exit 0)
  for a repo without Discussions — proves the sweep did not regress it.
- **AC5** On a stubbed fetch failure, the script exits non-zero **and** the diagnostic carries a
  non-empty cause (not `Error: … ()`) — proves D3 preserved diagnosability.
- **AC6** No fabricated stat: on a stubbed error body, output contains no numeric
  `stargazers_count`.
- **AC7 (D2)** When a fetch returns exactly `per_page` items, a truncation warning is emitted on
  stderr.
- **AC8 (D4)** The prompt contains a GitHub collection-failure clause **and** the standing
  permission is amended. Verify by grepping for the **guardrail's presence** at the content
  anchors — not for the absence of the old text (an absence-grep false-fails on a file that
  legitimately quotes the phrase).
- **AC9** `bash scripts/test-all.sh` runs `github-community.test.sh` and it passes; each case
  verified to fail against pre-fix code.
- **AC10** No tempfile residue in the private per-test `TMPDIR`, including on failure paths.
- **AC11** PR body uses `Ref #6695`, **not** `Closes` — #6695 is a scheduled digest whose other
  content is unrelated (`wg-use-closes-n-in-pr-body-not-title-to`).
- **AC12 (D5 sidecar)** With `SOLEUR_COLLECTOR_STATUS_DIR` set, every subcommand appends exactly
  one JSONL record carrying its real exit code (success **and** failure). With the env var
  unset, nothing is written and behaviour is unchanged.
- **AC13 (D5 handler)** A stubbed non-zero collector record causes `reportSilentFallback` to fire
  **and** `heartbeatOk` to be false — asserted independently of `resolveOutputAwareOk`'s return
  value, so the fail-open catch branch cannot mask it (M4).
- **AC14 (D5b fabrication detector)** Given a run where the collector recorded
  `repo-stats exit != 0` **and** the digest contains a Repository Stats number, the detector
  fires (Sentry + RED). Given an honest `collection failed:` digest with the same non-zero
  record, it does **not** fire. Both arms required — a detector that fires on the honest path
  trains the operator to ignore it.
- **AC15 (H3)** With the stub in error-body mode (exit 0, `{"message":"Not Found"}`), `repo-stats`
  exits non-zero and emits **no** `new_stargazers_count` — proving the "plausible 0" path is
  closed.

### Post-merge (operator)

None. All verification is automatable in-session (live `gh` calls + the shell suite).

## Observability

```yaml
liveness_signal:
  what: scheduled-community-monitor Sentry check-in (existing monitor), with heartbeatOk forced false by any non-zero collector-status record (D5)
  cadence: daily 08:00 UTC
  alert_target: Sentry Crons — existing monitor (SENTRY_MONITOR_SLUG)
  configured_in: apps/web-platform/server/inngest/functions/cron-community-monitor.ts
error_reporting:
  destination: Sentry via the existing reportSilentFallback import, triggered by the handler reading the collector-status sidecar from spawnCwd (D5) — NOT via resolveOutputAwareOk, which is a presence-only check and cannot express this condition
  fail_loud: true — reportSilentFallback is emitted unconditionally on a non-zero record, independently of resolveOutputAwareOk's fail-open catch branch (M4)
failure_modes:
  - mode: GitHub fetch fails (rate limit, auth, 5xx)
    detection: collector appends {exit != 0, cause} to collector-status.jsonl; handler reads it before teardown
    alert_route: sidecar -> reportSilentFallback -> Sentry; heartbeat forced RED. No LLM in the path
  - mode: Fetch returns exit 0 with an error body (404/403/410) — would render a plausible 0
    detection: check_array_response rejects any non-array payload at every fetch site (D6)
    alert_route: non-zero exit -> sidecar -> Sentry; regression test 3
  - mode: Digest states a stat the collector did not produce (the RC3 class)
    detection: D5b cross-check — collector recorded repo-stats exit != 0 AND the digest contains a Repository Stats number
    alert_route: reportSilentFallback -> Sentry + heartbeat RED. This is the only deterministic control on RC3; the D4 prompt edits are a probability shift, not enforcement
  - mode: A fetch is silently capped at per_page (latent, not present-tense)
    detection: D2 records {"warn":"truncated_at_per_page"} on the sidecar record
    alert_route: sidecar -> Sentry. NOTE - if the sidecar is descoped, D2 and this entry are cut together; a stderr-only warning has no consumer
logs:
  where: Inngest run logs + Sentry breadcrumbs + collector-status.jsonl (run-scoped, in spawnCwd, never committed)
  retention: per existing Sentry/Inngest retention; the sidecar is discarded with the ephemeral workspace
discoverability_test:
  command: bash plugins/soleur/skills/community/scripts/community-router.sh github repo-stats 1
  expected_output: stargazers_count
```

No SSH is required for any verification step (`hr-no-ssh-fallback-in-runbooks`).

## User-Brand Impact

**If this lands broken, the user experiences:** a community digest stating confident, wrong
growth numbers — stars carried forward from a six-week-old digest and presented as current,
under a period the digest invented. The operator makes positioning and prioritization calls on
fabricated traction data.

**If this leaks, the user's data is exposed via:** no new exposure. The collector reads only
public repository metadata through already-granted `gh` auth. No new data category, destination,
or retention is introduced.

- **Brand-survival threshold:** `none` — internal operator reporting, no external surface, no customer data.

**Sensitive-path scope-out** (required — `deepen-plan` Phase 4.6 correctly rejected an earlier
draft that claimed no sensitive path was touched):

- `threshold: none, reason: the only sensitive-path file is
  apps/web-platform/server/inngest/functions/cron-community-monitor.ts, and the edits are
  confined to LLM prompt prose plus one failure-signal call — no auth, credential, payment,
  schema, or user-data path is read or written.`

The edit surface within that file is: three prompt-string anchors (D4a/b/c) and the D5
output-aware failure condition. It touches no secret, no Supabase client, no route handler, and
no request path. `apps/web-platform/server/` matches the canonical sensitive-path regex on the
directory prefix alone, which is why the scope-out is required even though the change is inert
with respect to the concerns the regex protects.

## Domain Review

**Domains relevant:** Engineering, Support

### Engineering

**Status:** reviewed
**Assessment:** Bug fix on an existing, already-provisioned surface. No new infrastructure,
dependency, or schema. The chief risk identified at v1 was *over*-fixing: a `2>&1` sweep and a
pagination loop that would have regressed `cmd_discussions` and added a sort-order invariant for
a defect that does not occur at the production window. v2 cuts both. The remaining diff is two
`--argjson` sites, one `2>&1`, three prompt anchors, and a test helper.

### Support

**Status:** reviewed
**Assessment:** Directly improves the community-monitor digest (CCO surface). The behavioral
change operators will notice: the digest will sometimes say "collection failed" instead of
showing a number. That is the intended outcome — an honest gap is more useful than a confident
fabrication, and it is what makes the next failure self-report.

### Product/UX Gate

Not applicable — no UI surface in Files to Edit/Create; the mechanical UI-surface override did
not fire (shell + server-side TS only).

## Architecture Decision (ADR/C4)

**Not required.** A bug fix on an existing surface: no ownership/tenancy boundary move, no new
substrate or integration pattern, no resolver/dispatch/trust boundary change, no divergence from
an existing ADR.

**C4 completeness check.** All three model files (`model.c4`, `views.c4`, `spec.c4`) were
considered against this change's external actors and systems. It introduces no new external
human actor, no new external system or vendor (GitHub is already the data source being read), no
new container or data store, and no changed actor↔surface access relationship. No `.c4` edit is
in scope.

## GDPR / Compliance

Considered and **not triggered**. The canonical regulated-surface regex does not match (no
schema, migration, auth flow, API route, or `.sql` file). None of the four expansion triggers
fire: no new LLM/external-API processing of operator-session data (the digest LLM already reads
this), threshold is `none`, no new cron reads `learnings/`/`specs/`, no new distribution surface.
v2 *reduces* data volume versus v1 by cutting pagination.

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues; none reference `github-community.sh`,
`cron-community-monitor.ts`, or `community-router.sh`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `--slurpfile` array-wrapping silently yields `count: 1` | D1 pins the unwrapping shape; AC1 asserts non-empty JSON with correct counts; RED test 1 asserts an exact item count |
| The `2>&1` fix regresses `cmd_discussions` or `validate_gh` | Only the stargazer site changes; AC3 asserts both survivors are still present; AC4 asserts the graceful path still works |
| D5's extension point is not yet read end-to-end | Phase 0 gates on reading it, with a named fallback (explicit `reportSilentFallback` in the persistence step) and a recorded deviation |
| The prompt's standing permission keeps overriding the new clause | D4c amends it directly; AC8 asserts the guardrail's presence |
| More "collection failed" lines in digests | Intended. An honest gap beats a confident fabrication — this is the fix, not a regression |
| Tempfiles leak on failure paths | `trap … EXIT` everywhere; AC10 asserts zero residue in a private `TMPDIR`, including forced-failure runs |

## Out of Scope (tracked separately)

- **`/tmp` leak in `apps/web-platform/infra/workspaces-luks-freeze.test.sh`** — 9,470 leaked
  `mktemp` files (1.9 GB) filled the 4 GB tmpfs during this planning session. Unrelated to #6695
  (introduced around `ca85c30bc`). **File a separate issue** labelled `bug`,
  `domain/engineering`, `priority/p2-medium` (all verified to exist). Reclaimed in-session by
  deleting entries untouched for >60 min; the missing-`trap` defect remains.
- **Why the cron produced no committed digest for 41 days** (newest committed digest is
  `2026-06-08`). The 41-day gap is an *availability* question, not a collector bug — `days=1` is
  correct for a daily cadence. Worth its own issue; D4b at least makes the resulting window honest.
- `github discussions` — not reported as failing, and its `2>&1` is load-bearing. Untouched.

## Work-Phase Corrections (implementation findings)

Six plan claims did not survive contact with the code. Recorded here because the
plan is authoritative for *intent*, never for facts.

| Plan claim | What execution showed | Resolution |
|---|---|---|
| **H3/D6:** an exit-0 error body renders a plausible `new_stargazers_count: 0`, "indistinguishable from a quiet day" | **Wrong.** Verified directly: `$stargazers[]` over an object iterates its *values*, so `select(.starred_at >= $since)` indexes a **string** and jq hard-errors (`Cannot index string with "starred_at"`, exit 5). The script already failed loudly; no fabricated `0` was reachable by this path | D6 kept, rationale corrected: its value is a **named cause** (`GITHUB_COLLECTOR_CAUSE=`) instead of an opaque jq indexing error — diagnosability, not closing a fabrication hole. Test 3's first two assertions pass pre-fix and are documented as forward guards; only the cause assertion was RED |
| **AC2:** `grep -c -- '--slurpfile'` → 5 | Returned **6**. The sixth match was the plan-mandated explanatory comment naming the flag — the exact trap task 4.8 raised for the other two literals, which I then walked into with the third | Comment reworded AND the assertion anchored (`^[[:space:]]*--slurpfile`), matching its own `--argjson` half. The anchored and unanchored slurpfile greps now agree at 5; the unbounded-`--argjson` grep is 0 |
| **AC3 counter-assertion:** `grep -c '>/dev/null 2>&1'` → **2** | A whole-file count false-fails a *correct* implementation: `check_array_response` and the repo-metadata shape check legitimately add the idiom | Scoped to the function it is about: `awk '/^validate_gh\(\)/,/^}/' \| grep -c '>/dev/null 2>&1'` → 2. Same "fixed total false-fails" reasoning the plan already applied to AC2 |
| **D2:** warn when a fetch returns exactly `per_page` items | Fires on **every live run**. The `pulls` endpoint deliberately over-fetches a fixed page and filters by date client-side, so a full raw page is its steady state (100 on every run against this repo) | Cap measured **post-filter** for `pulls` only, where a full page really does mean the window is saturated. A detector that cries wolf daily is worse than none — the same argument the plan makes for D5b's honest arm. Guarded by a dedicated negative test |
| **AC9:** every case verified to fail against pre-fix code | Test 4 (multi-tempfile cleanup) **cannot** be RED pre-fix — the pre-fix commands create no tempfiles, so cleanup passes trivially | Documented in-file as a forward guard and covered by mutation instead: splitting the single trap into one-per-file turns it RED (M5) |
| **AC14:** both arms of the fabrication detector are tested | Both honest-path fixtures were **digit-free**, so the bare "contains a number?" check returned false on its own and the honest-failure exemption was never exercised. Mutation-testing showed deleting the exemption kept the suite GREEN | Fixtures now carry digits (`collection failed: HTTP 404`) — realistic, since real causes carry status codes. All 5 handler mutations now RED |

### Review-phase corrections (10-agent panel)

Nine of ten agents returned findings; six converged on the same P1. Everything
below was fixed in-PR — all are `pr-introduced`, so none is scope-out eligible.

| Finding | Severity | Resolution |
|---|---|---|
| `check_cap "$issues_f"` passed a **file path** to a helper taking a count. `[[ /tmp/tmp.X -eq 100 ]]` is arithmetic evaluation → bash syntax error, non-zero inside an `if`, detector **permanently dead** on `contributors` + stderr noise every run. Converged on by 6 agents; my `replace(…, 1)` had converted only the first of two identical call sites | **P1** | Fixed; `PER_PAGE` bound to one constant; a `contributors` cap arm added (test 7c) |
| `if (collectorSignalRed) heartbeatOk = false` was the try's **last statement**. A throw from `safe-commit-pr` jumps to the catch — which deliberately keeps `heartbeatOk` true for a trailing-step failure — so a collector failure **paged GREEN** on exactly the compound-failure run | **P0** | Moved after the inner catch closes: after persistence (digest kept) *and* on the throw path |
| `add // []` → `.[0] // []` mutated at **all six sites** left the suite 36/36 green. Every fixture was a single JSON array, so `--paginate`'s multi-array output — the whole reason the flattening exists — was **unverified**. Verified: two-page fixture gives 150 vs 100 | **P1 (vacuous test)** | Multi-page fixtures added for stargazers and issue-comments; mutation now RED |
| The untracked sidecar made `safe-commit-paths-dropped` fire on **every** run, drowning the control that detects a bot writing outside its allowlist | **P1** | Added to `STRUCTURAL_EXCLUSION_PREFIXES` + `.gitignore` |
| `warn: truncated_at_per_page` was written, typed, and **read by nothing** — the `alert_route` this plan claimed did not exist | **P1** | `classifyCollectorStatus` extracted with a warn arm that reports without paging; all three arms unit-tested |
| Stargazer cap fired on a **complete** set: `--paginate` exhausts pages, so a total of exactly 100 means done, not truncated | **P1** | Cap call removed for that endpoint, with the reason recorded at the helper |
| `cmd_fetch_interactions` ran in production with **zero test coverage** and collapsed a lost fetch into `[]` at exit 0 | **P1** | Separate stderr + shape guard + three test cases |
| The spawn-env negative class was extracted from the `buildSpawnEnv` slice only; the new call-site wrapper composed the env **outside** the guard | **P2** | Guard widened to the whole module |
| `digestFabricatesRepoStats` could not change any outcome (it required `repo-stats` failed, which already reds the monitor) and its regex failed **silently** on a bold-list rendering | **P2 (over-build)** | **Cut.** The plan's claim that it was "the only deterministic control on RC3" was wrong — the collector-status gate already covers it. Prompt edits kept |
| `check_rate_limit_file` was triple-covered and used a bash-4 `${msg,,}` on a script with a BSD fallback | **P2** | Cut; `_CAUSE="rate-limit"` added to the surviving `check_rate_limit`, which previously recorded an empty cause |
| An empty-body guard using `-s` passed a **whitespace-only** body (reachable for the direct-written stargazer file) | **P2** | Strengthened to a slurped-length check |

**Mutation results.** 8/8 script and 4/4 handler mutations turn the suite RED —
after **three** were found vacuous and fixed: two digit-free fixtures, and an
ordering guard whose bare `indexOf("} catch (err) {")` anchored on the first of
**three** matches in a different function, making the assertion trivially true.
A green mutation battery measures the mutations its author thought of; three of
this PR's holes were only found by mutating something the author had not.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **A signal that ends in an LLM's context window is not observability.** The collector runs as
  a Bash tool call inside the spawned `claude`, so its stderr is captured by the Bash tool, not
  by the `claude` process's `child.stderr` — it never reaches `spawnResult.stderrTail`. v2
  routed three separate signals (`GITHUB_COLLECTOR_CAUSE=`, the D2 cap warning, the D4
  `collection failed:` line) into that dead end and then *claimed the route in its Observability
  block*. Before asserting an `alert_route`, trace every hop to a destination a human does not
  have to read.
- **`resolveOutputAwareOk` is a presence-only check.** It answers "was an issue with this label
  updated since `runStartedAt`?" — nothing about content. Any design that needs to distinguish
  *what the agent wrote* cannot use it, and both the fabrication and honest-failure paths return
  GREEN through it. Its `catch` branch also returns `spawnOk` (deliberate fail-open, #5139), so
  never make a new signal depend solely on its return value.
- **`trap … EXIT` is global and singular — a second one replaces the first.** Registering one
  trap per tempfile silently leaks all but the last, on every run. Use a single trap listing
  every file (verified: naive two-trap form leaked 1; single-trap form leaked 0). And do **not**
  use a `_mktemp()` helper that appends to an array and returns the path via `$( )` — the append
  happens in a subshell, so the parent array is empty and every file leaks (verified: size 0,
  2 leaked). This bug appeared in a *reviewer's own recommended fix*; verify suggested code, not
  just suggested findings.
- **`--slurpfile`'s dangerous failure is the *partial* unwrap, not the full one.** Full
  non-unwrapping hard-errors on `.number` against an array. Partial unwrapping — projections
  fixed, `length` left as-is — yields `{"count": 1, "items": [ …all items… ]}` at **exit 0**:
  green, plausible, wrong. It is also the *likelier* mistake when five bindings are rewritten by
  hand across three functions. Assert `count == (items|length)`, never "non-empty JSON".
- **A prompt instruction is a probability shift, not an enforcement mechanism.** An AC that
  greps the prompt for a guardrail verifies the instruction was *written*, not *obeyed*. If the
  failure being guarded has already occurred 16 times, ship a deterministic backstop alongside
  the prompt edit or the next occurrence is again found only by a human reading the digest.
- **The binding limit is `MAX_ARG_STRLEN` (131,072 B *per argument*), not `ARG_MAX`
  (2,097,152 B).** A fixture sized against `ARG_MAX` would be 16× larger than needed and would
  obscure which limit is under test. RC1 fires on **10 commits** — it is driven by per-object
  payload size, not item count.
- **`--slurpfile` is not a drop-in for `--argjson`.** It wraps file contents in an array, so
  `$x` becomes `[[…]]` and every `$issues[]`-style reference must be rewritten. Get this wrong
  and the jq program silently emits `count: 1` — green exit, wrong data.
- **Do not sweep `2>&1` globally.** Of 9 occurrences, exactly **one** is the defect. Two are
  `>/dev/null 2>&1` discard idioms in `validate_gh`; the `cmd_discussions` capture is
  load-bearing for its graceful "Discussions not enabled" path (discarding it converts graceful
  degradation into a hard `exit 1`); and five others *are* the error diagnostic — discarding
  them yields `Error: Failed to fetch issues ()` and contradicts the `…_CAUSE=` requirement.
- **`make_gh_stub` handles only `gh run list`.** Every `gh api` / `gh auth status` call hits its
  `exit 1` branch. A precondition that merely checks the helper *exists* is vacuous — the
  `gh api` stub is a deliverable, not a reuse.
- **Measure at the configuration that actually runs.** v1's headline "-87 % undercount" was
  measured at `days=41` while production runs `days=1`; at `days=1` the endpoints return 10/56/14
  items and no truncation occurs. The error survived into a whole scope decision (pagination +
  a `days` change) because the `days=1` numbers were collected but never reconciled against the
  claim they contradicted.
- **A prompt fix must amend the contradicting instruction, not just append to it.** The standing
  `If any command in a batch fails, log the error and continue.` is what the LLM uses to omit the
  GitHub section; adding a failure clause elsewhere leaves two contradictory instructions and the
  vaguer one tends to win.
- `jq -s 'add // []'` on stderr-poisoned input exits **5** (not 0) and `set -o pipefail` *does*
  catch it — so `cmd_repo_stats` already fails loudly. Any claim that the script silently
  degrades to `[]` is wrong; the stale numbers come from the LLM, which is why the RC3 fix lives
  at the prompt layer, not in the script.
