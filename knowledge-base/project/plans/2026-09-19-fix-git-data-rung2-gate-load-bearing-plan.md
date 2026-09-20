---
title: "fix(git-data): make git_data_rung2_rehearsal_gate load-bearing — resolve the run, bind its head SHA to the hash, make the Sentry cross-check a required verdict"
type: fix
date: 2026-09-19
slug: fix-git-data-rung2-gate-load-bearing
branch: feat-one-shot-8010-rung2-gate-load-bearing
issue: 8010
closes: 8010
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-19 (round 1)
**Halt gates run:** 4.6 user-brand (pass) · 4.7 observability (pass, all five fields non-placeholder, allowlisted probe verb, no SSH) · 4.8 PAT-shaped (no hits) · 4.9 UI wireframe (skip — no UI surface) · 4.10 encryption posture (pass) · 4.11 guard contract (pass, `lint-guard-contract.py` green over 4 entries) · 4.5 network-outage and 4.55 downtime/cutover (skip — no SSH diagnosis, no provisioner-bearing apply, no serving surface taken offline).
**Agents:** verify-the-negative sweep · `soleur:engineering:review:security-sentinel` · `soleur:engineering:review:test-design-reviewer` · `soleur:engineering:research:git-history-analyzer` · `soleur:engineering:review:observability-coverage-reviewer` · precedent-diff sweep. Round-0 plan review: DHH · Kieran · code-simplicity · architecture-strategist · spec-flow-analyzer · CPO · CTO (structural + devex) · ADR-083 advisor.

### Key improvements

1. **The anchor claim was one level too strong and is now honest.** `git_data_rung2_bound_files` binds 17 files, none of them the rehearsal workflow or the capture script (measured), so Guard 1 proves "a workflow at that path ran on `main` and produced a boot-evidence artifact", not "a rehearsal happened". The producer-binding residual is named in the Guard Contract and filed in ADR-149 rather than claimed.
2. **Four concrete attack/leak paths closed at design time:** workflow-command injection through evidence-derived values printed into `::error::` and into the #8210 probe's issue comment; symlink/hardlink entries in the attacker-influenceable archived tree; xtrace leaking the bearer out of a sourced library; and a private-repo future where an anonymous 404 would read as forgery.
3. **A CI gate the plan would have tripped, found before it ran.** `scripts/lint-trap-tempfile-ownership.py` rule (c) fires on new `mktemp` allocations without an owning trap; the gate library has zero today. The precedent (`git-data-boot-signal-poll.sh`, and the highwater file's own #8178 entry) explicitly rejected `rm -rf "$scratch"` as an operand the P1b guard cannot prove safe — so the plan flipped from "removed inline on every return path" to the sanctioned leak-plus-annotation, plus a highwater raise.
4. **The daily probe stops reporting an instrument failure as "not run yet".** `sweep-followthroughs.sh` already renders `exit 3` as **CANNOT ESTABLISH** with the issue left open (measured), so FR16 became an rc split keyed on the bracketed token instead of a reworded sentence — and the `::error::` emitter is now documented as having **no reach** on that path (`env -i` drops `GITHUB_ACTIONS`; the output is captured into a comment).
5. **Six ways the prescribed test battery would have been vacuous or unbuildable**, including `mutate_r2`/`mutate_g` asserting rc only (so every token-swap mutation row would pass whether or not the mutant landed), harness row (a) having no helper that mutates the suite, two run-id seeds missing (`17253046871`, `2`), the capture suite's per-command `SOLEUR_TEST_MODE` prefix being the property under test rather than an oversight, and no fixture placing the cloud-init in a subdirectory — so Guard 2 row 5's tree-ish branch would never execute.

### New considerations discovered

- The suite's baseline is **150 passed / 0 failed with `_FLOOR=150`** — zero slack, so the floor must be raised to a measured count, not a predicted one.
- Under the suite-wide seam `_git_data_rung2_fetch` never executes, so the curl flag set (and the `## Encryption Posture` claim that rested on it) is asserted by source-grep, not by a behavioural row.
- The evidence **downgrade** shape (revert the infra tree, cite an old genuine run) passes every new check honestly; what catches it is Guard 4 ARM 2, which is advisory only because `deploy-script-tests` is not a required check — folded into the blocker issue.

## Overview

`git_data_rung2_rehearsal_gate` (sourced from `tests/scripts/lib/git-data-birth-readiness-gate.sh`) is the last mechanical hold in front of the git-data host birth and replace routes. Today it proves that a well-formed, hash-bound assertion file exists — not that a rung-2 rehearsal passed. The Actions run named in `RUNG2_EVIDENCE_URL` is shape-matched and never resolved; `RUNG2_SENTRY_CROSSCHECK` is written by the capture script and read by nobody; the host name lives in a stripped comment. A four-line hand-written file naming a nonexistent run releases the gate.

This plan makes three things load-bearing, in the gate library, the capture script and the rehearsal workflow's evidence emission: the run id (resolved through the GitHub REST API, required to be a completed, successful, `main`-dispatched `workflow_dispatch` run of the rehearsal workflow whose `head_sha` re-hashes to the evidence's `RUNG2_TEMPLATE_SHA256` and which actually uploaded a boot-evidence artifact), the Sentry cross-check (a required key with a closed value set, where a fatal or unreadable verdict holds outright and a degraded one needs an explicit run-bound acknowledgement), and the capture's own consistency (the host-name suffix must equal the run id it cites, and the Sentry liveness anchor is decoupled from the run-pinned fatal window so a quiet project no longer reads as a dead instrument).

No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

The apply workflow (`.github/workflows/apply-web-platform-infra.yml`) is **not** edited — it is over GitHub's 500 KB workflow-file limit (#8361; measured 513,306 bytes, and its last five runs all conclude `failure` with zero jobs, i.e. startup failure) and the brief scopes this PR to `git-data-rung2-rehearsal.yml` as the only workflow to touch. That has a consequence the plan states rather than discovers: the gate's two apply-workflow call sites are **inert until #8361 lands**, so this cycle's live surfaces are `infra-validation.yml`'s freshness step, the #8210 follow-through probe, the rehearsal workflow's operator instructions, and local invocation.

## Problem Statement

Measured on PR #8002 at `47a00de87` and restated in #8010:

1. **The run is never resolved.** `RUNG2_EVIDENCE_URL` passes a `=~ ^https://github\.com/jikig-ai/soleur/actions/runs/[0-9]+` shape check and nothing else. The gate's own refusal text says an unauditable claim is not evidence "and this repository's main branch has no required-review ruleset standing behind a hand-typed one" — still true.
2. **`RUNG2_SENTRY_CROSSCHECK` has no consumer.** The capture writes it (`printf 'RUNG2_SENTRY_CROSSCHECK=%s\n' "${_SENTRY_VERDICT:-NOT_RUN}"`), the capture suite asserts it exists, and the gate's required-key loop covers only the other four keys. `UNAVAILABLE`, `NOT_RUN` and junk all release.
3. **The host name is a stripped comment**, by design (comments are never load-bearing in this gate).
4. **Guard 4 (#8043) has a stated residual** — "last-touch laundering": a later evidence-only commit re-blesses a voided attestation through both provenance arms. Guard 4's own header says closing it "requires resolving the run RUNG2_EVIDENCE_URL names and binding its head SHA — #8010's scope".
5. **The Sentry liveness anchor is run-pinned.** On run 34768256297 it asked whether any *other* host emitted inside a ~90 s window; on a quiet project the answer is `count()=0`, so the capture wrote `UNAVAILABLE` for a Sentry read path that was fine (measured: 0 at 90 s, 56 at 24 h, 1,210 at 7 d). Item 5 of the #8126 follow-up list was deliberately left for this cycle, "before item 3 of this issue makes the key load-bearing".
6. **A `dry_run=true` dispatch concludes `success` and boots nothing.** Measured on run 33886787297: `success`, `main`, `path: .github/workflows/git-data-rung2-rehearsal.yml`, job steps ending at `Dry run complete — stopping here: success` with `Capture rung-2 evidence` and `Upload the evidence file as an artifact` both `skipped`, and `0` artifacts. Workflow inputs are not in the run object, so workflow-identity plus conclusion alone re-open exactly the forgery this issue closes, one level up.

## Research Reconciliation — Issue vs. Codebase

| Issue / brief claim | Reality on `origin/main` (2026-09-19) | Plan response |
|---|---|---|
| Fix 2: "assert workflow identity, not `conclusion == success`, because the current evidence's run (33888071954) is marked failure" | Superseded. The committed-evidence lineage (PR #8126) names run **34768256297**: `conclusion: success`, `status: completed`, `path: .github/workflows/git-data-rung2-rehearsal.yml`, `head_branch: main`, `head_sha: 15fd63aff…`. | **Require `conclusion == success`** as the brief instructs. |
| The evidence file is committed | **Deleted** on `main` by #8312 (`f64b0ebc2`) — a hash-bound edit voids the attestation and deletion is the permitted shape. | The no-evidence HOLD path is unchanged. The next evidence comes from run **35465756680** (dispatched 2026-09-19 from `main` at `d64430c26`; measured `completed`/`success` at 20:09:21Z). Its artifact carries `RUNG2_SENTRY_CROSSCHECK=UNAVAILABLE`, `RUNG2_TEMPLATE_SHA256=a0b5f37b…` (equal to `main`'s live hash today), `RUNG2_REBOOT_REOPEN=PASS`, `RUNG2_REBOOT_REOPEN_CHANNEL=both`, `RUNG2_REBOOT_REOPEN_RESTARTS=0`. PR **#8393** commits exactly that file and is OPEN. |
| "The hash is a pure function of tracked files, computable by anyone" | True, and stays true. | Binding it to a **resolved run's `head_sha`** is what turns a staleness detector into an authorship proof: measured, `git archive 15fd63aff…:apps/web-platform/infra` + `git_data_rung2_user_data_sha256` reproduces `5c50797b…` exactly (the hash that run's evidence claims), while `main` today hashes to `a0b5f37b…`. |
| Fix 1: "assert URL run id == host-name suffix" (the comment-vs-key question) | The comment is stripped before the gate reads; promoting it to a key would make evidence from the current capture unreadable. | **Decided: the gate reads no comment and no key is promoted.** The property fix 1 wanted is delivered more strongly by resolving the run and by refusing, at write time in the only writer, a `--host-name` suffix that differs from the `--evidence-url` run id. Comparing two fields of one hand-editable file proves consistency, not integrity (learning 2026-09-14). |
| The gate can authenticate in CI | **No.** Every gate call site declares `contents: read` with **no `actions: read`** (the `git_data_host_create` and `git_data_host_replace` job blocks in `apply-web-platform-infra.yml`, the workflow-level block in `infra-validation.yml`, and the sweeper's own block), and `GET /actions/runs/{id}` needs `actions: read` per GitHub's REST reference; the apply file documents the adjacent requirement in its own words at its `github-app-token`-minting job — "`actions: read` is the minimum for `…/actions/runs/<id>/jobs`" — which is the sibling endpoint, not this one. Cited as a content anchor rather than a line number per `cq-cite-content-anchor-not-line-number`: the line numbers drifted between the issue body and this worktree. The repo is **PUBLIC** and an unauthenticated `curl` to the runs endpoint returned **200** at plan time. | The operative CI path is **anonymous**. Send a bearer only when `GH_TOKEN`/`GITHUB_TOKEN` is set, and on a 401/403 that is *not* a rate limit, retry once anonymously. The `actions: read` grant plus explicit token threading is the blocker issue (QG5), not this PR. |
| #8171 "left body items 1–3 untouched" | Confirmed by that PR's merge comment; it also declined item 5 (liveness window) as "tied to body item 3". | Items 1–3 and 5 are this plan's scope. |

## Proposed Solution

### The gate (`tests/scripts/lib/git-data-birth-readiness-gate.sh`)

`git_data_rung2_rehearsal_gate` keeps every check it has today, in today's order (cardinality → PASS → URL shape → hash shape → divergence → live hash → Guard 4 provenance), and adds, **after** Guard 4:

**Step A — tooling, before anything that can stall.** `command -v jq`, `command -v curl`, `command -v tar` → `ABORT [TOOLING_MISSING]` naming the binary and an install line. Checked first so a toolchain gap is not reported after a network timeout.

**Step B — the Sentry verdict (local, no network).** The producible value set was read from the writer, not from memory: `grep -n '_SENTRY_VERDICT=' scripts/followthroughs/git-data-rung2-evidence-capture.sh` yields `UNAVAILABLE` (the default), `CLEAN` and `FATAL`, and the writer emits `${_SENTRY_VERDICT:-NOT_RUN}` — so the set is {`CLEAN`, `UNAVAILABLE`, `FATAL`, `NOT_RUN`} and every member is classified:

- `RUNG2_SENTRY_CROSSCHECK` joins the existing **exactly-once** loop (absence is a HOLD — the loop's semantics are already `-ne 1`).
- A **separate at-most-once** loop covers the one optional key `RUNG2_SENTRY_CROSSCHECK_ACK` (`-gt 1` → HOLD). It cannot ride the required-key loop, whose absence-is-a-HOLD semantics are wrong for an optional key; and the required loop's pattern `…CROSSCHECK[[:space:]]*=` does not match `…CROSSCHECK_ACK=`, so the two counts are genuinely independent. Both cardinality loops run **before** the value `case`.
- `CLEAN` → continue. `FATAL` → `HOLD [SENTRY_VERDICT_FATAL]` (a measured second-channel failure; never ack-able). `NOT_RUN`, empty, or anything unknown → `HOLD [SENTRY_VERDICT_UNREADABLE]` (could not measure — a distinct token, per the closed-vocabulary discipline this plan cites). `UNAVAILABLE` → continue only with a well-formed ack.
- **Ack grammar:** `RUNG2_SENTRY_CROSSCHECK_ACK=<run-id>:<reason>`, where `<run-id>` is the id parsed from `RUNG2_EVIDENCE_URL`, optional whitespace may follow the colon, and `<reason>` is non-empty after trimming. The gate's existing trailing-comment strip (`s/[[:space:]]#.*$//`) truncates anything from ` #` onward, so the reason **may not contain `#`**; a reason that does is refused by name rather than silently truncated. Wrong run id → `HOLD [SENTRY_ACK_MISMATCH]` (an ack copied forward). No ack → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`. An ack beside `CLEAN` is **ignored**, not refused — it satisfies no property and a refusal would be ceremony.

**Step C — run resolution (network, one GET).** `_git_data_rung2_fetch <path-suffix>` performs the HTTP call and is the only thing the test seam replaces; `_git_data_rung2_check_run` interprets the body with `jq` and never re-implements it.

- Parse the run id from the URL as `[0-9]+` terminated by `/`, `?`, `#` or end-of-string — the existing shape regex is unanchored, so a naive `${url##*/}` reads `…/runs/123abc` as `123`. Then **validate it** with `[[ "$run_id" =~ ^[0-9]{1,20}$ ]]` before it is interpolated into a URL or handed to the seam, so R7's property does not rest on quoting discipline; a non-conforming id is `HOLD [RUN_UNRESOLVABLE]`. Compare to `.id|tostring` (string comparison: ids exceed bash and jq double precision).
- `curl --disable --noproxy '*' -sS --max-time 20 -w '\n%{http_code}' -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "${auth[@]}" <url>`, where `auth` is a bash **array** (`local -a auth=(); [[ -n "$tok" ]] && auth=(-H "Authorization: Bearer ${tok}")`) — an unquoted `${tok:+-H "…"}` word-splits without quote removal and the header is never sent. The function saves and clears xtrace on entry (`local _x="$-"; set +x`, restored before every return): the library inherits the caller's shell options, and a caller running `set -x` would otherwise print the bearer array element. Its stderr file is `mktemp` under `umask 077` and is removed on every return. The body/status split follows the established sibling form (`scripts/sentry-issue.sh`, the `RESP=…; CODE="$(printf '%s' "$RESP" | tail -n1)"; BODY="$(printf '%s' "$RESP" | sed '$d')"` idiom), not the `-o <file>` variant. `--disable` matters because the gate also runs on a workstation with a possible `~/.curlrc`; both flags match the repo's dominant convention (86 call sites vs 16).
- **No response-header parsing.** Rate limiting is detected from the status plus the body GitHub already sends (`403`/`429` with `.message` matching `rate limit`) → `HOLD [RUN_RATE_LIMITED]`, naming the `actions: read` + token remedy and the blocker issue. This removes `-D -`, CRLF handling and `retry-after` arithmetic, and it is why the seam's contract is body + status only.
- **Retries:** 2 attempts, only on 5xx or a transport failure, separated by `SOLEUR_RUNG2_RETRY_SLEEP` (5 s in production, `0` in the suite). `curl` rc 6/7 (DNS/connect) fast-fails on the first attempt with `HOLD [RUN_OFFLINE]` naming no network path to `api.github.com` — an offline operator must not be sent after a token they do not need.
- **Auth:** bearer from `GH_TOKEN`, else `GITHUB_TOKEN`, else none. On `401`/`403` **without** a rate-limit body, retry **once anonymously** — that is the operative CI path today (no call site grants `actions: read`) and the data is public. When a bearer was present and rejected and the anonymous retry then 404s, the token is `RUN_UNRESOLVABLE`, never `RUN_NOT_FOUND`: if this repository is ever made private, a measured-absent token for a could-not-measure condition would read to the operator as forgery.
- Field checks: `.id` matches → else `HOLD [RUN_NOT_FOUND]` on 404, `HOLD [RUN_UNRESOLVABLE]` on any other unusable answer (non-JSON, null fields, mismatched id); `.path == ".github/workflows/git-data-rung2-rehearsal.yml"` → `HOLD [RUN_WRONG_WORKFLOW]`; `.event == "workflow_dispatch"` → `HOLD [RUN_WRONG_EVENT]` (a future `schedule`/`push` trigger on the rehearsal workflow would otherwise produce identity-passing runs that boot nothing); `.head_branch == "main"` → `HOLD [RUN_NOT_MAIN]`; `.status == "completed"` → `HOLD [RUN_NOT_COMPLETED]`, worded as *wait and re-run the gate*, not re-dispatch; `.conclusion == "success"` → `HOLD [RUN_NOT_SUCCESS]`, naming re-dispatch and the teardown-after-capture case; `.head_sha =~ ^[0-9a-f]{40}$` → `HOLD [RUN_UNRESOLVABLE]`.

**Step D — head-SHA hash binding (local git).** `git -C <toplevel> cat-file -e <head_sha>^{commit}` → else `HOLD [RUN_SHA_UNREACHABLE]`, naming `git fetch origin main` and the shallow-clone case as Guard 4 does. **The gate does not fetch:** a gate must not mutate the repository it judges, and an unbounded fetch is another offline stall. Then `git -C <toplevel> -c core.attributesfile=/dev/null archive <head_sha>:<repo-rel-dir>` piped to `tar -x -C <tmpdir>`, and `git_data_rung2_user_data_sha256 <tmpdir>/<basename>` — the **same** function the live hash and the capture use.

- The **tree-ish** form is load-bearing and was measured both ways: `git archive <sha> -- <dir>` emits repo-root-relative entries, so `<tmpdir>/<basename>` would not exist; and where the cloud-init directory *is* the repo root — exactly the `_g_repo` and `$FIX` fixture shape — the repo-relative dir is the empty string and `git archive <sha> -- ""` is fatal (`empty string is not a valid pathspec`). `<sha>:<dir>` roots the archive at the directory, and `<sha>:` covers the root case. Verified at plan time against `15fd63aff…`: the extracted tree re-hashes to `5c50797b…`.
- Attributes are disabled during the archive so a future `export-ignore`/`export-subst`/`text=auto` entry cannot make archived bytes differ from the worktree bytes the live hash reads (today `.gitattributes` carries merge drivers only; `git check-attr -a` on the roster returns nothing).
- **Extraction is hardened against a hostile tree.** `tar -x --no-same-owner --no-same-permissions`, then an `lstat` sweep that refuses any symlink or hardlink entry before hashing (`HOLD [RUN_HASH_UNCOMPUTABLE]`): the archived tree comes from an attacker-influenceable commit, and a mode-120000 entry pointing at `/etc/shadow` or back into the live worktree is both an arbitrary-read and a same-hash laundering shape.
- **The extraction directory leaks, deliberately, with the sanctioned annotation** — it is NOT removed inline. The library must not install an `EXIT` trap over its caller's (ADR-129 rule (c), stated in this file's own header), and the closest precedent — `scripts/lib/git-data-boot-signal-poll.sh`'s scratch dir — records that an explicit `rm -rf "$scratch"` was considered and **rejected**, because a variable-rooted `rm` is an operand the P1b relative-operand guard cannot prove safe: it trades a bounded leak for an unprovable destructive operation. Consequences this plan must carry rather than discover: the site needs a `# lint-trap-ownership: ok <reason>` annotation (a bare marker is itself an error), and because `scripts/lint-trap-tempfile-ownership.py`'s census counts POPULATION and deliberately does not honour the escape, `scripts/lint-trap-tempfile-ownership.highwater` must be raised by one with a written reason — the gate library calls `mktemp` **zero** times today, so this is a new entrant. `--check-highwater` runs in `ci.yml`. A per-function `trap … RETURN` is the alternative the lint also accepts; it is rejected here for the same reason the sibling rejected it, and the residual leak is one directory per gate call.
- Outcomes: hash differs → `HOLD [RUN_HASH_MISMATCH]` naming both hashes and the run's `head_sha`; the hash function itself ABORTs on the archived tree (an older `head_sha` whose module shape is non-canonical, or a roster below its floor) → `HOLD [RUN_HASH_UNCOMPUTABLE]`, a could-not-measure token carrying the ABORT's own first line.

**Step E — the capture discriminator (network, one GET).** `GET …/actions/runs/<id>/artifacts` must list an artifact named exactly `git-data-rung2-boot-evidence`. This is what separates a real capture from a `dry_run`/`teardown_only` dispatch (problem 6): the upload step is gated on both the capture rc and the reset-probe rc being 0, so the artifact's existence is the durable statement that this run captured a PASS. It runs **after** the local git checks, not beside the first GET, so the common refusals (stale evidence, laundering) cost one request instead of two.

- Records survive expiry: measured `expired: true` on run 27579149955 (~110 days old), while run 23814647816 (172 days) lists its jobs with `steps: []` — which is why the jobs API is not the discriminator.
- `total_count == 0` or no matching name, **and the run is younger than 90 days** (`.created_at`) → `HOLD [RUN_NO_EVIDENCE_ARTIFACT]`. Older, or the endpoint unusable → `HOLD [RUN_ARTIFACT_RECORD_UNREADABLE]` (could not measure — artifact-record retention past the window is undocumented and measured once, so it must not masquerade as a measured refusal). Name matching is **exact**: `git-data-rung2-capture-log` is uploaded on non-PASS runs.

**Cross-cutting — every evidence-derived value is sanitized before it is printed.** The HOLD lines interpolate values read from the evidence file (`${url}`, `${claimed_sha}`, the divergence tokens, the ack reason), and the Actions runner percent-decodes workflow-command data — so a value carrying `%0A::stop-commands::…` or `%0A::add-mask::` is a workflow-command injection from a `pull_request`-triggered step, and the same bytes reach a public issue comment through the #8210 probe. One sanitizer runs on every interpolated evidence value: strip `[\x00-\x1f\x7f]` and U+2028/U+2029, escape `%`→`%25`, CR→`%0D`, LF→`%0A`, then truncate to a named length. This is NFR1's second clause.

**Cross-cutting.** Every refusal is one line carrying exactly one bracketed token, and the could-not-measure set (`RUN_OFFLINE`, `RUN_RATE_LIMITED`, `RUN_UNRESOLVABLE`, `RUN_SHA_UNREACHABLE`, `RUN_HASH_UNCOMPUTABLE`, `RUN_ARTIFACT_RECORD_UNREADABLE`, `SENTRY_VERDICT_UNREADABLE`, `TOOLING_MISSING`) never shares wording with the measured-refusal set. When `GITHUB_ACTIONS` is set and the token is in the could-not-measure set, the gate **itself** emits one `::error::` line naming the instrument failure: the three CI call sites print `"… is HELD: no rung-2 boot evidence for the CURRENT cloud-init-git-data.yml"` on any non-zero rc, that text is pinned by `plugins/soleur/test/terraform-target-parity.test.ts`, and two of the three files cannot be edited this cycle — so the gate's own annotation is what stops an operator being told to commit evidence that already exists. The RELEASED line names the resolved run id, its `head_sha`, `concluded success`, the artifact it found, and the Sentry verdict.

**Test seam** (mirrors `SOLEUR_SENTRY_READER`, double gate included): `SOLEUR_RUNG2_RUN_FETCH` is honoured only when `SOLEUR_TEST_MODE` is also set. It is invoked with the **URL path suffix** (`runs/<id>` or `runs/<id>/artifacts`) so one stub serves both endpoints, and it prints the body then the HTTP status on the last line — body + status only, matching the real fetch now that header parsing is gone. Parsing, field checks, the artifact-name check and the archive/hash step always run for real. When `SOLEUR_RUNG2_RUN_FETCH` is set without `SOLEUR_TEST_MODE`, the refusal message says so, so the intended real-path fall-through does not read as a flaky test.

**The seam announces itself.** Whenever it is honoured, the RELEASED **and** HOLD lines carry `SEAM ACTIVE — <path>`. `infra-validation.yml` triggers on `pull_request`, so a PR author controls that step's `env:` block; without the announcement two innocuous-looking env lines would produce a `RELEASED` line indistinguishable from a real one. A suite arm additionally asserts that no workflow `env:`/`with:` block and no Doppler config name matches `SOLEUR_TEST_MODE|SOLEUR_RUNG2_`. The path-suffix-keyed stub store is **novel** — the only `SOLEUR_TEST_MODE` precedent (the capture's `SOLEUR_SENTRY_READER`) swaps a whole reader binary and is not argv-keyed; only the double-gate mechanism is mirrored.

### The capture (`scripts/followthroughs/git-data-rung2-evidence-capture.sh`)

1. **Host/run-id coupling at write time.** After both existing shape checks, refuse (exit 64) when `${HOST_NAME#soleur-git-data-rehearsal-}` differs from the run id parsed from `EVIDENCE_URL`. The capture is the only writer, so this pins fix 1 at the source.
2. **The liveness window is decoupled from the fatal window.** The single `--liveness` call in `_sentry_consult` passes `--stats-period 24h` regardless of `--since`; the run-pinned `--host-events` fatal read is unchanged. No helper — one call site does not need one. The rationale goes in the comment: the anchor asks whether the *instrument* is answering, which is a question about the last day, not about this run's two minutes.
3. **"Never consulted" stops reading as "degraded".** The `jq`-missing, `SENTRY_ISSUE_RO_TOKEN`-unset and reader-missing branches print `SKIPPED` while leaving `_SENTRY_VERDICT=UNAVAILABLE`, so a cross-check that never ran commits bytes identical to one that ran and degraded — and the new ack path would bless it. Those branches set `NOT_RUN`, which the gate refuses outright and which no ack can rescue.
4. **The evidence records the liveness question.** ARTIFACT 4 gains `# QUERY: sentry-issue.sh --liveness <host> --stats-period 24h` beside the `--host-events` line, and one sentence saying `UNAVAILABLE` now HOLDs the gate unless acknowledged.
5. **The reset arm records its real end timestamp** (P3 from PR #8393's security seat): the appended `# QUERY: … --stage luks_reopen_ok --start <since> --end <now>` writes the literal `<now>`; capture the resolved end once into a local and use it in both the call and the recorded line.
6. **The reset arm's own cross-check is scoped in prose.** `--reboot-since` re-runs `_sentry_consult` but appends only `RUNG2_REBOOT_REOPEN*`, so the committed `RUNG2_SENTRY_CROSSCHECK` describes the pre-reset window only. ARTIFACT 4's text says that explicitly rather than leaving a reader to assume the key covers the whole run.

### The rehearsal workflow (`.github/workflows/git-data-rung2-rehearsal.yml`)

Only summary text changes; the `Rung-2 rehearsal: PASS|FAIL` and `WRAPPER FAILURE` headings that `git-data-rung2-rehearsal.test.sh` pins are untouched.

1. The **ack decision is emitted once, after the reset probe** (the workflow step `id: reboot_probe`, so named in code), not as instructions-plus-caveats mid-run: a single line reading `ACK REQUIRED — append RUNG2_SENTRY_CROSSCHECK_ACK=${GITHUB_RUN_ID}:<why the second channel may be skipped for this run>` when the file's verdict is `UNAVAILABLE`, or `ACK NOT REQUIRED — cross-check CLEAN`. The value is read from `/tmp/rung2/git-data-rung2-boot-evidence.env` and CR/LF-stripped (`${v//[$'\n\r']/}`) before reaching `$GITHUB_STEP_SUMMARY`, which is line-oriented.
2. The **"land it yourself" block is reordered** so the ack is appended **before** `git add`: following the current order and appending afterwards yields Guard 4's "differs from its committed state" HOLD and forces an amend.
3. It says the evidence is usable only once the **whole run** concludes `success` (`gh run watch <id>` / `gh run view <id> --json conclusion`), because the artifact uploads before teardown and a failed teardown reds the run after the operator has already downloaded a good file.

### The fifth caller: the #8210 follow-through probe

`scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh` sources the library and calls the gate; the daily `scheduled-followthrough-sweeper.yml` runs it under `env -i` with only `PATH`, `HOME` and declared `secrets=` names, and checks out with `persist-credentials: false`. It therefore resolves anonymously. That is safe — every non-zero rc maps to its `TRANSIENT` arm (exit 2), so a rate limit cannot false-close #8210 — and **no `secrets=GH_TOKEN` is added**: the sweeper's `permissions:` block is `contents: read` + `issues: write`, so its `GITHUB_TOKEN` cannot read the Actions API either. The only change is one sentence in the probe's TRANSIENT message so a `RUN_*`/`SENTRY_*` instrument failure reads as one instead of as "the payload was edited". `git`, `curl` and `jq` are on the sweeper's pinned `PATH`. Adding `actions: read` to that workflow goes in the blocker issue.

### Documentation

- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`: Dispatch gains `--ref main`; a **token → remedy table** (one row per new HOLD token) that every new refusal line cites by path; `After a PASS` gains `gh run watch`, the ack-before-`git add` ordering, and the `jq`/`curl` dependency; `Two things that will mislead you` gains `RUN_NOT_COMPLETED`; a short **payload-change sequence** section stating the two-PR shape that Guard 4 plus `--ref main` require (payload PR deletes the evidence → merge → dispatch on `main` → evidence-only PR), and that the route is interlocked in between.
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`: retire "the gate ignores it today" for `RUNG2_SENTRY_CROSSCHECK`; add the operator fallback order for a `RUN_*` HOLD on the replace route (re-run the gate locally with `GH_TOKEN` exported to confirm the HOLD is an instrument failure, then re-dispatch).
- The gate's `STALE EVIDENCE` message — the first and usually only thing a payload author reads — gains one sentence pointing at the rehearsal runbook, because after this merge "re-run the rehearsal" silently means four new preconditions.
- ADR-149 disposition and one `model.c4` sentence (below).

## Technical Approach

### Architecture

```
evidence file ──► git_data_rung2_rehearsal_gate
                    ├─ (existing) keys ×1, PASS, URL shape, hash shape, divergence allowlist
                    ├─ (existing) live hash == RUNG2_TEMPLATE_SHA256
                    ├─ (existing) Guard 4 provenance (evidence commit touches no bound file)
                    ├─ A  jq / curl / tar present                                   [local]
                    ├─ B  Sentry verdict ∈ {CLEAN, UNAVAILABLE + ack(run-id)}       [local]
                    ├─ C  GET runs/<id>: path, event, head_branch, status,
                    │        conclusion, head_sha                                   [network]
                    ├─ D  head_sha reachable; hash(archive <sha>:<dir>) == claim    [local git]
                    └─ E  GET runs/<id>/artifacts: git-data-rung2-boot-evidence     [network]
```

Local before network, and the cheap network call before the expensive-to-be-wrong one: an offline operator sees file defects first, and the common refusal costs one request.

### Implementation Phases

#### Phase 1: RED — the gate's refuse paths (tests first, `cq-write-failing-tests-before`)

`tests/scripts/test-git-data-birth-readiness-gate.sh`:

- **Seam plumbing, once, at suite top — in the GATE suite only:** `export SOLEUR_TEST_MODE=1 SOLEUR_RUNG2_RUN_FETCH="$TMP/api-fetch.sh" SOLEUR_RUNG2_RETRY_SLEEP=0`. `export`, not a command prefix: `mutate_r2` and `mutate_g` run the gate in a **child** `bash -c`, so a prefix on `r2check` would not reach the five existing `want_rc=0` mutation rows and they would hit the live network. **Do not export in the capture suite** — that file passes `SOLEUR_TEST_MODE=1` as a per-command prefix precisely because the CWE-427 double gate is the property under test there; exporting it would silently honour `SOLEUR_SENTRY_READER` in every other arm. Scope the capture-side seam to the producer/consumer arm's own invocation.
- **The real fetch is never executed under the seam, so its flag set is asserted by source-grep, not by a stub.** With `SOLEUR_RUNG2_RUN_FETCH` set suite-wide, `_git_data_rung2_fetch` itself never runs: the `https://` literal, `--disable`, `--noproxy '*'`, the array-built bearer, the xtrace save/restore and the rc 6/7 → `RUN_OFFLINE` branch have no behavioural arm. Shimming `curl` to get one is the anti-pattern the 2026-09-02 learning names ("my fake curl put the seam above everything the vendor validates"). So add a **source-grep arm** over the gate library asserting each token is present and that `-k`/`--insecure`/`-D -`/`-v` are absent — and say in `## Encryption Posture` that this is the mechanism, rather than claiming a mutation row reddens on the `https://` literal.
- **Stub store** (under `$TMP`, which is what `git_fixture_env "$TMP"` fences and what `assert_fixture_dir` — the one guard the P1b scanner recognises — is called on): `$TMP/api/<path-suffix>` holds a body file and a `.status` file; `api-fetch.sh` is one `cat` pair keyed by its argument, with a distinct "no such entry" shape for the transport-failure case. `_stub_run <id> key=value…` (keys: `head_sha`, `conclusion`, `status`, `path`, `event`, `head_branch`, `created_at`, `http`, `artifacts`) writes both endpoints, defaulting artifacts to one `git-data-rung2-boot-evidence` entry so the ~20 non-artifact arms state none. The synthesized bodies carry the field set the live API returned at plan time (`id`, `path`, `status`, `conclusion`, `head_sha`, `head_branch`, `event`, `run_attempt`, `workflow_id`, `created_at`).
- **Existing-arm seeding, measured rather than assumed:** `ok.env` is written with `…/actions/runs/1`, not `R2_URL`, so the store must seed **run id 1** *and* `17250000001`, each with `head_sha` = the fixture's pre-evidence commit (`git -C "$R2" rev-parse HEAD` at that point), so the archive re-hashes to `R2_SHA`. Same for `_G_URL`/`_G_URL2` in the Guard 4 battery — **and for the two the first pass missed and a review grep found: `17253046871` (the `/job/`-suffix RELEASED arm) and `2` (the divergence RELEASED arm)**. Derive the seed list by grepping the suite for `actions/runs/[0-9]+` rather than by hand; a missed id turns a green arm red on merge.
- **Helper arg names:** extend `_r2_evidence_write` with `$6=sentry_verdict` (default `CLEAN`) and `$7=ack`. `$2` is already `verdict` (`RUNG2_BOOT_REHEARSAL`); do not overload the word.
- **New RED arms** (each needle is the token **with its `HOLD [` prefix**, per `cq-assert-anchor-not-bare-token`). The S and R rows are one-line truth-table rows, so they are driven by a **data table** (`verdict | ack | expected token`) feeding `r2check`, one named row per line — and each family pins its own row count inline (`_expect_rows S 12`), because an emptied or mis-parsed heredoc increments nothing and neither the floor nor the ledger reconciliation can see which family vanished:
  - S1 no `RUNG2_SENTRY_CROSSCHECK` → `exactly 1 is required`; S2 `NOT_RUN` → `HOLD [SENTRY_VERDICT_UNREADABLE]`; S3 `FATAL` → `HOLD [SENTRY_VERDICT_FATAL]`; S4 empty value → `HOLD [SENTRY_VERDICT_UNREADABLE]`; S5 `clean` (wrong case) → same
  - S6 `UNAVAILABLE`, no ack → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`; S7 ack for another run id → `HOLD [SENTRY_ACK_MISMATCH]`; S8 ack with an empty reason → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`; S9 `<id>: reason with spaces` (space after the colon) → `RELEASED`, and the RELEASED line names `acknowledged`; S10 ack whose reason contains `#` → HOLD naming the comment strip; S11 two ack lines → the **at-most-once** message (not the required-key text); S12 ack beside `CLEAN` → `RELEASED` (ignored, not refused)
  - R1 no stub entry (transport failure) → `HOLD [RUN_UNRESOLVABLE]`; R2 http 404 → `HOLD [RUN_NOT_FOUND]`; R3 http 403 with a `rate limit` message → `HOLD [RUN_RATE_LIMITED]` naming `actions: read`; R4 http 403 **without** a rate-limit body → the anonymous retry fires (the stub records a second call) and the arm passes; R5 http 200 non-JSON → `HOLD [RUN_UNRESOLVABLE]`; R6 `.id` mismatched → same; R7 `…/runs/123abc` in the URL → the id parses as `123abc`, never a silent `123`
  - R8 `path: …/apply-web-platform-infra.yml` → `HOLD [RUN_WRONG_WORKFLOW]`; R9 `event: schedule` → `HOLD [RUN_WRONG_EVENT]`; R10 `head_branch: feat-x` → `HOLD [RUN_NOT_MAIN]`; R11 `status: in_progress, conclusion: null` → `HOLD [RUN_NOT_COMPLETED]`; R12 `conclusion: failure` → `HOLD [RUN_NOT_SUCCESS]`; R13 `conclusion: cancelled` → same
  - A1 artifacts `total_count: 0`, run 3 days old → `HOLD [RUN_NO_EVIDENCE_ARTIFACT]` (the **dry-run shape**); A2 only `git-data-rung2-capture-log` listed → same; A3 the evidence artifact with `expired: true` → `RELEASED`; A4 `total_count: 0` with `created_at` 200 days old → `HOLD [RUN_ARTIFACT_RECORD_UNREADABLE]`; A5 artifacts endpoint 404 → same
  - H1 `head_sha` not in the fixture repo → `HOLD [RUN_SHA_UNREACHABLE]`; H2 `head_sha` = a commit whose tree edits one payload while the live tree still matches → `HOLD [RUN_HASH_MISMATCH]` — the C21 "last-touch laundering" shape as a row; H3 `head_sha` = the capture commit, evidence committed later alone → `RELEASED` naming the run id and `head_sha`; H4 the fixture where the cloud-init dir **is** the repo root (`_g_repo`'s shape) → `RELEASED`, pinning the `<sha>:` tree-ish form; H5 a `head_sha` whose module shape makes the hash function ABORT → `HOLD [RUN_HASH_UNCOMPUTABLE]`; H6 shallow fixture clone → the existing Guard 4 HOLD fires first (order pin)
  - T1 `jq` shadowed absent on `PATH` → `ABORT [TOOLING_MISSING]` naming `jq`, **before** any stub call (assert the stub recorded zero invocations)
  - E1 with `GITHUB_ACTIONS=true` and a could-not-measure token, the output carries one `::error::` line; E2 with a measured-refusal token it does not
- **`mutate_r2`/`mutate_g` must gain a needle argument before any MUT row is written.** Both compare `rc` to `want_rc` and never inspect the output, so every HOLD→HOLD **token-swap** row (Guard 1 rows 9 and 10, Guard 2 row 6, Guard 3 row 3) would pass whether or not the mutant landed — `cmp -s` proves the file differs, not that the edit hit the region under test. Add a 4th argument asserting the pre-mutation token is now **absent** and the collapsed one present, and anchor each `sed` to the target function's line range.
- **Harness row (a) needs a helper that does not exist.** Every guard's harness row (a) is a *suite* mutation ("change `_stub_run`'s default `conclusion`", "change `_r2_evidence_write`'s default sentry_verdict", "mismatch the `HOST`/`URL` constants"), while `mutate_r2`/`mutate_g` mutate `$GATE`. Add `mutate_suite <label> <sed> <expect-fails>` that re-runs the suite file under a recursion sentinel and asserts the expected number of failures — otherwise those four rows are one-time manual acts that could never detect a later stubbed-out suite.
- **Arms that need fixture work the current helpers cannot produce:** H5 needs a *historical* commit whose module binds fewer payloads than the floor while the worktree stays canonical (`_r2_write_module "$d" "${_r2_payloads[@]:0:8}"` as c1); T1 needs a symlink-farm `PATH` that keeps `git`/`sed`/`grep`/`sha256sum`/`tar`/`curl` and drops only `jq`, restored explicitly rather than in a subshell (a subshell loses `pass()`); A1/A3/A4 must compute `created_at` with `date -u -d '<n> days ago'` and assert only the token, never an exact age, so the 90-day boundary cannot drift under them. **No current fixture puts the cloud-init in a subdirectory** — `$R2`, `_g_repo` and `$FIX` are all repo-root-shaped — so a subdirectory fixture must be added or Guard 2 row 5's `<sha>:<repo-rel-dir>` branch never executes.
- **Vacuity pairing for the two pure negatives.** Guard 1 row 12 (marker file absent) and T1 (no stub call) are true for the wrong reasons too — a mis-pathed stub, or a fixture that HOLDs at Guard 4 before step C runs. Pair each with a positive control in the same shape (same arm with `SOLEUR_TEST_MODE=1` → marker present; the stub's call counter proven to increment), and drop row 12's URL-host override: adding one would be a second seam outside the `SOLEUR_TEST_MODE` gate, i.e. the row would create the hole it tests. Seed an entry that must not be read instead.
- **MUT rows** via `mutate_r2`/`mutate_g`, per the Guard Contract below.
- **Floor:** `_FLOOR=150` is raised **by hand** to the **measured** new total and itemised in a `RAISED 150 -> N (#8010), ITEMISED:` block beside the five existing raise blocks (families: S 12 · R 13 · A 5 · H 6 · T 1 · E 2 · Guard-1 MUT 12 · Guard-2 MUT 7 · Guard-3 MUT 8 · must-PASS non-canonical 4, plus the pairing controls above). Measure the real count from a green run and write that number — never ship the prediction. Baseline measured at plan time: **150 passed, 0 failed, floor 150** — zero slack, so every added assertion must be accounted for. The ledger reconciliation compares `${#FAILURES[@]}` to `fails` and cannot see a stale floor, and the floor is a single global counter, so it is the right instrument for "a family was deleted" and the wrong one for "which family" — that is what the per-family `_expect_rows` pins are for.

`tests/scripts/test-git-data-rung2-evidence-capture.sh`:

- **First, the arm that would break:** the producer/consumer arm (`gate_out="$(git_data_rung2_rehearsal_gate "$FIX/cloud-init-git-data.yml" "$OUT_TRACKED" …`) calls the **real** gate with `…/runs/17250000001` and no seam. Under the new gate it makes a live call, 404s, and a currently-green arm goes red while the suite stops working offline. Give it the same exported seam and a stub whose `head_sha` is the fixture's own commit; `$FIX` is a repo-root-is-the-template fixture, so it also exercises the `<sha>:` form.
- C1 `--host-name …-17250000002` with `--evidence-url …/runs/17250000001` → rc 64 naming both values; C2 the matched pair still accepted; C3 the `--liveness` argv carries `--stats-period 24h` **even when `--since` is passed**, while the same run's `--host-events` argv still carries `--start/--end` (ARM 26's pinned shape stays); C4 ARTIFACT 4 records the liveness query line; C5 the reset arm's recorded `--end` is a `YYYY-MM-DDTHH:MM:SS` timestamp equal to what the stub saw, never the literal `<now>`; C6 the token-unset branch writes `RUNG2_SENTRY_CROSSCHECK=NOT_RUN`, not `UNAVAILABLE`.
- `_FLOOR=107` raised and itemised the same way (`C1–C6` 6 · Guard-4 MUT 3 · the `/attempts/2` must-PASS 1), from a measured run.

`apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`: one arm asserting the post-reboot summary emits exactly one of `ACK REQUIRED` / `ACK NOT REQUIRED`.

Run all three suites plus `plugins/soleur/test/terraform-target-parity.test.ts` and the `fixture-relative-assert` baseline; record the RED count in the PR body.

#### Phase 2: GREEN — the gate

`_git_data_rung2_fetch`, `_git_data_rung2_check_run`, `_git_data_rung2_check_artifacts`, `_git_data_rung2_hash_at_sha` as separate functions above the gate, each with a header in the file's house style (property; what it does NOT prove; every fail-closed case named). Wire steps A–E after Guard 4; extend the RELEASED line; update the Guard 4 header's residual paragraph ("Closing that requires resolving the run … #8010's scope") to record what is now closed and what is not.

#### Phase 3: GREEN — the capture, the workflow, the probe, the docs

The six capture edits, the three workflow summary edits, the one probe sentence, the runbook and ADR-149 edits, and the `model.c4` sentence (the `c4-model-regenerate` pre-commit hook re-renders `model.likec4.json`; run `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 render/freshness tests).

#### Phase 4: Live verification and the in-flight evidence

- Run the real gate (no stub) against the recorded evidence of run 34768256297 (`git show 273f29a80:apps/web-platform/infra/git-data-rung2-boot-evidence.env`) in a scratch checkout at `15fd63aff…`: with an ack line → `RELEASED` naming run 34768256297; without → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`.
- Run it against the exact bytes PR #8393 commits (run 35465756680; re-fetchable with `gh run download 35465756680 -n git-data-rung2-boot-evidence`) placed in a scratch checkout of `d64430c26`: without an ack → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`; with `RUNG2_SENTRY_CROSSCHECK_ACK=35465756680:run-pinned liveness window on a quiet project, retired by this PR` → `RELEASED`.
- Run it against a hand-written file naming dry run 33886787297 with `main`'s live hash → `HOLD [RUN_NO_EVIDENCE_ARTIFACT]`.
- **Sequencing, decided rather than conditional.** After syncing `main`: if #8393 has merged, this PR appends the ack line to the committed evidence in its **own commit that touches no hash-bound file** (this PR touches none — the roster is 17 entries, measured with `git_data_rung2_bound_files`: the cloud-init, the render module's three `.tf` files and its thirteen `file()`-bound payloads — so both Guard 4 arms pass). If #8393 has not merged, `main` carries no evidence at all, the gate's no-evidence HOLD is the designed state, and the ack line must be carried by #8393 itself; say so in that PR. Either way `main` is never left HELD by *this* change.
- File the blocker issue (QG5): add `actions: read` to the two apply jobs, the `infra-validation.yml` freshness step and the sweeper; thread `GH_TOKEN: ${{ github.token }}`; convert the three call sites' binary `if !` into a tri-state that distinguishes an instrument failure from a HOLD (with the matching `terraform-target-parity.test.ts` regex); and reorder the freshness step after the guards it can otherwise blank. Milestone `Phase 4: Validate + Scale`, linked from roadmap L27 and #8361, marked as blocking the L27 birth/replace dispatch (CPO condition 2).
- `gh issue edit 8010 --milestone "Phase 4: Validate + Scale"` (CPO condition 1 — the milestone name was read from the live milestone list, not guessed).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Promote the host name to a `RUNG2_REHEARSAL_HOST` key and require it | Evidence from the current capture would be unreadable, and a key beside the URL in the same hand-editable file proves consistency, not integrity. Delivered instead by run resolution + the capture-side refusal. |
| Read the host-name comment raw | Reverses a deliberate gate decision for a weaker check than run resolution. |
| `git merge-base --is-ancestor <head_sha> origin/main` instead of `.head_branch == "main"` | Proposed by the advisor consult (a branch label survives a force-push), adopted, then **cut** at review: it satisfies no listed property that `head_branch` + reachability do not, a removed commit already HOLDs at `RUN_SHA_UNREACHABLE` because the archive needs it, no fixture has an `origin/main` ref (every existing RELEASED arm would have turned into a HOLD), and on a laptop with a stale `origin/main` it reports a *refusal* token for a *could-not-measure* condition. |
| Assert per-step conclusions via the jobs API to exclude dry runs | Right concern, wrong endpoint: step data is **not durable** (run 23814647816, 172 days, lists jobs with `steps: []`), so the gate would time-bomb on older evidence. The artifacts listing keeps its records with `expired: true`. |
| Encode the dispatch mode in `run-name:` / assert `display_title` | Durable and single-endpoint, but run 35465756680's title is the default, so PR #8393's evidence would HOLD. Recorded as future hardening once every live evidence file postdates it. |
| Have the capture write the dispatch mode into the evidence | Adds nothing against the threat: the file is hand-writable, which is precisely why the discriminator must live outside it. |
| `workflow_id` (numeric) instead of `path` | Changes if the workflow is deleted and recreated; `path` is what this repository reviews. Both are in the fixtures; only `path` is asserted. |
| Download the run's evidence artifact and byte-compare | Artifact **contents** expire at 90 days; only the record persists. The gate would HOLD forever after expiry. |
| `gh api` | `gh` refuses to run in Actions without `GH_TOKEN`; `curl` is present on every surface, including the `env -i` sweeper. |
| Forward `actions/checkout`'s persisted `http.…extraheader` to `api.github.com` | Proposed to authenticate the un-editable call sites. **Cut:** it forwards a credential to a destination it was not issued for (the class #7898's confinement backlog exists for), it is a complete header line rather than a bearer value so it cannot even ride the same chain, and it was never measured against `api.github.com` — and it buys nothing anyway, because those jobs' `GITHUB_TOKEN` lacks `actions: read` (measured: no call site grants it). |
| `gh auth token` as a third credential | An operator can `export GH_TOKEN`; the chain stays two-deep plus anonymous. |
| Honour `retry-after`/`x-ratelimit-reset` with a bounded sleep | The only reason the seam would need response headers. A rate limit on an hourly window is not waited out in 60 s; HOLD immediately with the remedy. |
| Bound the evidence's age, or require `head_sha` to be an ancestor of the gated `HEAD`, to stop a downgrade | The downgrade shape is real and is recorded as a residual rather than closed here: revert `apps/web-platform/infra` to a tree some past rehearsal genuinely booted, then commit evidence citing that old run — every check in C, D and E passes honestly. An age bound forces periodic re-rehearsal at a paid host for no property gain when nothing moved, and an ancestor-of-`HEAD` check is satisfied by the revert itself. What actually catches it is **Guard 4 ARM 2**, which sees the whole PR range (bound files edited *and* the evidence added) — and ARM 2 is advisory only because `deploy-script-tests` is not a required check. Making it required is therefore folded into the blocker issue (QG5), which is the honest remedy, and the residual is named in ADR-149. |
| Let the **replace** route proceed when the network is unreachable (the hash binding is local) | A technical fork, decided here rather than asked (`hr-technical-fork-is-not-an-operator-question`): an instrument failure releasing the last hold on the host that will store every user's source is the fail-open shape this issue exists to remove. Mitigated instead by naming the remedy, by the gate's own `::error::` line, and by the blocker issue that gives CI a working credential. |
| Hard-HOLD `UNAVAILABLE` with no ack path | Would hold every quiet-window rehearsal, including PR #8393's evidence. The ack is run-bound so it cannot be copied forward. |
| Accept `UNAVAILABLE` when the reset arm reports `RUNG2_REBOOT_REOPEN_CHANNEL ∈ {both, sentry}` (Sentry answered for this host) | Drafted, then **cut** at review: it adds three keys to the cardinality mechanism, six suite arms and two guard rows to satisfy a property the run-bound ack already satisfies — and the coordinator's own constraint names "an explicit operator-ack key" as an accepted alternative. Worth revisiting only if `UNAVAILABLE` recurs after the 24 h liveness fix, which the ADR-149 tripwire watches for. |
| Thread `GH_TOKEN`/`actions: read` into `infra-validation.yml` in this PR | The brief scopes this PR to one workflow. Surfaced as a decision-challenge rather than decided here; it is the first item of the blocker issue. |
| `actions/attest-build-provenance` + a committed Sigstore bundle | Would bind run identity and payload digest with no network, `jq`, `tar` or git history at verify time. The brief mandates REST resolution; recorded in ADR-149's Future Considerations so the next maintainer does not re-ask. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly on day one — the git-data store serves no user traffic while `GIT_DATA_STORE_ENABLED` is off. The two failure shapes are (a) a spurious HOLD on the birth/replace routes (rate-limited, offline, or unreachable history), delaying remediation of the host that will hold every connected user's source, and (b) a fail-open path that releases a forged or laundered attestation, which is how a dark-booted host holding user repositories would come to exist.
- **If this leaks, the user's data is exposed via:** no new exposure — the gate reads public run metadata over TLS and sends a bearer only to `api.github.com` when one is set; the evidence file carries no user data. A `curl` error path that echoed headers would leak a CI token, which is why stderr is captured to a file and never printed, and why the persisted-checkout-header idea was cut.
- **Brand-survival threshold:** `single-user incident` — this gate is the mechanical hold on the host that will store every connected user's source code; #8262 and #8312 on the same queue were raised to this threshold at their plan boundaries.
  - artifact: a git-data host born or replaced from an un-rehearsed template → exposure vector: a dark boot holding user repositories that no rehearsal proved.
  - artifact: the replace route held by a spurious instrument failure → exposure vector: delayed remediation of the live host (mitigated: the gate emits its own `::error::` naming the instrument, the HOLD names the remedy, and the blocker issue gives CI a working credential).
  - artifact (post-cutover, CPO condition 3): once `GIT_DATA_STORE_ENABLED` flips, the replace route is the **recovery path for every connected user's repositories**, so a spurious HOLD there extends an outage (RTO), not merely a remediation delay → `git-data-birth.md` names the fallback order (re-run the gate locally with `GH_TOKEN` exported to confirm the HOLD is an instrument failure, then re-dispatch), and the credential work is filed as blocking the L27 dispatch rather than as a loose follow-up.

`requires_cpo_signoff: true` (frontmatter); CPO signed off with four conditions, all applied. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "the gate is exercised on every PR by infra-validation.yml's 'Rung-2 evidence freshness' step whenever an evidence file is committed, daily by the #8210 follow-through probe, and by the birth/replace jobs before any apply; each emits one RELEASED/HOLD line carrying exactly one bracketed reason token"
  cadence: "per PR touching the infra paths / daily (sweeper) / per birth or replace dispatch"
  alert_target: "a red deploy-script-tests check on the PR; the sweeper's comment on #8210; a failed birth/replace job with the gate's own ::error:: annotation"
  configured_in: ".github/workflows/infra-validation.yml (freshness step); .github/workflows/scheduled-followthrough-sweeper.yml (probe); .github/workflows/apply-web-platform-infra.yml (two interlock steps, unchanged and inert until #8361)"

error_reporting:
  destination: "layer 6 — the synchronous workflow-run log plus a gate-emitted ::error:: annotation on instrument failures. Layers 1-5 are N/A (no runtime host, no Sentry DSN, no cron surface); layer 7 is N/A (not a customer-executed plugins/ surface). NOTE: the ::error:: annotation has NO reach on the sweeper path — scripts/sweep-followthroughs.sh runs probes under `env -i` with a pinned name list, so GITHUB_ACTIONS is not forwarded and the guard never fires, and the probe's output is captured into an issue-comment body where ::error:: is inert text. That surface's operator-visible channel is the sweeper's own verdict heading plus the probe-printed token line"
  fail_loud: "every refusal is a single 'git_data_rung2_rehearsal_gate: HOLD [<TOKEN>] — …' line on stdout and a non-zero exit; could-not-measure tokens additionally emit ::error:: under GITHUB_ACTIONS so the callers' fixed 'no rung-2 boot evidence' text is not the only thing an operator reads"

failure_modes:
  - mode: "api.github.com rate-limits the anonymous call (every CI site is anonymous: no caller grants actions: read)"
    detection: "HOLD [RUN_RATE_LIMITED] naming the actions: read + GH_TOKEN remedy and the blocker issue; plus the gate's ::error:: line"
    alert_route: "layer 6 — the calling step's run-log line and the gate's ::error:: annotation; on the daily sweeper path instead the CANNOT ESTABLISH verdict heading on #8210 carrying the bracketed token"
  - mode: "no network path to api.github.com (operator laptop, restricted runner)"
    detection: "HOLD [RUN_OFFLINE] on the first attempt (curl rc 6/7), no retry ladder"
    alert_route: "the operator's terminal"
  - mode: "the run's head_sha is not in the checkout (shallow clone, unfetched main)"
    detection: "HOLD [RUN_SHA_UNREACHABLE] naming git fetch origin main"
    alert_route: "red check / failed job"
  - mode: "an evidence file names a run that did not boot its bytes (laundering)"
    detection: "HOLD [RUN_HASH_MISMATCH] naming both hashes and the run's head_sha"
    alert_route: "red check / failed job"
  - mode: "an evidence file names a dry_run/teardown_only dispatch"
    detection: "HOLD [RUN_NO_EVIDENCE_ARTIFACT] — that run uploaded no boot-evidence artifact"
    alert_route: "red check / failed job"
  - mode: "a transient HOLD in the freshness step blanks the eight guard steps after it (that file's own reasoning at its provenance-guard comment)"
    detection: "the red step names a could-not-measure token, so the blanking is attributable rather than mysterious"
    alert_route: "red deploy-script-tests (not a required check); the step reorder is in the blocker issue"
  - mode: "the capture's Sentry read path is dead rather than merely quiet"
    detection: "RUNG2_SENTRY_CROSSCHECK=UNAVAILABLE with the 24 h liveness anchor at count 0 — the run summary prints ACK REQUIRED and the gate HOLDs until acknowledged; NOT_RUN (never consulted) is refused outright and cannot be acked"
    alert_route: "the human landing the evidence PR"

logs:
  where: "Actions job log of the calling step; the rehearsal run's step summary for the capture verdict and the ack decision"
  retention: "90 days (Actions log retention); the RELEASED/HOLD line is also in the PR check output"

discoverability_test:
  command: "bash tests/scripts/test-git-data-birth-readiness-gate.sh"
  expected_output: "the suite's final ledger line reports 0 failures and an assertion count at or above its raised floor, including the S/R/A/H/T/E arms"
```

Expected API budget, stated because it is shared: at most 2 requests per gate call, one freshness-step call per infra PR plus one sweeper call per day, all on the anonymous 60/h-per-IP budget until the blocker issue lands.

## Encryption Posture

```yaml
in_transit:
  - connection: "git_data_rung2_rehearsal_gate (CI runner or operator workstation) -> api.github.com (GET /repos/jikig-ai/soleur/actions/runs/<id> and .../artifacts)"
    enforced_at: "tests/scripts/lib/git-data-birth-readiness-gate.sh:_git_data_rung2_fetch (https:// literal in the URL; curl default verification; --disable so no ~/.curlrc can weaken it)"
    tls: "HTTPS, TLS 1.2+ as negotiated by curl against GitHub's edge"
    cert_verification: "on (curl default; no -k/--insecure/-D -/-v anywhere in the function). Asserted by a source-grep arm over the gate library, not by a behavioural row: the suite runs with the fetch seam active, so the real curl invocation never executes and a mutation row could not redden on it"
    does_not_defend: "a compromised GH_TOKEN/GITHUB_TOKEN in the caller's env (sent as a bearer when set); GitHub returning stale or wrong run metadata; an attacker who can dispatch the rehearsal workflow from main"
    disclosed_as: "not-publicly-claimed"
```

No persistent store is introduced; the evidence file's at-rest posture is unchanged (a committed text file in a public repository). No credential is read from disk — the cut extraheader path is the one that would have.

## Guard Contract

### Guard 1 — the resolved run

**Property.** The gate releases only if the run id in `RUNG2_EVIDENCE_URL` resolves, through the GitHub REST API, to a `workflow_dispatch` run of `.github/workflows/git-data-rung2-rehearsal.yml` on `main` that completed with `conclusion == success` **and uploaded a `git-data-rung2-boot-evidence` artifact** (a `dry_run`/`teardown_only` dispatch also concludes `success` and does not).

**Assembly.** One chokepoint: `git_data_rung2_rehearsal_gate` is the only function that reads the evidence file for release purposes, and every release path calls it — the two apply jobs, the freshness step, the #8210 probe, the runbook's local invocation. Inside it, `_git_data_rung2_check_run` and `_git_data_rung2_check_artifacts` are the only interpreters of the two bodies, called once each per gate call. The fetch seam sits below both parsers and is keyed by URL path suffix, so every field check on both bodies runs in the suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `.conclusion == "success"` comparison | RED (R12, R13) |
| 2 | Delete the `.path` comparison | RED (R8) |
| 3 | Delete the `.event` / `.head_branch` comparisons | RED (R9, R10) |
| 4 | Delete the artifacts GET (own dispatch of the second clause: a run with no artifacts must not read as a capture) | RED (A1) |
| 5 | Match the artifact name by prefix (`git-data-rung2-`) instead of exactly | RED (A2 — the capture-log artifact) |
| 6 | Treat `expired: true` as absent | RED (A3) |
| 7 | Replace the fetch with `printf '{}\n200'` (a body with no fields must not read as a run) | RED (R6, H3) |
| 8 | Return rc 0 with an empty body on transport failure | RED (R1) |
| 9 | Treat HTTP 404 as `RUN_UNRESOLVABLE` (collapsing "measured absent" into "could not measure") | RED (R2's token needle) |
| 10 | Collapse `RUN_RATE_LIMITED` into `RUN_UNRESOLVABLE` | RED (R3) |
| 11 | Second member: evidence carrying two `RUNG2_EVIDENCE_URL` lines, the first resolvable | RED (existing cardinality arm — pinned) |
| 12 | Remove the `SOLEUR_TEST_MODE` half of the seam's double gate | RED (a harness arm sets only `SOLEUR_RUNG2_RUN_FETCH`, points the seam at a stub that writes a marker file, and asserts the marker is **absent**; the URL host is overridden to an unroutable literal and attempts capped at 1, so the row never touches the network or the anonymous budget) |

**Harness rows.** (a) Suite mutation: change `_stub_run`'s default `conclusion` to `failure` — every RELEASED arm must go RED (proves the arms read the stub, not a constant). (b) Must-PASS non-canonical input: a run body with extra fields (`actor`, `jobs_url`), `run_attempt: 2`, and an evidence URL carrying `/attempts/2` → RELEASED (re-run attempts and unknown fields are permitted).

**Anchor — stated at its real strength, not one level too high.** The stored values are compared to something outside the commit: GitHub's **past** run records and artifact listings are immutable, so weakening the evidence and the record together requires dispatching a real `main` rehearsal that actually captures. What it does **not** anchor is the **producer**: `git_data_rung2_bound_files` binds the cloud-init, the render module's `.tf` files and the payloads (17 entries, measured) — it binds neither `.github/workflows/git-data-rung2-rehearsal.yml` nor `scripts/followthroughs/git-data-rung2-evidence-capture.sh`. A merge to `main` that rewrites the rehearsal workflow into a no-op uploading an artifact of the right name, followed by a dispatch from `main`, satisfies `path`, `event`, `head_branch`, `status`, `conclusion`, the head-SHA hash **and** step E at once. So Guard 1 proves *"a workflow at that path ran on main and produced a boot-evidence artifact"*, not *"a rehearsal happened"*. That residual is bounded by the same missing control the gate's own URL-shape HOLD already names — `main` carries no required-review ruleset — and closing it is a producer-binding question (a `RUNG2_PRODUCER_SHA256` over the workflow + capture, recomputed at the run's `head_sha`), recorded in ADR-149 and filed, not claimed here. Binding those two files into the existing roster is **not** the fix: the roster is "what renders into user_data", and this very PR edits the workflow, so it would void its own evidence.

### Guard 2 — the head-SHA hash binding

**Property.** The user_data hash computed from the tree at the resolved run's `head_sha` equals `RUNG2_TEMPLATE_SHA256` (which, as today, must also equal the live hash).

**Assembly.** `_git_data_rung2_hash_at_sha` is the only path; it delegates to `git_data_rung2_user_data_sha256`, the single derivation shared with the live check and the capture, so the two cannot drift. Its input is a `git archive <head_sha>:<repo-rel-dir>` extraction of the evidence's own repository, with the toplevel derived as Guard 4 derives it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the hash comparison with `true` | RED (H2) |
| 2 | Compare against the LIVE hash instead of `claimed_sha` | RED (H2 — live matches, the run does not) |
| 3 | Skip `cat-file -e` and let the archive fail silently (`|| true`) | RED (H1 — must be `RUN_SHA_UNREACHABLE`, not a mismatch or a release) |
| 4 | Archive `HEAD` instead of `<head_sha>` (own dispatch: the function must consume the resolved sha) | RED (H2) |
| 5 | Use the pathspec form `git archive <sha> -- <dir>` instead of the tree-ish form | RED (H4 — the root-dir fixture is fatal; every arm reddens on the path arithmetic) |
| 6 | Report an ABORT from the hash function as a mismatch | RED (H5) |
| 7 | Second member: a run whose `head_sha` tree matches but whose evidence claims a different hash (claimed ≠ live) | RED (the existing STALE EVIDENCE arm fires first — order pinned by H6) |

**Harness rows.** (a) Suite mutation: point `_stub_run`'s default `head_sha` at the fixture's *evidence* commit instead of its pre-evidence commit — H3 must stay green (that commit touches no bound file) while a sibling arm whose c2 edits a payload goes RED. (b) Must-PASS non-canonical: `head_sha` = a later commit that changed only a non-bound file → RELEASED.

**Anchor.** The sha comes from GitHub's run record (Guard 1's anchor); the tree at that sha is immutable content-addressed history.

### Guard 3 — the Sentry verdict

**Property.** The gate releases only if `RUNG2_SENTRY_CROSSCHECK` is present exactly once and is `CLEAN`, or is `UNAVAILABLE` and `RUNG2_SENTRY_CROSSCHECK_ACK` is present exactly once with value `<this run's id>:<non-empty, #-free reason>`. `FATAL` and `NOT_RUN` are refused and cannot be acked.

**Assembly.** Two cardinality mechanisms, both evaluated before the value `case`: the existing exactly-once loop, which `RUNG2_SENTRY_CROSSCHECK` joins, and a new at-most-once loop for the optional `RUNG2_SENTRY_CROSSCHECK_ACK` (the required loop refuses absence, which is wrong for an optional key, and its pattern does not match the `_ACK` suffix). The ack's run id is compared to the id Guard 1 parses from `RUNG2_EVIDENCE_URL` — one parse, two consumers.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `RUNG2_SENTRY_CROSSCHECK` from the required loop | RED (S1) |
| 2 | Add `NOT_RUN` (or a `*` catch-all) to the accepted `case` arms | RED (S2) |
| 3 | Merge `SENTRY_VERDICT_FATAL` into `SENTRY_VERDICT_UNREADABLE` (measured vs could-not-measure) | RED (S3) |
| 4 | Accept an ack without comparing its run id | RED (S7) |
| 5 | Accept an ack whose reason is empty after trimming | RED (S8) |
| 6 | Own dispatch: make the verdict read `CLEAN` when the grep returns nothing | RED (S1, S4) |
| 7 | Second member: two ack lines, the first well-formed | RED (S11) |
| 8 | Run the value `case` before the cardinality loops | RED (S11 — a duplicate ack would be read as one) |

**Harness rows.** (a) Suite mutation: change `_r2_evidence_write`'s default **sentry_verdict** from `CLEAN` to `UNAVAILABLE` — every RELEASED arm that passes no ack must go RED. (b) Must-PASS non-canonical: `CLEAN` with trailing whitespace and a trailing `# comment`; and an `UNAVAILABLE` file whose ack reason contains a colon and spaces → both RELEASED.

**Anchor.** None for the ack itself, and the plan says so: it lowers the second-channel requirement for one named run and never substitutes for Guards 1–2. The run-binding is what stops the declaration surviving a copy into the next file, and ADR-149's tripwire is what stops it becoming routine.

### Guard 4 — the capture writes only a coupled host/run pair

**Property.** `git-data-rung2-evidence-capture.sh` never writes an evidence file whose `--host-name` suffix differs from the run id in `--evidence-url`.

**Assembly.** The single arg-parse block after the two existing shape checks; both values are validated there and nowhere else, and the writer reads the same two variables.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the suffix comparison | RED (C1) |
| 2 | Own dispatch: compare `HOST_NAME` to itself | RED (C1) |
| 3 | Second member: `--host-name` given twice, first coupled and second not (last-wins parse) | RED (C1 variant) |

**Harness rows.** (a) Suite mutation: set the suite's `HOST`/`URL` constants to a mismatched pair — every PASS-path capture arm must go RED. (b) Must-PASS non-canonical: `--evidence-url …/runs/17250000001/attempts/2` with the canonical host → accepted.

**Anchor.** Not applicable — a write-time input check, anchored at read time by Guard 1.

## Acceptance Criteria

### Functional Requirements

- [ ] FR1 `git_data_rung2_rehearsal_gate` requires `RUNG2_SENTRY_CROSSCHECK` exactly once and `RUNG2_SENTRY_CROSSCHECK_ACK` at most once, both counted before the value `case`; `CLEAN` releases; `UNAVAILABLE` releases only with an ack matching `<url-run-id>:<non-empty, #-free reason>` (optional whitespace after the colon); `FATAL` → `HOLD [SENTRY_VERDICT_FATAL]`; `NOT_RUN`/empty/unknown → `HOLD [SENTRY_VERDICT_UNREADABLE]`; a wrong-run ack → `HOLD [SENTRY_ACK_MISMATCH]`; no ack → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`; an ack beside `CLEAN` is ignored.
- [ ] FR2 The gate resolves `GET https://api.github.com/repos/jikig-ai/soleur/actions/runs/<id>` with `curl --disable --noproxy '*' -sS --max-time 20 -w '\n%{http_code}'` and a bash-array auth header (bearer from `GH_TOKEN` → `GITHUB_TOKEN`, else none; one anonymous retry on a non-rate-limit 401/403), 2 attempts on 5xx/transport separated by `SOLEUR_RUNG2_RETRY_SLEEP`, fast-fail on curl rc 6/7, no response-header parsing, stderr captured to a temp file and never printed — and holds with `RUN_OFFLINE`, `RUN_RATE_LIMITED`, `RUN_UNRESOLVABLE`, `RUN_NOT_FOUND`, `RUN_WRONG_WORKFLOW`, `RUN_WRONG_EVENT`, `RUN_NOT_MAIN`, `RUN_NOT_COMPLETED`, `RUN_NOT_SUCCESS` as specified.
- [ ] FR3 The gate requires the run's `head_sha` to be present in the checkout (no fetch; `RUN_SHA_UNREACHABLE` names `git fetch origin main`), then re-hashes `git archive <head_sha>:<repo-rel-dir>` (and `<head_sha>:` when that dir is the repo root) with attributes disabled, extracted with `tar -x --no-same-owner --no-same-permissions` and swept for symlink/hardlink entries (refused as `RUN_HASH_UNCOMPUTABLE`) before `git_data_rung2_user_data_sha256` reads it; the extraction directory is left to be reclaimed by the runner, annotated `# lint-trap-ownership: ok <reason>`, with `scripts/lint-trap-tempfile-ownership.highwater` raised by one — never an `EXIT` trap over the caller's, and never a variable-rooted `rm -rf`. `RUN_HASH_MISMATCH` on inequality.
- [ ] FR4 After the local git checks, the gate lists `…/runs/<id>/artifacts` and requires an artifact named exactly `git-data-rung2-boot-evidence` (expired allowed); absent on a run younger than 90 days → `RUN_NO_EVIDENCE_ARTIFACT`; absent on an older run, or an unusable response → `RUN_ARTIFACT_RECORD_UNREADABLE`.
- [x] FR5 **AMENDED 2026-09-20 (review round, commit `237a49299`).** Original named only `jq`, `curl` and `tar` — and that understatement is precisely what let P1 #3 through: `find` is load-bearing in the archived-tree symlink/hardlink sweep and was absent, so shadowing it made the sweep fail OPEN. As shipped, `command -v` is checked over **`jq curl tar find sha256sum`** before the first network attempt, ABORTing with `[TOOLING_MISSING]` naming the binary and a remedy. A tooling list is a claim about what the library CALLS, not about what the author remembered; re-derive it from the call sites when either changes.
- [ ] FR6 The RELEASED line names the resolved run id, its `head_sha`, `concluded success`, the artifact found, and the Sentry verdict (`CLEAN` or `UNAVAILABLE acknowledged: <reason>`).
- [ ] FR7 Under `GITHUB_ACTIONS`, a could-not-measure token additionally emits one `::error::` line naming the instrument failure; a measured refusal does not.
- [ ] FR8 The test seam `SOLEUR_RUNG2_RUN_FETCH` is honoured only under `SOLEUR_TEST_MODE`, is invoked with the URL path suffix, returns body + status only, and says so when set without `SOLEUR_TEST_MODE`; the suite exports both plus `SOLEUR_RUNG2_RETRY_SLEEP=0` at top level so `mutate_r2`/`mutate_g` child shells inherit them.
- [ ] FR9 The capture refuses (exit 64) a `--host-name` suffix that differs from the `--evidence-url` run id.
- [ ] FR10 The capture's `--liveness` read uses `--stats-period 24h` regardless of `--since` (at the call site, no new helper); the `--host-events` fatal read keeps its run-pinned `--start/--end`; ARTIFACT 4 records both query lines and scopes the key to the pre-reset window.
- [ ] FR11 The capture's never-consulted branches (`jq` missing, token unset, reader missing) write `RUNG2_SENTRY_CROSSCHECK=NOT_RUN`, not `UNAVAILABLE`.
- [ ] FR12 The reset arm's recorded `--stage luks_reopen_ok` query line carries the resolved `--end` timestamp, never the literal `<now>`.
- [ ] FR13 The rehearsal workflow emits exactly one `ACK REQUIRED …` / `ACK NOT REQUIRED …` line **after** the reset probe, CR/LF-stripped; the "land it yourself" block appends the ack **before** `git add` and tells the operator to wait for the whole run to conclude `success`. The `Rung-2 rehearsal: PASS|FAIL` and `WRAPPER FAILURE` headings are unchanged.
- [ ] FR14 The existing check order is unchanged and pinned: cardinality → PASS → URL shape → hash shape → divergence → live hash → Guard 4 → tooling → Sentry verdict → run resolution → head-SHA reachability → head-SHA hash → artifacts.
- [x] FR15 **AMENDED 2026-09-20 during the review round (commit `237a49299`) — the original text is superseded and was false against the shipped tree.** Original: "`apply-web-platform-infra.yml` and `infra-validation.yml` are not modified." As shipped: `apply-web-platform-infra.yml` is NOT modified (the brief's explicit prohibition, and it is over GitHub's 500 KB limit pending #8361), but `infra-validation.yml` IS — the nine-seat panel measured that all four gate call sites resolved the Actions run ANONYMOUSLY against the 60/h-per-IP budget, and this is the only one of the four editable this cycle. It gains `permissions: {contents: read, actions: read}` on `deploy-script-tests` and `env: GH_TOKEN` on the freshness step, plus the tri-state could-not-measure branch so an instrument failure no longer reads as "your change broke the evidence". The remaining three sites are #8397. Assert as: `git diff --name-only origin/main...HEAD` excludes `apply-web-platform-infra.yml`.
- [ ] FR16 The #8210 probe splits its could-not-measure arm out of `TRANSIENT`: `exit 2` stays for the measured pre-conditions (no evidence file, no reboot key, not on `main`), and the probe returns **`exit 3`** when the gate's first line carries any could-not-measure token (`RUN_OFFLINE`, `RUN_RATE_LIMITED`, `RUN_UNRESOLVABLE`, `RUN_SHA_UNREACHABLE`, `RUN_HASH_UNCOMPUTABLE`, `RUN_ARTIFACT_RECORD_UNREADABLE`, `SENTRY_VERDICT_UNREADABLE`, `TOOLING_MISSING`), matched on the bracketed token. `scripts/sweep-followthroughs.sh` already renders `3` as **CANNOT ESTABLISH** with "Leaving the issue open" — measured — so the safety property FR16 used to state is preserved while an instrument failure stops rendering as "NOT YET — the rehearsal simply has not run yet" every day. The probe prints the gate's full token line (not `head -1`) so the token reaches the issue comment. It still never returns PASS or FAIL on a gate refusal, and no `secrets=` clause is added to #8210's directive (the sweeper's token lacks `actions: read`). One probe-suite arm per rc.

### Non-Functional Requirements

- [ ] NFR1 Every refusal line carries exactly one bracketed token; the could-not-measure set and the measured-refusal set share no wording; each could-not-measure token names its own remedy (`actions: read` + token, `git fetch origin main`, network, install line) rather than a generic one. **Every evidence-derived value interpolated into any printed line is sanitized first** (control chars and U+2028/9 stripped; `%`, CR, LF percent-escaped; truncated to a named length), so an evidence value cannot forge a workflow command from a `pull_request`-triggered step or from the issue comment the #8210 probe's output lands in.
- [ ] NFR2 The release path makes at most two HTTP requests; worst-case wall clock is bounded by named constants (`--max-time 20`, 2 attempts, `SOLEUR_RUNG2_RETRY_SLEEP`), verified deterministically by a stub that always reports a transport failure and a call counter asserting exactly 2 invocations per endpoint — never by timing a live run.
- [ ] NFR3 No `Authorization` header value can reach stdout or the Actions log on any curl path: array-built header, xtrace saved-and-cleared for the duration of the fetch and restored on every return, stderr to a `umask 077` `mktemp` removed on every return, no `-v` / `-D -`. A suite arm greps the gate's combined output for the stub token **with the caller running `set -x`**, and the source-grep arm asserts `-k`/`--insecure`/`-v`/`-D -` are absent and `--disable`/`--noproxy '*'`/the `https://` literal are present.
- [ ] NFR4 `shellcheck` clean on all three scripts; `actionlint .github/workflows/git-data-rung2-rehearsal.yml` clean and the edited `run:` body checked with `bash -n` as an extracted snippet (never `bash -n` on the YAML); `bash tests/scripts/test-git-data-birth-readiness-gate.sh`, `bash tests/scripts/test-git-data-rung2-evidence-capture.sh`, `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts` and the `fixture-relative-assert` baseline all pass; both gate suites remain registered in `scripts/test-all.sh` (verified at plan time — not orphans, #7718).
- [ ] NFR5 Both suites' floors are raised by hand to the new totals and itemised in `RAISED <old> -> <new> (#8010), ITEMISED:` blocks (`_FLOOR=150` in the gate suite, `_FLOOR=107` in the capture suite); the ledger reconciliation cannot see a stale floor, so this is not mechanical.

### Quality Gates

- [ ] QG1 Phase 1's arms were committed RED before Phase 2 (the PR body quotes the RED count and the commit).
- [ ] QG2 Live, non-stubbed gate runs pasted in the PR body: (a) run 34768256297's recorded evidence at `15fd63aff…` → `RELEASED` with an ack, `HOLD [SENTRY_UNAVAILABLE_UNACKED]` without; (b) the exact bytes PR #8393 commits, placed unmodified in a scratch checkout of `d64430c26`, → `HOLD [SENTRY_UNAVAILABLE_UNACKED]`, and `RELEASED` once the ack line is appended (asserted against those bytes, not against whatever `main` carries at the time, so no concurrently-merging PR can flip it); (c) a hand-written file naming dry run 33886787297 with `main`'s live hash → `HOLD [RUN_NO_EVIDENCE_ARTIFACT]`.
- [ ] QG3 `python3 scripts/lint-guard-contract.py <this plan>` passes; `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 render/freshness tests pass after the `model.c4` edit.
- [ ] QG4 ADR-149 carries `### Disposition — #8010 (2026-09-19)`; the rehearsal runbook carries the token→remedy table, `--ref main`, the payload-change sequence and `RUN_NOT_COMPLETED` in its misleading-things list; `git-data-birth.md` no longer says the gate ignores the Sentry key and names the replace-route fallback.
- [ ] QG5 The blocker issue exists (milestone `Phase 4: Validate + Scale`, linked from roadmap L27 and #8361, marked blocking the L27 dispatch) covering `actions: read` + `GH_TOKEN` at the four call sites, the tri-state call-site conversion with its parity-test regex, the freshness-step reorder, **making `deploy-script-tests` a required check** (which is what turns Guard 4 ARM 2 from advisory into the control that catches the downgrade shape), and the `RUNG2_PRODUCER_SHA256` producer-binding; every `RUN_RATE_LIMITED` message cites it.
- [ ] QG6 `gh issue view 8010 --json milestone` reads `Phase 4: Validate + Scale`.

## Test Scenarios

### Acceptance Tests (RED phase targets)

S1–S12, R1–R13, A1–A5, H1–H6, T1, E1–E2, C1–C6 and the workflow ACK-line arm as enumerated in Phase 1, plus the Guard Contract mutation and harness rows driven through `mutate_r2` / `mutate_g` and the capture suite's sed-mutation idiom.

### Regression Tests

- Every existing R2, A, B and G arm stays green **only after** the stub store seeds run id `1` and `17250000001` (and `_G_URL` / `_G_URL2`) with `head_sha` = the matching fixture's pre-evidence commit, and the `CLEAN` default lands. This is prescribed work in Phase 1, not an assumption.
- The capture suite's producer/consumer arm keeps passing under the seam.
- `git-data-rung2-rehearsal.test.sh`'s summary-heading needles (`Rung-2 rehearsal: PASS`, `Rung-2 rehearsal: FAIL`, `WRAPPER FAILURE`) stay green; ARM 22 / ARM 26 in the capture suite stay green.

### Edge Cases

- `/job/<id>` or `/attempts/<n>` suffixes on the evidence URL; `…/runs/123abc` (must not parse as `123`); ids beyond double precision (string comparison).
- `conclusion: null` with `status: completed` → `RUN_NOT_SUCCESS`.
- HTTP 200 with `{"message":"Not Found"}` (no `.id`) → `RUN_UNRESOLVABLE`.
- An ack reason containing `:` (only the first colon separates) and one containing `#` (refused by name).
- The fixture whose cloud-init directory is the repo root (`<sha>:` form).

### Integration Verification (for `/soleur:qa`)

- **Local:** source the library in a scratch worktree at `15fd63aff…` and run the gate against that run's recorded evidence plus an ack → `RELEASED … run 34768256297 … concluded success`.
- **API verify:** `curl -s https://api.github.com/repos/jikig-ai/soleur/actions/runs/34768256297 | jq -r '.conclusion,.path,.event,.head_branch,.head_sha'` → `success`, `.github/workflows/git-data-rung2-rehearsal.yml`, `workflow_dispatch`, `main`, `15fd63aff88302f047fc7a96875aab466e8bc4cb`; and `curl -s .../artifacts | jq -r '.artifacts[].name'` → `git-data-rung2-boot-evidence`.
- **Cleanup:** remove the scratch worktree and the extraction temp dir.

## Domain Review

**Domains relevant:** Engineering, Product

Marketing, Operations, Legal, Sales, Finance and Support assessed and not relevant: no content, vendor, expense, contract, pipeline, budget or support-workflow surface changes. The GDPR gate (Phase 2.7) does not fire — no schema, migration, auth flow, API route or `.sql` file is touched, no new processing activity, no new distribution surface; the gate reads public CI metadata only.

### Engineering

**Status:** reviewed
**Assessment** (`soleur:engineering:cto` structural + devex passes; `soleur:engineering:review:architecture-strategist`; `soleur:engineering:review:dhh-rails-reviewer`; `soleur:engineering:review:kieran-rails-reviewer`; `soleur:engineering:review:code-simplicity-reviewer`; `soleur:product:spec-flow-analyzer`; ADR-083 advisor consult):

- **Dry-run forgery (CTO High, spec-flow P0, independently converged).** Verified on run 33886787297. Closed by the artifacts listing, not the jobs API — jobs' `steps` are not durable (run 23814647816, 172 days: `steps: []`) while artifact records persist with `expired: true` (run 27579149955, ~110 days).
- **The credential premise was false (architecture F1/F2, DHH P0, Kieran 9, simplicity cut 9).** No gate call site grants `actions: read`, so an authenticated attempt 403s and the anonymous path is operative everywhere. The persisted-checkout-header idea was cut outright (wrong destination for the credential, wrong type for a bearer chain, unmeasured). `secrets=GH_TOKEN` on #8210 was cut for the same reason.
- **Prescribed shell that did not work (Kieran P0 ×3, spec-flow P0).** The unquoted `${tok:+-H "…"}` never sends the header (array now); the curl had no `-D -` while the design read headers (header parsing removed entirely — rate limiting is read from status + body); `git archive <sha> -- <dir>` emits repo-root-relative paths and is fatal on the root-dir fixtures (tree-ish `<sha>:<dir>` now, measured both ways).
- **Cuts taken (simplicity, DHH).** The `merge-base --is-ancestor` check and the gate-side `git fetch` (no property they satisfy that `head_branch` + reachability do not, and every fixture lacks `origin/main` — Kieran 4); the reboot-arm corroboration path (the run-bound ack already satisfies the property, and the coordinator's constraint names the ack as an accepted alternative); `SENTRY_ACK_CONTRADICTS`; the `retry-after` honouring; the one-caller liveness helper; Guard 4's mutation matrix trimmed. Roughly 190–225 lines of prescribed code and test removed while every property P1–P6 stays satisfied.
- **Vocabulary splits (spec-flow P1 ×3).** `SENTRY_VERDICT_FATAL` vs `SENTRY_VERDICT_UNREADABLE`; `RUN_NO_EVIDENCE_ARTIFACT` vs `RUN_ARTIFACT_RECORD_UNREADABLE`; `NOT_RUN` written by the capture's never-consulted branches so "never ran" stops committing the same bytes as "ran and degraded".
- **Unnamed consumers (architecture F5/F8, spec-flow P0).** The capture suite's producer/consumer arm calls the real gate; `plugins/soleur/test/terraform-target-parity.test.ts` pins the call-site `if !` shape; `fixture-relative-assert.baseline.txt` references the gate path; Guard 1's seam mutation row would have hit the live network. All four are now in scope.
- **Devex (CTO devex pass).** The `STALE EVIDENCE` message is the one a payload author actually reads and now points at the runbook; the two-PR payload sequence is documented; a token→remedy table lands in the runbook; the operator is told to wait for the whole run; the ack decision is one line after the reset probe instead of instructions plus caveats. Remaining debt named: the gate suite is large relative to the function it guards.

### Product/UX Gate

**Tier:** none — no UI surface. `## Files to Edit` and `## Files to Create` were scanned against the UI-surface term list and glob superset: no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`, no user-facing route or copy. The mechanical override does not fire; no wireframe is required.
**Decision:** reviewed (CPO invoked for the `single-user incident` sign-off, not for a UX gate)
**Agents invoked:** `soleur:product:cpo`, `soleur:product:spec-flow-analyzer`
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**`soleur:product:cpo` — SIGN-OFF: yes-with-conditions.** All four applied: (1) re-milestone #8010 to `Phase 4: Validate + Scale` so the P1 birth route (roadmap L27) is not gated by a Post-MVP item; (2) the credential work is filed as a **blocker of the L27 birth/replace dispatch**, linked from L27 and #8361; (3) `## User-Brand Impact` carries the post-cutover RTO line and the runbook names the fallback order; (4) ADR-149's disposition records an ack-frequency tripwire — two consecutive `main` rehearsals reading `UNAVAILABLE` after this merge reopen the liveness question rather than accumulating acks. CPO also noted, and this plan agrees, that nothing here may be marketed as "rehearsed before birth" while the Sentry verdict remains a human-committed string; the residual is recorded in ADR-149 and the encryption posture stays `not-publicly-claimed`.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-149** with `### Disposition — #8010 (2026-09-19): the rung-2 gate resolves the run it names`. Its 2026-09-11 disposition records the finding as open ("the gate's only provenance check is a regex that RUNG2_EVIDENCE_URL *looks like* an Actions run URL; it never fetches the run (#8010)"). The disposition records: the five new steps and their order; that identity is asserted by workflow `path`, `event`, `head_branch` and the **capture artifact**, because a dry run also concludes success; that `conclusion == success` is required and why the earlier caveat no longer applies; the run-bound ack as the only way `UNAVAILABLE` releases, plus the ack-frequency tripwire; that every CI call site is **anonymous** until the blocker issue grants `actions: read`, and that the gate's own `::error::` line exists because two of three callers cannot be edited this cycle; the accepted consequence that a failed teardown after a PASS capture yields no usable evidence; the residuals — the Sentry verdict is still a human-committed string; artifact-record retention past ~110 days is measured once and undocumented, which is why its absence past 90 days is a could-not-measure token; **the producer is unbound** (the roster binds neither the rehearsal workflow nor the capture script, so the gate proves "a workflow at that path ran on `main` and produced a boot-evidence artifact", and a `RUNG2_PRODUCER_SHA256` recomputed at the run's `head_sha` is the recorded next step); and **the downgrade shape** (revert the infra tree, cite an older genuine run) passes every check honestly, caught only by Guard 4 ARM 2, which is advisory until `deploy-script-tests` becomes required; and, in Future Considerations, the attestation-based alternative (`actions/attest-build-provenance` + a committed Sigstore bundle) beside the deferred check-run idea. No new ADR: this extends ADR-149's interlock decision rather than reversing it.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). External actors and systems touched: the operator (modeled), **GitHub** (`github = system "GitHub"`, modeled, with `webapp -> github` over the REST API and `engine -> github`), Sentry (modeled; the `github -> sentry` edge exists). No new element and no new edge — the gate runs inside GitHub Actions and reads GitHub's own API, and the local run reuses the existing operator→GitHub relationship. **One description edit** on the `gitDataStore` element: after "hash-bound to the CURRENT template (…)", add "and, since #8010, names a completed, successful `workflow_dispatch` run of the rehearsal workflow on `main` that uploaded a boot-evidence artifact and whose `head_sha` re-hashes to that evidence (resolved live through the GitHub REST API), with the Sentry cross-check verdict required in the file". `plugins/soleur/test/c4-count-parity.test.sh` was run at plan time and passes (`Failed: 0`); the edit moves no cardinality. The pre-commit hook regenerates `model.likec4.json`.

### Sequencing

The disposition is true the moment this PR merges; no soak. Authored in Phase 3.

## Open Code-Review Overlap

- #7098 (`ci: audit the 56 run: bodies whose set omits -e …`) names `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`. **Acknowledge:** a repo-wide lint-shaping audit; this plan adds one assertion arm and changes no `run:` body's `set` line.
- No other open `code-review` issue names a file in this plan's edit list (queried `gh issue list --label code-review --state open`, 65 issues).

## Success Metrics

- The hand-written four-line file from #8010 HOLDs: with an unknown run id at `RUN_NOT_FOUND`, with a real successful run at `RUN_HASH_MISMATCH`, and with the newest **dry run** at `RUN_NO_EVIDENCE_ARTIFACT`.
- The C21/C8 laundering shapes from the #8052 review HOLD at `RUN_HASH_MISMATCH` (H2), and the Guard 4 residual is closed **for runs that actually captured** — the dry-run arm is what makes that claim true rather than rhetorical.
- The capture records a 24 h liveness anchor in ARTIFACT 4 (`--stats-period 24h`), asserted by C3/C4 — a post-condition of this PR rather than a prediction about ambient Sentry ingest (the ambient question belongs to the ADR-149 tripwire).

## Dependencies & Prerequisites

- PR #8393 (evidence from run 35465756680) is the file this gate will judge; the ack sequencing above covers both merge orders.
- #8361 (apply workflow over the 500 KB limit) keeps the two apply call sites inert; it blocks the credential follow-up on that file, not this plan.
- `curl`, `jq`, `git`, `tar` on every gate surface (ubuntu-latest runners, the `env -i` sweeper's pinned `PATH`, and the operator workstation).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Anonymous rate limiting (60/h per IP, shared NAT on hosted runners) spuriously HOLDs a route | `RUN_RATE_LIMITED` names the `actions: read` + token remedy and the blocker issue; the gate emits its own `::error::` so the callers' fixed text is not the only signal; the two apply sites are inert until #8361; the #8210 probe maps it to TRANSIENT. Fail-closed is the correct direction for this gate. |
| The freshness step's `exit 1` blanks the eight guard steps after it, now for a transient cause | Named in the failure modes; the step reorder is in the blocker issue; `deploy-script-tests` is not a required check, so it is a visible red rather than a merge gate. |
| The artifact **record** is purged past the measured ~110-day horizon | Absence past 90 days is the could-not-measure token, not a refusal; the remedy in both cases is a fresh `main` rehearsal, which the hash binding already demands whenever a bound file moves. Recorded in ADR-149. |
| A run that concludes `failure` after a PASS capture yields unusable evidence | Documented in the disposition, the runbook and the `RUN_NOT_SUCCESS` text; the workflow tells the operator to wait for the whole run; teardown-only recovery exists. |
| A rehearsal dispatched from a branch is refused | The runbook's dispatch line carries `--ref main`; `RUN_NOT_MAIN` names it; all eight historical rehearsal runs were `main` + `workflow_dispatch`, so this refuses nothing that happens today. |
| `git archive` bytes diverge from worktree bytes via a future `.gitattributes` entry | Attributes disabled during the archive; `git check-attr -a` on the roster returns nothing today. |
| The producer (rehearsal workflow, capture script) is outside the hash-bound roster, so a merge to `main` can make a no-op workflow satisfy every run check | Stated at its real strength in Guard 1's Anchor and in ADR-149 rather than claimed away; bounded by the same missing required-review ruleset the gate's own URL HOLD names; `RUNG2_PRODUCER_SHA256` filed in the blocker issue. Binding the two files into the existing roster is not the fix — the roster is "what renders into user_data", and this PR edits the workflow, so it would void its own evidence. |
| An evidence value forges a workflow command through the gate's own `::error::` line or the #8210 issue comment | One sanitizer on every interpolated evidence value (NFR1), plus the suite arm that feeds a `%0A::stop-commands::` value through a HOLD path. |
| The gate suite grows past ~2,300 lines | The S/R rows are data-driven tables rather than hand-written blocks; the residual maintenance cost is named as debt in the Domain Review rather than hidden. |

## Resource Requirements

One engineer-session; no infrastructure; no secrets. The live verification uses public run metadata and scratch checkouts.

## Future Considerations

- Per-step conclusions via the jobs API if GitHub ever makes step data durable.
- `run-name:`-encoded dispatch mode once every live evidence file postdates it (a second, endpoint-free dry-run discriminator).
- Binding the Sentry verdict to something outside the file (a check-run output written by the rehearsal workflow), and the attestation-based alternative — both recorded in ADR-149.

## Documentation Plan

- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` — `--ref main`; the token→remedy table; `After a PASS` (wait for `success`, ack before `git add`, the `jq`/`curl` dependency); `RUN_NOT_COMPLETED` in the misleading-things list; the two-PR payload-change sequence.
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — the `RUNG2_SENTRY_CROSSCHECK` sentence; the replace-route fallback order.
- ADR-149 disposition; the `model.c4` sentence.
- In-file: the gate's `STALE EVIDENCE` pointer, the Guard 4 residual paragraph, the capture's ARTIFACT 4 prose.

## Files to Edit

- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — four new helper functions, the two cardinality loops and the verdict `case`, steps A–E, the `::error::` emitter, the RELEASED line, the `STALE EVIDENCE` pointer, the Guard 4 header residual.
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — the exported seam, the `$TMP/api` stub store and `_stub_run`, `_r2_evidence_write` args 6–7, the existing-arm run-id/head_sha seeding, the S/R/A/H/T/E tables, the mutation and harness rows, the itemised floor raise.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — the suffix refusal, the 24 h liveness at the call site, `NOT_RUN` on the never-consulted branches, the ARTIFACT 4 lines and scope sentence, the reset arm's resolved `--end`.
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — the producer/consumer arm's seam, C1–C6, the itemised floor raise.
- `.github/workflows/git-data-rung2-rehearsal.yml` — the post-reset ACK decision line, the reordered "land it yourself" block, the wait-for-`success` sentence.
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — one ACK-line arm.
- `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh` — the `exit 3` could-not-measure split (FR16), the full-token print, and the TRANSIENT message wording.
- `scripts/lint-trap-tempfile-ownership.highwater` — +1 with a written reason (the gate library becomes a new `mktemp`-without-trap entrant; the census does not honour the escape annotation).
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md`, `knowledge-base/engineering/operations/runbooks/git-data-birth.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and the hook-regenerated `model.likec4.json`).
- Run but do not edit unless they move: `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`.

## Files to Create

None.

## Research Insights

### Premise Validation (Phase 0.6)

- #8010 is `OPEN`, `closedBy: []`; labels `priority/p2-medium`, `type/chore`, `domain/engineering`, `type/security`. Body items 1–3 and follow-up item 5 are untouched (#8171's merge comment enumerates what it took).
- Run 34768256297: `success`, `completed`, `main`, `workflow_dispatch`, `head_sha 15fd63aff…`, `path .github/workflows/git-data-rung2-rehearsal.yml`, `workflow_id 323842193`, artifacts `[git-data-rung2-boot-evidence, expired:false]`. Run 33888071954 (the issue's caveat): `failure` — superseded. Run 35465756680: `completed`/`success`, `main`, `head_sha d64430c26`, artifact present. Dry run 33886787297: `success` with `Dry run complete — stopping here: success`, capture/upload `skipped`, `0` artifacts.
- The evidence file does not exist on `origin/main` (deleted by #8312 `f64b0ebc2`); the last committed content is at `273f29a80` and carries `RUNG2_SENTRY_CROSSCHECK=UNAVAILABLE`. PR #8393 (OPEN) commits run 35465756680's file, whose bytes were fetched and read at plan time.
- Hash mechanism measured: `git archive 15fd63aff…:apps/web-platform/infra` + `git_data_rung2_user_data_sha256` → `5c50797be839…` (equals the committed claim); `main` today → `a0b5f37b2fef…`. The pathspec form and the empty-pathspec root case were both measured and rejected.
- Repo visibility `PUBLIC`; unauthenticated `curl` to the runs endpoint → 200; run 30558537136 (2026-07-30) still resolves; the 404 body is `{"message":"Not Found",…}`; `x-ratelimit-remaining` / `x-ratelimit-reset` are present on responses but are **not** used (status + body suffice).
- No gate call site grants `actions: read` — verified in all four permissions blocks (`git_data_host_create`, `git_data_host_replace`, `infra-validation.yml`'s workflow-level block, the sweeper's). The apply file's own comment documents `actions: read` as the minimum for the sibling `…/actions/runs/<id>/jobs` endpoint; the requirement for `…/runs/<id>` itself comes from GitHub's REST reference. `apply-web-platform-infra.yml` is 513,306 bytes and its recent runs are startup failures (#8361).
- Both gate suites are registered in `scripts/test-all.sh`; `deploy-script-tests` carries 133 registered suites; neither suite is an orphan.
- ADR corpus: ADR-149 records the run-URL finding as open and deferred to #8010; ADR-152 (render-time comment stripping) is unaffected; ADR-129 rule (c) forbids a library `EXIT` trap. No ADR rejected run resolution or key promotion.
- No brainstorm document matches this feature; idea refinement was skipped (pipeline mode, detailed brief).

### Property List and Cut List (Phase 0.6b)

**Properties.** P1 release only on a resolvable, completed, successful `main` `workflow_dispatch` run of the rehearsal workflow **that actually captured**; P2 the run booted the attested bytes (hash at `head_sha` == claim); P3 the Sentry verdict is part of the release decision, with `UNAVAILABLE` requiring a run-bound ack and `FATAL`/`NOT_RUN` refused; P4 the capture cannot write a decoupled host/run pair; P5 a quiet project is not a dead instrument (24 h liveness anchor); P6 the human landing the evidence is told exactly what the gate will require.

**Cuts.** Fix 1 as a gate-side string comparison → P1/P2/P4 cover it; `workflow_id` → `path`; jobs-API step conclusions → not durable; artifact byte-compare → contents expire; `gh` → `curl`; a hard `UNAVAILABLE` HOLD with no ack → the issue's own design; ancestor-of-`origin/main` → no property beyond `head_branch` + reachability, and no fixture has the ref; reboot-arm corroboration → the ack satisfies P3 already; `SENTRY_ACK_CONTRADICTS` → satisfies nothing; the extraheader scrape and `gh auth token` → P1 is satisfiable anonymously on a public repo; `retry-after` honouring → an hourly window is not waited out; a one-caller liveness helper → inline.

### Relevant institutional learnings

- `knowledge-base/project/learnings/2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md` — cardinality checks that count keys not values; extract then validate.
- `knowledge-base/project/learnings/2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md` — never infer success from absent parsed evidence; test null/empty/wrong-type shapes.
- `knowledge-base/project/learnings/test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md` — the seam sits below the parser.
- `knowledge-base/project/learnings/2026-08-04-the-pr-that-fixed-unmeasured-claims-shipped-three-of-them.md` — closed reason vocabulary; measured vs could-not-measure are structurally distinct tokens.
- `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md` — curl stderr leaks `Authorization`; capture `%{http_code}`; jq fallbacks.
- `knowledge-base/project/learnings/2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md` — anonymous vs authenticated budgets.
- `knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md` — the anchor must live outside the commit.
- `knowledge-base/project/learnings/2026-09-11-the-gate-i-skipped-for-contention-hid-my-own-red-suite-and-two-rehearsals-attested-a-gc-that-never-ran.md` — run every suite that consumes the touched function.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — harness rows and own-dispatch rows in every matrix.
- `knowledge-base/project/learnings/2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md` — validate each mechanism against the tree its own remediation produces.

### Codebase anchors

- Gate: `git_data_rung2_rehearsal_gate()` (usage comment `# 0=RELEASED, 1=HOLD`), the cardinality loop `for _k in RUNG2_BOOT_REHEARSAL RUNG2_EVIDENCE_URL RUNG2_TEMPLATE_SHA256 RUNG2_VAR_DIVERGENCE`, the comment strip `s/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//`, the Guard 4 header paragraph beginning `RESIDUAL, STATED SO NOBODY READS THIS AS A PROOF`, `_git_data_repo_rel`, `git_data_rung2_user_data_sha256`, `git_data_rung2_bound_files`, and the ADR-129 note at the `trap ... EXIT` comment.
- Capture: `_sentry_window_args`, `_sentry_consult` (the `--liveness` call, the `UNAVAILABLE` and SKIPPED branches), the writer block beginning `printf '# ARTIFACT 4 — the Sentry cross-check`, the reset arm's `--stage luks_reopen_ok … --end <now>` line, the refusals `refusing: --host-name must match` and `refusing: --evidence-url must be an Actions run URL`.
- Workflow: capture step `id: capture`, the summary block from `Evidence captured for` through the `git_data_rung2_rehearsal_gate …` line; the reset probe `id: reboot_probe`; the upload gated on `capture_rc == '0' && reboot_rc == '0'`.
- Suites: `_r2_evidence_write`, `r2check`, `mutate_r2`, `_g_repo`, `_g`, `mutate_g`, `_FLOOR=150` with its `RAISED …, ITEMISED:` blocks and the ledger reconciliation; the capture suite's `SOLEUR_SENTRY_READER` / `SENTRY_ARGV_FILE` stub, ARMs 22/26/29, the `HOST` / `URL` constants, the producer/consumer arm at `gate_out="$(git_data_rung2_rehearsal_gate`, and `_FLOOR=107`.
- Consumers: `apply-web-platform-infra.yml` `git_data_host_create` / `git_data_host_replace` (not edited), `infra-validation.yml` "Rung-2 evidence freshness", `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh`, `scripts/test-all.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, both runbooks.

### CLAUDE.md / constitution conventions applied

`#!/usr/bin/env bash` + `set -euo pipefail`; `local` in functions; operator-protection signals on stdout; the minimalism ladder (curl over gh, one shared hash function, no new evidence keys the current capture does not write, no helper with one caller); `cq-assert-anchor-not-bare-token` and `cq-cite-content-anchor-not-line-number` in the suites and this plan; `hr-verify-repo-capability-claim-before-assert` (the anonymous API read, run-metadata persistence, artifact-record persistence, the dry-run shape, both archive forms, the permissions blocks and the hash reproduction were all measured, not assumed); `hr-technical-fork-is-not-an-operator-question` (the replace-route fail-open fork decided here, with reasoning recorded).

### Community / functional overlap

`soleur:engineering:discovery:functional-discovery` found no community skill or agent that resolves a run id, re-hashes at `head_sha` and requires a closed-set verdict; the closest (`ci-fix`, `ariadne` in-toto attestations) replace no part of this repo-specific gate. No uncovered stack.

## References & Research

### Internal References

- ADR-149 `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` — `### Disposition — #8043 (2026-09-11)` and the run-URL finding.
- ADR-152 (render-time comment stripping) — the comments-are-not-load-bearing lineage. ADR-129 — no library `EXIT` trap.
- Plans: `knowledge-base/project/plans/archive/20260911-230120-2026-09-10-fix-git-data-hash-bound-hardening-batch-plan.md` (Guard 4); `knowledge-base/project/plans/archive/20260919-001310-2026-09-18-fix-git-data-luks-mapper-reopen-at-boot-plan.md` (the deletion that voided the evidence; the threshold precedent).

### External References

- GitHub REST `GET /repos/{owner}/{repo}/actions/runs/{run_id}` and `…/artifacts` — fields `id`, `path`, `status`, `conclusion`, `head_sha`, `head_branch`, `event`, `run_attempt`, `created_at`, `artifacts[].name`, `artifacts[].expired` (all verified live at plan time).
- GitHub rate limits: 60 requests/hour unauthenticated per IP; 1,000/hour for `GITHUB_TOKEN` in Actions — and `actions: read` is required for the runs API regardless.

### Related Work

- PRs #8002, #8052, #8126, #8171, #8312; PR #8393 (open, the evidence this gate will judge).
- Issues #8010 (this), #8361, #8178, #8210, #7098 (overlap, acknowledged).
