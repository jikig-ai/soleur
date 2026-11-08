---
title: "Persist web-2's LB weight after the serve flip (web2_lb_weight default 1) and mint the relay hello-signing secret"
date: 2026-11-08
slug: web2-lb-weight-default-and-proxy-hello-key-mint
branch: feat-one-shot-12363-web2-weight-persist-hello-key
issue: 12363
closes: 12363
type: chore
lane: cross-domain
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
---

# Persist web-2's LB weight (default 0 to 1) and Terraform-mint PROXY_HELLO_HMAC_KEY

## Enhancement Summary

**Deepened on:** 2026-11-08. **Agents used:** CTO (5 rulings), three plan-review seats (DHH, Kieran, code-simplicity), an independent C4 read, terraform-architect, security-sentinel, learnings researcher. **Gates run:** Phase 4.6-4.13 mechanical checks (user-brand, observability, PAT, UI, encryption posture, guard contract, scope check all present and valid; the discoverability probe was replaced by a 1-second grep after the suite-shaped probe tripped the Check 10 cap heuristic), cited issue numbers and rule ids re-verified live.

### Key improvements
1. Serve no-op grading moved from editing 17 jq selectors to a hardened thin wrapper (three-way dispatch whose default arm refuses, exact normalization predicate, `{resource_changes}`-only temp copy, explicit rc handling).
2. Fixture names corrected (`pn*`; `pu1`-`pu36` exist), defect fixtures made genuinely RED today, floors re-derived (124 / 285 / 376).
3. The "exactly two additions" PR-plan check was wrong for a full-root plan; it is now relative (+2 against base, no pool block). Added a pre-merge precondition on the first post-flip drift run and a `WEB2_LB_WEIGHT` absence check.
4. Stale-wording sweep widened (tf, variables, workflow, dispatch-input description) with one named exception (the live `description =` attribute at `cloudflare-lb.tf` L160).
5. ADR-068 handled as a dated addendum (the file has no `web2_lb_weight` text); the default flip's two ungated paths (untargeted rebuild, non-durable drain) are now explicit MUSTs in the runbook, bootstrap-recovery runbook and ADR addendum.

### New considerations
- Flipping `host_proxy_tls_enabled` off and on silently mints a different hello key; documented in the `.tf` header.
- Sentry scrub-list entry for the new key is a PR A precondition (A-0 cannot touch app code).
- The release push arm fires on this infra-only PR (CTO ruling 7).

## Overview

Infra-only change "A-0" under epic #8211 / #12167. Two independent edits ride one PR as two commits (CTO rulings 1 and 8 in `knowledge-base/project/specs/feat-one-shot-12363-web2-weight-persist-hello-key/decision-challenges.md`):

1. **Commit 1, the flip (#12363).** Live web-2 is already at pool weight 1 (the serve flip applied), but `variable "web2_lb_weight"` still defaults to 0. The tree therefore disagrees with live: the scheduled full-root drift plan reports web-2 `1 -> 0` on every run, and any full-root plan or `ga-overlay` run would propose a silent drain. The default moves to 1, and every grader pin, census, comment, runbook paragraph and model description that encoded "default 0 / drained" moves with it. Drain stays an explicit act: `ga-pool-update mode=drain` already passes `-var=web2_lb_weight=0` (the plan step passes the pin step's value in both modes), and `ga_overlay` gains the same explicit `0` so its fresh-create shape stays drained.
2. **Commit 2, the mint.** `PROXY_HELLO_HMAC_KEY` (64 lowercase hex chars = 32 random bytes) is minted by Terraform into Doppler `soleur/prd`, count-gated on `var.host_proxy_tls_enabled` exactly like `proxy_tls_key`, so the secret exists before the next PR ("A", fail-closed signed relay hello, #12288/#12289/#12290) reads it. The generator is `random_bytes`, not `random_password` (CTO ruling 6: `random_password` cannot emit hex; `random_bytes.hex` is sensitive and has no `id`).

No application code is touched. The brief's expectation that this keeps the release push arm out is wrong for any file under `apps/web-platform/infra/` (CTO ruling 7, evidence below): the release fires, publishes unchanged app bits, and deploys to both hosts. The plan records that as expected rather than changing the release filters.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (verified in this worktree) | Plan response |
|---|---|---|
| This PR triggers the infra apply only; the release push arm stays out because there is no app code | `web-platform-release.yml` `on.push.paths` has `apps/web-platform/**` with no infra exclusion; `path_filter` (L128) and `RELEASE_PATH_FILTER` (L375) both start `apps/web-platform/ plugins/soleur/`. Three infra-only commits (960ec26913, 9682d9440d, e2964b801d: files only under `apps/web-platform/infra/`, `.github/`, `tests/`, `scripts/`, `knowledge-base/` and `plugins/soleur/test/`, which the release filter excludes) each show a successful `push` and `workflow_run` release run (`gh run list --workflow web-platform-release.yml --commit <sha>`); Phase 3.6 re-runs `git show --name-only` per commit before the PR body cites them (two other candidates, df921cff26 and 3d75cc24a3, also touched `apps/web-platform/test/` or `plugins/soleur/scripts/` and prove nothing) | Premise corrected. Accept the no-op release (same app bits, rolling deploy to both hosts), say so in the PR body, do not edit the filters here (CTO ruling 7). Follow-up issue: audit excluding `apps/web-platform/infra/` from the release filters |
| Terraform-mint with `random_password` | `random_password` exposes only `result` and `bcrypt_hash`; no hex. hashicorp/random is locked at 3.9.0, where `random_bytes.hex` is Sensitive and the type has no `id` | `random_bytes` length 32 fed through `.hex` (CTO ruling 6). The deviation from the brief's word is technical and meets its stated requirement |
| Drain must pass an EXPLICIT `-var=web2_lb_weight=0` | Already true: `cf-lb-overlay.yml` ga_pool_update plan step passes `-var="web2_lb_weight=${WEB2_LB_WEIGHT}"` in both modes (L1149), the pin step sets 1 only for serve | No workflow change for `ga_pool_update` beyond comment rewrites; the C.4-F4/F5 pins stay |
| Serve must accept a no-op "no changes" plan | `cf_lb_gate_ga_pool_update` drops no-ops (`_CF_LB_CHANGES`), so a serve no-op plan hits the `updates == 0` "empty change set" refusal; and when other entries exist the pool-less "remnant-only" branch SKIPS the origins pins, so today a serve plan whose pool is a no-op at web-2 weight 0 passes with only a notice | Serve-only grading of a pool entry that is `update` or `no-op`, same pins; remnant-only becomes drain-only (CTO ruling 4). The existing vacuous serve pass becomes a refusal |
| Nothing in apply-web-platform-infra.yml's `-target` set plans the pool | `grep -c cloudflare_load_balancer .github/workflows/apply-web-platform-infra.yml` is 0, and no `.tf` outside `cloudflare-lb.tf` references `cloudflare_load_balancer_pool.web_1` / `.app` / `_monitor.web` (so no targeted resource pulls the pool in transitively) | Confirmed. Evidence recorded in Research Insights; pinned by the existing C.4-F7 plus the transitive-reference check in Phase 3.7 |
| Grep every workflow for a full-root terraform run | Full-root (untargeted) plans on the web-platform root: `scheduled-terraform-drift.yml` (no `-var`, `doppler run --name-transformer tf-var`, detect-only) and the `infra-validation.yml` `plan` job (PR-only, `-refresh=false`, detect-only). `apply-web-platform-infra.yml` plans hard `-target` lists. `cf-lb-overlay.yml` arms: `ga_overlay` (pool targeted, NO `-var`), `ga_pool_update` (`-var` both modes), `ga_monitor_fix`/`ga_monitor_https` (monitor only), three staging arms (own root). Every other `terraform plan` workflow targets a different root | Only `ga_overlay` needs a change: explicit `-var="web2_lb_weight=0"` (CTO ruling 5). Drift and PR-plan workflows must stay `-var`-free (C.4-F7) |
| A NEW suite needs shard-manifest rows | No new test file is created: the new assertions extend `tests/scripts/test-cf-lb-overlay-gate.sh`, `apps/web-platform/infra/lb-weight-gate.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `tests/scripts/test-tf-redact-random-ids.sh` | `regenerate-shard-manifest.py --incremental --write` is run and must produce NO diff (proof of the no-new-suite claim); baseline decision in Phase 3.4 |
| Floors EXACT and derived | Measured on this branch before any edit: `test-cf-lb-overlay-gate.sh` prints 110 assertions against a floor of 98 (12 loose); `lb-weight-gate.test.sh` 282 against `MIN_CASES=282` (exact); `grep -cE '^\s*test\(' terraform-target-parity.test.ts` is 372 against `TEST_FLOOR = 367` (5 loose) | Each floor is set to its measured post-change value (derivation table under Acceptance Criteria). The two loose floors are tightened in the commit that touches them |
| model.c4 and the runbook describe web-2 as drained | model.c4 L448 (`cloudflare`: "web-2@0 drained until the #6027 window flip"), L351 (`hetzner`), L355 (`workspacesVolume`), L926 (`betterstack -> hetzner`) state serving weight 0; the runbook paragraph "After a successful serve" and the arm descriptions state default 0 / one-way; further stale text sits in `cloudflare-lb.tf` L48/L70/L87/L160, `variables.tf` L181 and `cf-lb-overlay.yml` L25/L55/L706/L879 | Runbook, ADR addendum, the .tf/.yml comments and the L448 C4 phrase are rewritten in commit 1; model.c4 L351/L355/L926 and the live `description =` attribute at `cloudflare-lb.tf` L160 go to a follow-up (plan-review taste call) |
| (not in the brief) In-transit exceptions expire 2026-11-12 | `lint-encryption-posture.py` warns that two `in_transit` exceptions (tracking #10538, #10479) expire 2026-11-12 and "every PR goes red on that date" | Unrelated to this change; sequencing risk recorded: merge before 2026-11-12 or expect that red gate from a sibling concern |

## Research Insights

**Premise Validation (Phase 0.6).** #12363 is OPEN and unfixed on `origin/main` (variables.tf still `default = 0`). #8211, #12167, #12288, #12289, #12290 are OPEN. The collision pre-check names exactly one open PR for #12363: #12414, this branch's own draft. Foreign `test-all.sh` processes belong to other worktrees (not collisions). The proposed mechanism was checked against the ADR corpus: ADR-068's 2026-11-01 addendum (item 2, "web-2 pooling shape") records web-2 as a pool origin at weight 0 until the #6027 window flips it behind the §(c) gate chain; the "one-way until the default changes" wording and the "only feeder is the serve arm" invariant live in the runbook, the `variables.tf` comment and `lb-weight-gate.test.sh` C.4, not in the ADR (ADR-068 never names `web2_lb_weight`). ADR-118 (2026-09-27 amendment) owns the proxy-TLS count-gate pattern and the `-target` list discipline. Neither rejects this change. The ADR's "until the window flips 0→1" statement is now history, so a dated addendum at the end of ADR-068 is a deliverable here (see Architecture Decision).

**Property List (Phase 0.6b).**
- P1. The Terraform default for web-2's origin weight equals live (1), so the scheduled full-root drift plan is clean with no `-var` and no full-root plan proposes web-2 `1 -> 0` (the drift has existed only since the serve flip applied at about 14:40Z on 2026-11-08; before it the pool read {1,0} and plans were clean).
- P2. Draining web-2 remains possible only as an explicit, gated act (`ga-pool-update mode=drain` passing `-var=...=0`), and a GA fresh-create still lands web-2 drained.
- P3. A serve dispatch against live state {1,1} is admitted by its grader on the same pins as a 0-to-1 flip and never admitted without grading the pool.
- P4. No document, comment or model description still states that the tree default is 0.
- P5. `PROXY_HELLO_HMAC_KEY` exists in Doppler `prd` as exactly 64 lowercase hex chars from a CSPRNG, masked, never in plan or log output, minted by the per-merge saved plan, before any code reads it.

**Cut List (Phase 0.6b).** None of the mechanisms the brief names is cut except as follows: (a) `random_password` is replaced by `random_bytes` (it cannot satisfy P5's hex requirement); (b) widening the proxy-TLS quartet test is replaced by a separate pair test (the quartet test's all-four-together meaning is about the cert/key pairing); (c) a release-filter edit is deferred to a separate audited change (CTO ruling 7); (d) a before==after assertion on the no-op pool is dropped (identical by construction, CTO ruling 4); (e) a new test suite is avoided (all assertions extend existing suites).

**Value-proposition measurement (Phase 0.6c).** No cost or performance saving is claimed. The size-budget claim is measured: `wc -c .github/workflows/apply-web-platform-infra.yml` is 488,411 bytes against the 490,000-byte gate in `plugins/soleur/test/workflow-file-size.test.ts` (GitHub's hard limit is 512,000); two `-target` lines add about 115 bytes, leaving about 1,470 bytes of headroom.

**Institutional learnings applied.**
- `knowledge-base/project/learnings/2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`: a constant flip breaks gates asserting the old value only after merge; the whole-repo grep for `web2_lb_weight|WEB2_LB_WEIGHT` and for the stale phrases is a Phase 1 task, and a stale-phrase census becomes a permanent pin.
- `knowledge-base/project/learnings/2026-10-30-gate-allow-sets-bound-which-resources-not-what-they-say.md` and `2026-11-01-dispatch-arm-grader-admit-first-apply-verb-and-pin-by-resolved-ip.md`: pins bind `.change.after` by resolved IP, weights compare as numbers, `has()` not `//` for booleans, and a fixture that encodes the defective behavior is itself a defect (the existing serve-with-no-pool admission is exactly that).
- `knowledge-base/project/learnings/2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md` and `2026-06-02-verify-terraform-target-set-not-header-prose.md`: a typo in a `random_*`/`doppler_secret` `-target` silently no-ops; the new pair is pinned by address in the parity test, and the `-target` literals, not prose, are the source of truth.
- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: measure the apply workflow's bytes before and after; rationale prose belongs in `apply-web-platform-infra-job-rationale.md`, not the YAML.
- `knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`: extending the `-target` list can break guard suites that hard-code allowed resource types; sweep `test-destroy-guard-counter-web-platform.sh`, the parity test and `workflow-file-size.test.ts`.
- `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md` "Follow-up PR (required after a successful serve)": names this PR's exact scope (variables.tf, C.3/C.4 and W-series pins, the pin-step comment, the runbook section).

**Overlap with open PRs (read only, never edited).** #12404, #12379, #10678, #7390 touch `apply-web-platform-infra.yml` at hunks near L408/L857, L604, L518 and L5944; this PR's insertion is directly after the `-target=doppler_secret.proxy_tls_cert \` line (about L681), disjoint from all four. #12379 also edits `terraform-target-parity.test.ts` and `model.c4` (model.c4 hunks at L594/L788/L860/L969; this plan edits L351/L355/L448/L926): disjoint hunks, but `TEST_FLOOR` and its comment block are a rebase hot spot, so whichever PR lands second re-derives the floor with the grep command. #11592 (draft) touches `variables.tf` at L77 only; this plan edits L555-570 and the `host_proxy_tls_enabled` description near L710.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was searched for each planned file path with `jq --arg`; no issue body names any of them.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent (do-not-ask mode) ruled all five forks; the rows are in `decision-challenges.md` (items 4-8) beside the three pre-ruled items. Key rulings: serve-only no-op grading with remnant-only restricted to drain; explicit `-var=0` on `ga_overlay`; `random_bytes` over `random_password`; the release push arm fires and is accepted; flip and mint are separate commits in one squash-merged PR with a revert rule. Product/UX: no user-facing surface (no new components, pages, or copy), so the Product gate is NONE. GDPR gate: skipped, no regulated-data surface (a service-to-service HMAC key; no personal data, schema, auth flow or API route) and none of triggers (a)-(d) apply.

## User-Brand Impact

**If this lands broken, the user experiences:** a silent drain of web-2 (a full-root plan or `ga-overlay` proposing `1 -> 0` and someone applying it) halves serving capacity and removes the second origin during a live multi-host window; or a serve re-dispatch that the grader wrongly refuses or admits. Because live is already 1, a correct merge changes nothing users can see; a wrong default (left at 0) is the failure, and it surfaces as a drift alert rather than as user-visible breakage.
**If this leaks, the user's workflow is exposed via:** a leaked `PROXY_HELLO_HMAC_KEY` (or its value in Terraform state or plan output) would let a party on the private network forge a relay hello and attach to another user's proxied session once the next PR enforces it. In A-0 nothing reads the key, and `random_bytes.hex` is Sensitive (no `id`, masked Doppler secret), so nothing prints.
**Also accepted (review 2026-11-08):** merging fires the release push arm, which restarts each live host's container in turn (`docker stop --time=12`; the swap drain waits only for in-flight cron children), so any live user stream on that host drops once; live users are 0 today, and the merge is owner-named, so it can be timed to a window with `agent_sessions_live=0` on both hosts. The apply workflow's `terraform show -json` dump (runner-local, not uploaded) will hold `PROXY_HELLO_HMAC_KEY` in clear exactly as it already holds `PROXY_TLS_KEY` and the Inngest keys; R2 state holds it too.
**Brand-survival threshold:** aggregate pattern.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "flip variables.tf web2_lb_weight default 0 -> 1 (variables.tf, cloudflare-lb.tf) as its OWN commit" [brief] | Phase 1 / `variables.tf` + `cloudflare-lb.tf` entries; commit 1 | mapped |
| 2 | "drain passes an EXPLICIT -var=web2_lb_weight=0 and still plans {web-1:1, web-2:0}" [brief] | Phase 1 task 1.4 (pin-step comments), fixtures pu1 and pu15, the existing `-var` at the plan step | mapped |
| 3 | "serve plans {1,1} and must accept a no-op \"no changes\" plan as well as a 0->1 diff (live is already 1)" [brief] | Phase 1 tasks 1.1-1.3 (gate lib, fixtures pn1-pn8) | mapped |
| 4 | "update tests/scripts/lib/cf-lb-overlay-gate.sh cf_lb_gate_ga_pool_update pins, lb-weight-gate.test.sh C.3/C.4 + the WEB2_LB_WEIGHT step census" [brief] | Phase 1 tasks 1.1-1.6 | mapped |
| 5 | "rewrite (do not leave stale) the runbook sections the relay-evidence work added, incl. cf-lb-a-record-gaplessness-verify.md post-serve procedure" [brief] | Phase 1 tasks 1.4 and 1.7 (rewrite, plus a one-time repo-wide grep recorded in the work log) | mapped |
| 6 | "confirm nothing in apply-web-platform-infra.yml's -target set plans the pool ... also grep every workflow for a full-root terraform run" [brief] | Research Reconciliation rows 5-6 + Phase 3.7 evidence capture | mapped |
| 7 | "after merge the scheduled drift plan is clean with no -var and no full-root plan proposes web-2 1->0" [brief] | AC-1, AC-14 (post-merge read-only verification) | mapped |
| 8 | "Terraform-mint the NEW relay hello-signing secret PROXY_HELLO_HMAC_KEY (64 hex chars = 32 random bytes) exactly like proxy_tls_key" [brief] | Phase 2 (`proxy-hello-hmac.tf`) | mapped (generator deviates, ruling 6) |
| 9 | "plus -target= lines in apply-web-platform-infra.yml beside the proxy_tls_key/proxy_tls_cert lines (~L680) and any matching test/census pins" [brief] | Phase 2 tasks 2.1-2.3 | mapped |
| 10 | "verify the path filters (release workflow push arm and infra apply workflow) ... and record the evidence" [brief] | Research Reconciliation row 1 + Phase 3.6 | mapped |
| 11 | "PR body: \"Closes #12363\"; do NOT close #12288/#12289/#12290" [brief] | Phase 4.1 PR-body block | mapped |
| 12 | "The plan must end with an `## Operator Holds` section" [brief] | final section | mapped |
| 13 | "a NEW suite needs `regenerate-shard-manifest.py --incremental --write` rows and a test-affected-kb-consumers baseline decision" [brief] | Phase 3.3-3.4 (no new suite; proven by an empty diff) | mapped |
| 14 | "mutate each new guard on a sandbox copy (bash scripts/soleur-sandbox.sh new/rm), control green first; floors EXACT and derived" [brief] | Guard Contract + Phase 3.5 + floor table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `variables.tf`, `cloudflare-lb.tf` | "flip variables.tf web2_lb_weight default 0 -> 1" | asked |
| `tests/scripts/lib/cf-lb-overlay-gate.sh`, `tests/scripts/test-cf-lb-overlay-gate.sh` | "update tests/scripts/lib/cf-lb-overlay-gate.sh cf_lb_gate_ga_pool_update pins" | asked |
| `apps/web-platform/infra/lb-weight-gate.test.sh` | "lb-weight-gate.test.sh C.3/C.4 + the WEB2_LB_WEIGHT step census" | asked |
| `.github/workflows/cf-lb-overlay.yml` (pin-step comments) | "the WEB2_LB_WEIGHT step census" | asked |
| `.github/workflows/cf-lb-overlay.yml` (`ga_overlay` explicit `-var=0`) | — | inferred — justification: without it the default flip silently changes ga-overlay's create shape to web-2 weight 1, which its own grader refuses (CTO ruling 5); behaviour-neutral is the brief's own framing |
| runbook `cf-lb-a-record-gaplessness-verify.md` | "rewrite (do not leave stale) the runbook sections" | asked |
| `ADR-068` amendment | — | inferred — justification: plan Phase 2.10 makes the ADR write a deliverable of the plan that changes an ADR-recorded invariant ("only feeder is the serve arm") |
| `model.c4` (L448 only) + regenerated `model.likec4.json` | — | inferred — justification: the `cloudflare` description states the pool shape this PR persists (web-2 drained at weight 0), which would otherwise contradict the tree (C4 completeness mandate); the other weight statements pre-date this change and ride a follow-up |
| `apps/web-platform/infra/proxy-hello-hmac.tf` (new) | "Terraform-mint the NEW relay hello-signing secret PROXY_HELLO_HMAC_KEY" | asked |
| `.github/workflows/apply-web-platform-infra.yml` (+2 lines) | "-target= lines in apply-web-platform-infra.yml beside the proxy_tls_key/proxy_tls_cert lines" | asked |
| `plugins/soleur/test/terraform-target-parity.test.ts` | "any matching test/census pins" | asked |
| `tests/scripts/test-tf-redact-random-ids.sh` (fixture) | — | inferred — justification: CTO ruling 6; the first `random_bytes` at a counted address must be proven redacted by the existing log filter or the plan comment could print it |
| `variables.tf` `host_proxy_tls_enabled` description | — | inferred — justification: its description enumerates the gated resources; leaving the new pair out makes the enumeration false |
| Guard Contract mutation batteries | "mutate each new guard on a sandbox copy" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform/infra/`, `.github/workflows/`, `tests/scripts/`, `plugins/soleur/test/`, `knowledge-base/`
- Planned files: 17 (13 edits including the regenerated model JSON, 1 new `.tf`, plus `tasks.md` and `decision-challenges.md` under specs) | Estimated changed lines: about 500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, two commits. The subsystem threshold is exceeded only because tests and docs travel with each infra change; the two halves share no file, and the CTO ruled single-PR-two-commits (decision-challenges items 1, 2, 8). If the mint half is questioned in review it detaches cleanly (Phase 2 touches `proxy-hello-hmac.tf`, two workflow lines, the parity test and the redactor test only).

## Implementation Phases

Order inside each commit is tests first (`cq-write-failing-tests-before`): write the RED assertions, run them against the unchanged tree to see them fail for the right reason, then make them green. Run every command from the worktree root. Never print or place a secret on a command line.

### Phase 0 — Baseline and safety

- 0.1 Confirm the worktree and a clean tree (`git status --short` empty except plan artifacts).
- 0.2 Record the baselines (command, expected current output): `bash tests/scripts/test-cf-lb-overlay-gate.sh | tail -1` (110 assertions), `bash apps/web-platform/infra/lb-weight-gate.test.sh | tail -2` (282 passed), `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts` (372), `wc -c .github/workflows/apply-web-platform-infra.yml` (488411), `python3 scripts/lint-encryption-posture.py | tail -1` (PASS), `bash plugins/soleur/test/c4-count-parity.test.sh | tail -1` (ALL TESTS PASSED).
- 0.3 Initialise the root offline so `validate` and `fmt -check` can run later: `terraform -chdir=apps/web-platform/infra init -backend=false -input=false`. Do not plan against live state; do not dispatch any workflow; no Doppler write; `flip.sh` is never run.

### Phase 1 — Commit 1: persist web-2's weight (flip)

**1.1 RED first (two pin groups).**
- (a) `tests/scripts/test-cf-lb-overlay-gate.sh` already defines fixtures `pu1` through `pu36`, so the new rows use the distinct prefix `pn` (pool no-op) to keep labels unique. Reuse `WEB1`, `WEB2`, `GA_LB_UPD`, `POLICY_CREATE`, `POLICY_UPD`; add `POOL_NOOP_SERVE` (= `POOL_NOOP` with web-2 weight 1) and `LB_NOOP`/`POLICY_NOOP` no-op entries. Every serve defect fixture also carries `POLICY_CREATE`, so that against the CURRENT lib it falls into the pool-less remnant branch and passes (wrongly) rather than hitting the empty-set refusal: that is what makes it RED now and GREEN-as-refusal later.

  | Fixture | Mode | Entries | Expect (and today's result) |
  |---|---|---|---|
  | pn1 | serve | WEB1, WEB2, POOL_NOOP_SERVE, LB_NOOP, POLICY_NOOP (the realistic post-flip shape: everything no-op) | pass, plus a second assertion on the notice "pool already {web-1:1, web-2:1}" (today: refused as an empty change set) |
  | pn2 | serve | WEB1, WEB2, POOL_NOOP_SERVE, POLICY_CREATE | pass (today: remnant pass without grading) |
  | pn3 | serve | WEB1, WEB2, POOL_NOOP (web-2 weight 0), POLICY_CREATE | refuse (today: vacuous pass) |
  | pn4 | serve | WEB1, WEB2, POOL_NOOP_SERVE with web-1 at weight 0, POLICY_CREATE | refuse (today: vacuous pass; proves origin pins reach the no-op path) |
  | pn5 | serve | WEB1, WEB2, POLICY_CREATE (pool entry absent) | refuse, and the message must be the new distinct "pool absent from the plan" text (today: remnant pass) |
  | pn6 | serve | WEB1, WEB2, pool actions `["delete","create"]`, POLICY_CREATE | refuse (allow-set) |
  | pn7 | drain | WEB1, WEB2, POOL_NOOP only | refuse (empty set; drain unchanged; today also refuses, so this row is a regression pin, not a RED) |
  | pn8 | serve | pn1's plan with `TMPDIR` pointed at a fixture dir and a `mktemp` shim that records the path it handed out | after the call the dir is empty AND the shim saw exactly one file created there (positive control: a wrapper that ignores `TMPDIR` or never creates a copy cannot pass) |
  | pn9 | serve | pn4's plan (a refusing no-op plan) with the same shim | rc 1 and the dir is empty (cleanup on the refuse path) |
  | pn10 | serve | pn1's plan with the pool entry carrying `previous_address` (a state move) | refuse (normalization predicate is exact) |
  | pu15 (exists) | drain | POOL_NOOP + POLICY_CREATE | still admitted with the "grading the remaining change(s) only" notice (assertion retained) |

  Assertion count added: pn1 (2) + pn2 + pn3 + pn4 + pn5 (2: refusal and message) + pn6 + pn7 + pn8 (2: empty dir, shim saw one file) + pn9 (2: rc, empty dir) + pn10 = 14.
- (b) `apps/web-platform/infra/lb-weight-gate.test.sh`: C.4-V2 expects `default = 1` (type number, default 1); C.4-F6 becomes "exactly TWO non-comment lines name `web2_lb_weight`: the ga_pool_update plan step (`${WEB2_LB_WEIGHT}`) and the ga_overlay plan step (literal `0`)"; new F8 pins the `ga_overlay` plan step: `-var="web2_lb_weight=0"` exactly once with the literal value 0. C.4's `JOB`/`step_of`/`PLAN_STEP` helpers are awk-keyed on `^  ga_pool_update:`, so F8 needs its own extractor: `GAO_JOB` keyed on `^  ga_overlay:` and `GAO_PLAN` on the step named `Terraform plan (GA LB trio only)` (same awk shape, a parameterised `job_step_of <job> <name-ere>` is fine). C.3 fixture labels are reworded from "default-0 gated variable" to "gated variable (validation admits only 0 or 1)" and the C.3/C.4 header comments are rewritten. Two in-suite mutants on a `mktemp` copy (value 1, line deleted) assert LANDED then RED.
- (c) No prose census. The stale-wording sweep is a one-time repo-wide grep in Phase 1.4 whose output goes to the work log (a phrase census cannot prove prose true, would make an infra-validation suite read `knowledge-base/`, and the suite does not even run on a runbook-only change).
- (d) Run all suites; keep the RED output as evidence in the work log.

**1.2 Gate change (GREEN), `tests/scripts/lib/cf-lb-overlay-gate.sh`.** Behaviour fixed by CTO ruling 4; mechanism chosen at plan review to avoid editing the 17 pool selectors inside the grader (each is a single-quoted jq program with `--arg`, so fragment interpolation means re-quoting all of them):
- Rename the existing function body to `_cf_lb_gate_ga_pool_update_graded` unchanged. Add a thin `cf_lb_gate_ga_pool_update` wrapper (it declares `local plan_json="$1" mode="${2:-drain}"`, the load-bearing parameter name for the preamble drift test) that: validates the mode; runs `plan_gate_assert_readable` and `plan_gate_assert_classifiable` on the ORIGINAL file first; for `drain` calls the inner function directly; for `serve` derives, with every jq call guarded by `|| return 1`, the number of RAW `.resource_changes[]` entries whose address contains `cloudflare_load_balancer_pool.web_1` (raw, because `_CF_LB_CHANGES` drops no-ops) and the single entry's actions string, then dispatches through a three-way `case` where the default arm REFUSES (an empty or unparseable probe result can never fall through to the old vacuous pass): (1) zero entries, or more than one (a deposed duplicate, a module-prefixed twin) → refuse with a distinct "pool absent from, or ambiguous in, the plan" message; (2) actions exactly `["update"]` → inner function on the original file; (3) actions exactly `["no-op"]` AND the entry has an exact address match, no `previous_address`, no `change.importing`, no `deposed` → normalized copy (below), otherwise refuse.
- Normalized copy, hardened (security review): `umask 077`; `local tmp rc; tmp="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ga-pool-serve.XXXXXXXX.json")" || return 1` (never `local tmp=$(mktemp)`, which masks the failure; never `mktemp -u`, `$$` or fixed names); the copy is built as `{resource_changes: [...]}` ONLY (the inner function reads nothing else, and dropping `prior_state`/`planned_values`/`configuration` means a leaked copy holds no state values, including the future hello key), with only the pool entry's actions rewritten to `["update"]`; `jq ... > "$tmp" || { rm -f "$tmp"; return 1; }`; then `_cf_lb_gate_ga_pool_update_graded "$tmp" serve; rc=$?; rm -f "$tmp"`; the notice `cf-lb-overlay gate[ga-pool-update:serve]: pool already {web-1:1, web-2:1} (no-op against live; the pass line below counts the normalized pool as one change) — pass` is printed (before the inner line, so the log reads true) only when the pool was a no-op, and the function ends `return $rc`. The only call site is `... || { ...; exit 1; }` under `set -euo pipefail`, where errexit is suppressed inside the function, so every failure path above returns explicitly instead of relying on `set -e`.
- Why this is safe: the normalization is applied to the pool entry only, after which the inner function sees an ordinary update-shape plan, so every origins, enabled, monitor, resolved-IP and weight pin (the {1,1} serve quartet) grades the no-op pool exactly as it grades a 0-to-1 update; the empty-set refusal, the allow-set and the drain-only remnant branch are untouched. The remnant branch can no longer be reached by serve because serve with a pool entry always presents `pool_updates == 1`, and serve without one is refused by the wrapper.
- The lib header paragraph ("`serve` is the #6027 window arm") is rewritten: serve grades the pool whether it is an update (0-to-1) or a no-op (already {1,1}), via the wrapper's normalization.

**1.3 Floors.** After the gate suite is green, set the `checks -lt` floor in `test-cf-lb-overlay-gate.sh` to the measured post-change `checks` value (baseline 110 plus the 14 enumerated assertions is the cross-check); the old 98 is 12 loose and is tightened here, not preserved.

**1.4 Variable, tf comments, workflow.**
- `apps/web-platform/infra/variables.tf`: `default = 1`; rewrite the leading comment block and the `description` ("web-2 origin weight in the GA LB pool (0 = drained, 1 = serving). Default 1 = the live serving shape after the #12167 serve flip; drain is explicit via cf-lb-overlay ga-pool-update mode=drain (passes 0) and ga-overlay (passes 0). Do not set via Doppler or tfvars."). The validation block (admits only 0 or 1) is unchanged.
- `apps/web-platform/infra/cloudflare-lb.tf`: comment-only edits at the header B2 line (L10-13), L48 ("web-2 is weight 0 and the B1 fallback..."), L70 ("web-2 drained at weight 0 (B2)"), L87 and the web-2 origin block (L88-95): "default 1 = serving, matches live; drain rides ga-pool-update mode=drain, the GA3 create rides ga-overlay with an explicit 0". `weight = var.web2_lb_weight` stays byte-identical (pin C.4-V5). EXCEPTION, left untouched on purpose: L160 is a live `description =` attribute on `cloudflare_load_balancer.app` ("web-2 drained at weight 0 until the #6027 window flip"); editing an attribute value would plan a standing LB update and drift noise, so the file stays comment-only and the stale attribute text is listed in follow-up (c) to be changed together with an intentional LB apply.
- Other stale comment or description text found by the line audit: `variables.tf` L181 (a comment calling web-2 "serving-weight 0": rewrite); `cf-lb-overlay.yml` L25 (header "web-2 at weight 0; mode=serve is the #6027 window 0→1 flip"), L55 (the workflow_dispatch input `description:` for mode — a dispatch-input description, not Terraform state, so editing it is safe and required: "drain = web-2 explicitly set to weight 0; serve = grade and apply web-2 weight 1 (already 1 after the 2026 serve flip) behind the §(c) gate chain"), L706 and L879 (job comments). Run `grep -rnIiE 'weight[ -]?0|default[ -]?0|drained' apps/web-platform/infra/variables.tf apps/web-platform/infra/cloudflare-lb.tf .github/workflows/cf-lb-overlay.yml knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md` before and after; every remaining hit must be either a true statement about drain as an explicit act or the named L160 exception. Record the output in the work log.
- `.github/workflows/cf-lb-overlay.yml`: (i) the `ga_overlay` plan step gains `-var="web2_lb_weight=0" \` after the `ssh_key_path` var line, with a two-line comment; (ii) the pin-step comment ("1 only for mode=serve, else 0 (the variable's default)") is reworded to "else 0 (an explicit pass; the variable's default is 1)" without touching the if/else line that C.4-F4 pins; (iii) the plan-step comment block is reworded likewise. The `ga_pool_update` `-var` line is unchanged. Check the YAML parses: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/cf-lb-overlay.yml"))'`.

**1.5 Re-run all suites GREEN** and confirm each RED row from 1.1 flipped for the right reason (the lib changed, not the fixture).

**1.6 C.3 static anti-pooling guard stays correct.** `lb-weight-gate.test.sh` C.3 accepts `weight = var.web2_lb_weight` as the gated form. With default 1 the committed tree now intentionally pools web-2, so C.3's meaning narrows to "the member weight is the literal 0 or the validated gated variable, never another expression or literal". Reword its comments accordingly; the regexes do not change.

**1.7 Runbook rewrite, `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md`.** Rewrite (no stale remnants):
- Arm list (L377-378): `mode=drain` "pins web-2's after-weight to 0 (explicit `-var`)"; `mode=serve` "grades the pool whether the plan is the 0-to-1 update or a no-op against live {1,1}; still behind the gate chain, health precondition and relay bind probe".
- "Before dispatching `mode=serve`" (the relay-evidence section): add that after the persisted flip a serve dispatch is a re-proof, not a state change, ending in a no-op apply and the 90-sample continuity check; the three evidence rows are unchanged.
- "After a successful serve" becomes "After the serve: the tree and live agree on web-2 = 1 (#12363)": the default is 1; the scheduled drift plan is clean with no `-var`; the per-merge apply cannot touch the pool (hard `-target` lists name no `cloudflare_load_balancer*` address and no targeted resource references the pool); `ga-overlay` passes an explicit 0 so its create shape is drained and its grader still refuses an update; a full-root plan or out-of-CI full-root apply after an INTENTIONAL drain proposes `0 -> 1` (the standing drift signal until the default is flipped back or serve is re-run); the rollback lever is `ga-pool-update mode=drain` followed by a PR returning the default to 0 if the drain is to persist, and a drain is NOT durable until that PR lands (the next unrelated untargeted apply restores weight 1); the new MUST (security review): any untargeted apply that creates or replaces `hcloud_server.web["web-2"]` or the pool passes `-var=web2_lb_weight=0`, because at the new default an empty replacement host would enter the pool at weight 1 before the serve gate chain runs (at the old default it landed drained). The same MUST is added to `fresh-host-bootstrap-recovery.md` step 3 and to the ADR-068 addendum; the one-way language and the `-var=web2_lb_weight=1` drift-read instruction are deleted. The old "Follow-up PR (required after a successful serve)" paragraph is replaced by one line, "Done in #12363".
- L424 ("web-2 is weight 0, the B1 fallback serves web-1") is corrected to the live shape (both origins serve; an unhealthy origin falls back via B1 to web-1).
- The runbook states the rule in one sentence: "The `web2_lb_weight` default is 1 (live web-2 serves); drain is an explicit `-var=web2_lb_weight=0`."

**1.8 ADR-068 addendum (dated 2026-11-08)** via `soleur:architecture`, following the file's own convention of a new `## Addendum — <date>` heading at the end of the file (the file's options section is `## Considered Options`, not "Alternatives Considered"): `## Addendum — 2026-11-08 (#12363)`: the 2026-11-01 addendum's "weight = 0 until the #6027 window flips 0→1" is now history because the serve flip applied; web-2 serves at weight 1 and the Terraform default (`web2_lb_weight`) is 1; drain is the explicit act (`ga-pool-update mode=drain` and `ga-overlay` pass 0); the serve grader accepts a no-op plan against live {1,1}; the full-root hazard inverts (a full-root plan after an intentional drain proposes 0-to-1). The rejected option goes in the addendum body (not a table row): keep default 0 and pass `-var=...=1` in every non-serve plan — rejected because the drift workflow and every ad-hoc plan would need the variable and a forgotten variable drains web-2. Do not attribute the "only feeder is the serve arm" invariant to the ADR; it lives in the runbook, `variables.tf` and C.4. The addendum also carries the untargeted-apply MUST from 1.7 and the non-durable-drain sentence.

**1.9 C4 (model.c4), minimal.** The `cloudflare` element (L448) is the description of the very pool shape this PR persists ("web-2@0 drained until the #6027 window flip"): change that one phrase to "web-2@1 serving since the 2026-11 serve flip, #12167; drain is an explicit ga-pool-update act" (read the whole sentence first; keep everything still true). Then `bash scripts/regenerate-c4-model.sh` and run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh`. The other weight statements (`hetzner` L351, `workspacesVolume` L355, `betterstack -> hetzner` L926) and the role wording stale for other reasons ("scheduler-less standby" L347/L792; "A record is web-1 only" L849/L1006) pre-date this change (live web-2 has served since the flip), are entangled with LUKS/plaintext gating prose that needs its own careful read, and travel in follow-up (c) rather than widening this PR (plan-review taste call, recorded in decision-challenges item 9).

**1.10 Commit 1** (`fix(infra): persist web-2 LB weight 1 and accept serve no-op plans (#12363)`): every Phase 1 file. Pre-commit: `terraform fmt -check` on the two `.tf` files, `shellcheck -S warning` on touched `.sh`.

### Phase 2 — Commit 2: mint PROXY_HELLO_HMAC_KEY

**2.1 RED first.**
- `plugins/soleur/test/terraform-target-parity.test.ts`: four new tests next to the proxy-TLS tests (not widening the quartet test): (T1) `random_bytes.proxy_hello_hmac` and `doppler_secret.proxy_hello_hmac_key` each carry `count = var.host_proxy_tls_enabled ? 1 : 0`; (T2) both addresses are in the saved plan's `planTargets`, absent from `OPERATOR_APPLIED_EXCLUSIONS`, and absent from the `web_host_create`/`web_host_replace` dispatch jobs' targets (non-vacuity assert on `hcloud_server.web` as the quartet test does); (T3) shape: `random_bytes` has `length = 32`; the secret has `project = "soleur"`, `config = "prd"`, `name = "PROXY_HELLO_HMAC_KEY"`, `visibility = "masked"`, `value = random_bytes.proxy_hello_hmac[0].hex` exactly, and `proxy-hello-hmac.tf` declares no `output` (deliberately NOT pinned: `keepers`/`lifecycle` absence, since PR A's previous-key rotation will legitimately change those); (T4) a two-mutant in-test battery over T1-T3 on string copies (Guard 3).
- `tests/scripts/test-tf-redact-random-ids.sh`: ONE fixture for the count-indexed `random_bytes.proxy_hello_hmac[0]`: the `# random_bytes.proxy_hello_hmac[0] will be created` plan block with `hex = (sensitive value)`, asserting no value-like token survives and the line shape is preserved. No "Refreshing state [id=...]" fixture (the type has no `id`, per Phase 2.2). FIRST CHECK, before writing anything else: confirm the redactor's block-start recognition accepts a counted `[0]` address; if it does not, fix the redactor in this commit (add it to Files to Edit) — the redactor suite's own floor (`MIN_ASSERTIONS`, currently equal to its measured 327) then moves by exactly the rows added.
- Run: T1-T3 go RED because neither the `.tf` nor the `-target` lines exist (the generic "every resource is targeted or excluded" census stays green until the file exists).

**2.2 GREEN: `apps/web-platform/infra/proxy-hello-hmac.tf` (new).** Header comment cites proxy-tls.tf and ADR-118 and states: one shared key for both hosts (equally trusted owned nodes, the same proportionality as the shared TLS cert); `prd` only (the relay does not run in dev; PR A's tests use synthesized fixtures, `cq-test-fixtures-synthesized-only`); no auto-rotation; and the rotation rule from CTO ruling 6 (no replace or taint of `random_bytes.proxy_hello_hmac` until the verifier accepts a previous key; each host reads the secret at container start, so a rotation splits web-1 and web-2 across keys during the rolling redeploy). Deepen-plan additions to the header: the count gate is ALSO a rotation lever (setting `host_proxy_tls_enabled` false destroys the pair and setting it true again mints a DIFFERENT key, which a fail-closed hello would turn into a relay outage), the gate couples this key's lifecycle to the TLS flag on purpose, and a later `count`-to-`for_each` or rename refactor needs a `moved {}` block or it replaces the key. Resources:

```hcl
resource "random_bytes" "proxy_hello_hmac" {
  count  = var.host_proxy_tls_enabled ? 1 : 0
  length = 32
}

resource "doppler_secret" "proxy_hello_hmac_key" {
  count      = var.host_proxy_tls_enabled ? 1 : 0
  project    = "soleur"
  config     = "prd"
  name       = "PROXY_HELLO_HMAC_KEY"
  value      = random_bytes.proxy_hello_hmac[0].hex
  visibility = "masked"
}
```

Before writing, verify the attribute against the locked provider, not memory: after the offline init, `terraform -chdir=apps/web-platform/infra providers schema -json` filtered with jq at `.provider_schemas["registry.terraform.io/hashicorp/random"].resource_schemas.random_bytes.block.attributes` must show `hex` with `sensitive: true` and no `id` key (the CTO read this for 3.9.0; the task re-proves it on the lock file so a provider bump cannot silently change it).

**2.3 GREEN: workflow and descriptions.**
- `.github/workflows/apply-web-platform-infra.yml`, directly after `-target=doppler_secret.proxy_tls_cert \`: insert `-target=random_bytes.proxy_hello_hmac \` and `-target=doppler_secret.proxy_hello_hmac_key \`. Nothing else in the file changes (no comment prose; byte budget). Re-measure: `wc -c` under 490,000 and `bun test plugins/soleur/test/workflow-file-size.test.ts` green.
- `variables.tf` `host_proxy_tls_enabled` description: name the new pair and fix the counts ("the four resources" / "the four addresses" become six; setting the flag false then plans six destroys and needs `[ack-destroy]`); sweep any fixture or test that hard-codes four.
- Sweep the guard suites the `-target` extension can break: `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`; the parity test as a whole; the "terraform stream key-material redaction" describe (it derives key-bearing types from the HCL; the root already declares `random_id`, so every step already redacts — assert it still passes with `random_bytes` newly counted).

**2.4 Floors.** `TEST_FLOOR`: re-derive with `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts` after the change and set it to that exact value, with a one-line comment in the file's existing history style naming this change.

**2.5 Commit 2** (`feat(infra): mint PROXY_HELLO_HMAC_KEY for the signed relay hello (Ref #12289)`).

### Phase 3 — Verification (all local; read-only against live systems)

- 3.1 Suites: `bash tests/scripts/test-cf-lb-overlay-gate.sh`; `bash apps/web-platform/infra/lb-weight-gate.test.sh`; `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/workflow-file-size.test.ts`; `bash tests/scripts/test-tf-redact-random-ids.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; the C4 vitest pair; `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`.
- 3.2 Pre-push gates (all clean): the `fixture-relative-assert.test.sh` suite (locate with `git ls-files | grep fixture-relative-assert`), `python3 scripts/lint-shell-capture-exit.py --baseline`, `python3 scripts/lint-trap-tempfile-ownership.py`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt`, `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`, `shellcheck -S warning` on every touched `.sh`, `terraform -chdir=apps/web-platform/infra fmt -check` and `validate`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/test-all-corpus-weight-budget.test.sh`, `python3 scripts/lint-encryption-posture.py`, `python3 scripts/lint-guard-contract.py` on this plan.
- 3.3 Shard manifest: `python3 scripts/regenerate-shard-manifest.py --incremental --write`, then `git status --short -- scripts apps/web-platform/infra | grep -E '\.tsv$'` must print nothing. A non-empty result means a new suite slipped in: stop and reconcile.
- 3.4 test-affected-kb-consumers baseline decision: no change and no new analysis needed. The oracle's population is derived from `test-all.sh` registrations; the only registered suite touched is `tests/scripts/cf-lb-overlay-gate`, whose new assertions read no `knowledge-base/` path, and no assertion anywhere reads the runbook (the stale-wording sweep is a one-time grep, Phase 1.4). Check: `bash scripts/test-affected-kb-consumers.test.sh` green and `git diff --stat -- scripts/test-affected-kb-consumers.baseline.txt` empty. (Do not run `test-all.sh --print-selection`: it exceeds a minute here.)
- 3.5 Sandbox mutation (Guard Contract rows): `bash scripts/soleur-sandbox.sh new` creates the sandbox copy; run each guard's CONTROL (pristine, must be green) first, then each mutation (it must LAND, asserted by `cmp` against pristine, and go RED for the named reason), then `bash scripts/soleur-sandbox.sh rm`. Record the control and each RED in the work log. Guard 1's lib-source mutations and Guard 3's tf/yml mutations run in the sandbox; Guard 2's two mutants run in-suite on a `mktemp` copy (the sandbox run repeats them once as the control-green proof, not as a second implementation).
- 3.6 Path-filter evidence (record in the PR body): re-run `git show --name-only --format=%h <sha>` for 960ec26913, 9682d9440d and e2964b801d and confirm each touches only paths the release filter excludes plus `apps/web-platform/infra/`; then the release run list for those three (`gh run list --workflow web-platform-release.yml --commit <sha> --json event,conclusion -L 3`); the `paths:` blocks of `web-platform-release.yml` and `apply-web-platform-infra.yml` quoted; `apps/web-platform/infra/**` matches the new and edited `.tf` files; the release `path_filter` `apps/web-platform/` matches them too (so the release arm fires, accepted).
- 3.7 Evidence that nothing else plans the pool (record verbatim): `grep -c cloudflare_load_balancer .github/workflows/apply-web-platform-infra.yml` prints 0; `grep -ln 'cloudflare_load_balancer_pool.web_1\|cloudflare_load_balancer.app\|cloudflare_load_balancer_monitor.web' apps/web-platform/infra/*.tf` prints only `cloudflare-lb.tf`; `grep -c web_lb_health .github/workflows/apply-web-platform-infra.yml` prints 0 and `grep -rln 'web_lb_health\|load_balancer_pool' apps/web-platform/infra/*.tf` prints only `cloudflare-lb.tf` (the pool's real dependent is the notification policy, and a `-target` on it would pull the pool in); the full-root plan inventory from Research Reconciliation. Read-only Doppler name check with the existing read-only token: `doppler secrets --only-names -p soleur -c prd_terraform | grep -c '^WEB2_LB_WEIGHT$'` prints `0` (the drift workflow runs under `--name-transformer tf-var`, so a `WEB2_LB_WEIGHT` value there would override the new default and hide the flip from the drift plan; C.4-F2 pins only the repo tree).
- 3.8 Pre-merge precondition (Terraform review): the first scheduled drift run AFTER the 2026-11-08 serve flip (the 18:00Z run or later; before 14:40Z the pool read {1,0} in state) must list no `cloudflare_load_balancer_pool.web_1` change in the `apps/web-platform/infra` leg. If instead the PR plan comment shows `~ origins` with only hidden attributes, stop: that is provider-normalisation churn, not the weight. Read-only (`gh run list` / `gh run view`).

### Phase 4 — PR body, follow-ups, post-merge

- 4.1 PR body: `Closes #12363` only; `Ref #12288`, `Ref #12289`, `Ref #12290`, `Ref #8211`, `Ref #12167`. State: squash-merge means the "own commit" exists only in branch history; revert rule: revert the flip hunk only, never the whole squash. State the release-arm finding (a release of unchanged app bits fires and deploys to both hosts; accepted; evidence from 3.6). State that the generator is `random_bytes` and why. The `infra-validation` plan comment is a FULL-ROOT plan (`-refresh=false`) and already carries unrelated config-versus-state diffs (the 2026-11-08 06:02Z drift plan showed 5 to add / 5 to destroy before this PR), so the check is relative, not absolute: it must contain `# random_bytes.proxy_hello_hmac[0] will be created` and `# doppler_secret.proxy_hello_hmac_key[0] will be created` (value sensitive), its add count must be exactly +2 against the same plan on the base branch, and it must contain NO `cloudflare_load_balancer_pool.web_1 will` block; a pool diff means state is not 1 (or the provider normalises an attribute) and the PR must stop.
- 4.2 Follow-up issues to create at ship time (each with what, why, a re-evaluation criterion, and a milestone from `knowledge-base/product/roadmap.md`): (a) audit excluding `apps/web-platform/infra/` from the release `on.push.paths`, `path_filter` and `RELEASE_PATH_FILTER`, together with the `scripts/prod-version-drift-check.sh` PATHSPEC and its B8/P3 pins (re-evaluate before the next infra-only PR that must avoid a deploy); (c) stale C4 and Terraform-attribute wording: `model.c4` L351/L355/L926 (weight-0 statements entangled with LUKS gating prose), L347/L792 ("scheduler-less standby" role), L849/L1006 ("A record is web-1 only"), and the live `description =` attribute at `cloudflare-lb.tf` L160 (to change together with an intentional LB apply). Issue (b) from the CTO ruling is NOT a separate issue: PR A's rollout compatibility (a rolling deploy with a fail-closed hello means a new and an old host disagree, so A needs a dual-accept window or ordered rollout) and the previous-key mechanism are design inputs for PR A, posted as a comment on #12289 (the issue that owns A) at ship time, together with two hard preconditions for A (add `PROXY_HELLO_HMAC_KEY` to the Sentry scrub list in `apps/web-platform/server/sensitive-keys.ts` beside `PROXY_TLS_KEY`; run the Phase 4.3 presence read before A merges); the rotation rule is already in the `.tf` header.
- 4.3 Post-merge, read-only, no operator checklist (`hr-ship-message-no-operator-checklist`): `soleur:postmerge` verifies (i) the `apply-web-platform-infra.yml` run on the merge commit succeeded and its log shows `Creation complete` for both new addresses (match the ADDRESS and `Creation complete`, not an `[id=...]` suffix: `random_bytes` has no `id`, so its line reads `random_bytes.proxy_hello_hmac[0]: Creation complete after 0s` with none); (ii) the first `scheduled-terraform-drift.yml` run created after the merge's apply run completed is clean for the `apps/web-platform/infra` matrix leg: read the run log for that leg and require the line `No drift detected in web-platform` (a drift-flagged run can still conclude green, because exit 2 only warns and opens an issue, so the run conclusion is not the signal; also require no open `infra: drift detected in web-platform` issue); read via `gh run list` and `gh run view --log`, never a dispatch; (iii) a presence read of the prd secret with the existing read-only prd token (`DOPPLER_TOKEN_TF`, the token `scripts/key-rotate.sh` reads prd names with; the listing is a table, so the match uses a non-alphanumeric boundary as `kk_copy_state` does, and an empty or failed listing is UNKNOWN, never absent). Refinement of CTO ruling 7(c) from the security review (decision-challenges item 13): the names-only form is primary because it never puts the value in the verifier's process; the value-shape read is optional where the token may read values; run neither under `set -x` and never with `2>&1`. Names-only: `doppler secrets --only-names -p soleur -c prd | grep -Ec '(^|[^A-Za-z0-9_])PROXY_HELLO_HMAC_KEY([^A-Za-z0-9_]|$)'` prints `1`. Value-shape, count only: `doppler secrets get PROXY_HELLO_HMAC_KEY -p soleur -c prd --plain | grep -Ec '^[0-9a-f]{64}$'` prints `1` and never the value (CTO ruling 7); where the verifying token is not permitted to read values, the names-only form `doppler secrets --only-names -p soleur -c prd | grep -Ec '(^|[^A-Za-z0-9_])PROXY_HELLO_HMAC_KEY([^A-Za-z0-9_]|$)'` printing `1` is the accepted fallback (the hex shape is then guaranteed by `random_bytes` length 32 and the T3 pin). The same count-only check becomes a recorded precondition in PR A's plan. This is a post-merge verification, not a soak: no follow-through enrollment is needed because no N-day signal must hold before anything closes.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — `web2_lb_weight` default 1, comment and description; `host_proxy_tls_enabled` description
- `apps/web-platform/infra/cloudflare-lb.tf` — comment-only (header B2 and web-2 origin block)
- `.github/workflows/cf-lb-overlay.yml` — `ga_overlay` explicit `-var`, pin-step and plan-step comments
- `.github/workflows/apply-web-platform-infra.yml` — two `-target` lines after `proxy_tls_cert`
- `tests/scripts/lib/cf-lb-overlay-gate.sh` — `cf_lb_gate_ga_pool_update` serve no-op grading, header comment
- `tests/scripts/test-cf-lb-overlay-gate.sh` — pn1-pn8 fixtures, exact floor
- `apps/web-platform/infra/lb-weight-gate.test.sh` — V2, F6, F8 (own ga_overlay extractor), C.3 wording, two F8 mutants, `MIN_CASES`
- `plugins/soleur/test/terraform-target-parity.test.ts` — four tests, exact `TEST_FLOOR`
- `tests/scripts/test-tf-redact-random-ids.sh` — `random_bytes.proxy_hello_hmac[0]` fixtures
- `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md` — rewritten sections (1.7)
- `knowledge-base/engineering/operations/runbooks/fresh-host-bootstrap-recovery.md` — step 3 ("apply to RECREATE the fresh host") gains the explicit `-var=web2_lb_weight=0` rule (see 1.7)
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — dated addendum
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` (regenerated) — weight statements only

## Files to Create

- `apps/web-platform/infra/proxy-hello-hmac.tf`
- `knowledge-base/project/specs/feat-one-shot-12363-web2-weight-persist-hello-key/tasks.md` (`decision-challenges.md` already exists)

## Infrastructure (IaC)

### Terraform changes

New file `apps/web-platform/infra/proxy-hello-hmac.tf` in the existing web-platform root (R2 backend already configured). Resources `random_bytes.proxy_hello_hmac` and `doppler_secret.proxy_hello_hmac_key`, both `count = var.host_proxy_tls_enabled ? 1 : 0`. Providers: `hashicorp/random` `~> 3.0` locked at 3.9.0 (confirmed against the lock file in Phase 2.2) and the existing `doppler` provider; no new provider, no new variable, no operator-minted default (`hr-tf-variable-no-operator-mint-default`: the value is generated, nothing is pasted). Sensitive-variable list: none added. `variables.tf` changes are one default and two descriptions.

### Apply path

(a) Per-merge saved plan: `apply-web-platform-infra.yml` applies automatically on merge to main through its hard `-target` list; the two new addresses are creates, the pool is not in the set, and the destroy-guard counters see zero deletes. Expected downtime: none. Blast radius: one new masked secret in Doppler `prd`. No host is replaced, no SSH provisioner runs, no `terraform_data` is touched. The merge is held until the owner names the exact merge command (see Operator Holds); the merge event itself triggers the infra workflow, which writes the Doppler secret.

### Host fan-out

No `terraform_data` SSH provisioner is added or edited. The release that fires on merge fans out to web-1 and web-2 through the existing deploy chain with unchanged app bits; nothing in this PR is host-specific.

### Distinctness / drift safeguards

`dev != prd` (`hr-dev-prd-distinct-supabase-projects`): the secret is created in `prd` only, like `PROXY_TLS_KEY`/`CERT`; nothing is written to `dev`, and PR A's tests use synthesized fixtures. No `lifecycle.ignore_changes` (the value is stable in state); no `prevent_destroy` (it would block a `host_proxy_tls_enabled = false` teardown). Terraform state in R2 will hold the key value (state holds sensitive values); see Encryption Posture. Drift: the web-2 weight drift disappears by construction (default equals live).

### Vendor-tier reality check

Doppler and the random provider have no tier gate on these resources. The Cloudflare Load Balancing add-on is already billed and untouched.

## Architecture Decision (ADR/C4)

### ADR

Add a dated `## Addendum — 2026-11-08 (#12363)` at the end of ADR-068 via `soleur:architecture` (task 1.8). No new ADR: the decision (default 1, explicit drain) refines an existing ADR rather than creating a new substrate or boundary; the hello-signing design itself is PR A's ADR, not this PR's.

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were read in full by an independent pass (model.c4 in chunks). Findings: `views.c4` and `spec.c4` contain nothing about web-2, weight, Doppler or the relay. External human actors: none added (no new sender or recipient). External systems and vendors: none new (Doppler `prd` secrets delivery is already modeled by `doppler -> hetzner`; Terraform-owned `prd` secrets already have precedent at `GIT_DATA_SSH_HOST_KEY`, `INNGEST_REDIS_LUKS_KEY` and `registry_luks_key`; the "mints NOTHING" statement at L814 is scoped to the `soleur-infra-privileged` project, not `soleur/prd`, so it is not contradicted). Containers and data-stores: no new store. Actor-to-surface access relationships: unchanged. The relay itself is not modeled as an edge, and no description enumerates `soleur/prd` secrets exhaustively ("about 116" at L795/L954 stays true at +1). Falsified descriptions this change must fix: the `cloudflare` L448 weight-0 phrase (task 1.9); the remaining weight-0 statements (`hetzner` L351, `workspacesVolume` L355, `betterstack -> hetzner` L926) pre-date this change and are tracked in follow-up (c). Derived cardinalities: `plugins/soleur/test/c4-count-parity.test.sh` gates workflow, cron-monitor and Resend-emitter counts, none of which a `doppler_secret`, a `random_bytes` or an extra `-target` line can move (a `terraform_data` SSH provisioner would, and none is added); it is run green before and after (Phases 0.2 and 3.1). `model.likec4.json` is regenerated with `scripts/regenerate-c4-model.sh` (c4-model-freshness gate).

### Sequencing

Target state only; nothing is gated on a later slice. PR A will extend the model if it adds a relay hello edge.

## Encryption Posture

No new persistent store and no new network connection. The one new datum lands in two already-ledgered stores:

```yaml
at_rest:
  - store: doppler.secrets (scripts/encryption-posture-ledger.json)
    mechanism: provider-managed:doppler-aes256-gcm
    evidence: ledger row doppler.secrets; attestation https://www.doppler.com/security retrieved 2026-07-24
    defends_against: physical-media compromise of Doppler's secret storage
    does_not_defend: a leaked Doppler token or a compromised host holding a live token reads PROXY_HELLO_HMAC_KEY in clear, and so does each of the sixteen read-only Doppler tokens documented in token-drift-read-tokens.tf that read the whole prd root; masking hides the value from display and logs, it does not encrypt it from authorized readers
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:named SOC 2 attestation formalization pending; tracked #6911
  - store: r2.terraform_state_backend (ledger row)
    mechanism: provider-managed:Cloudflare-R2-SOC2-Type-II
    evidence: ledger row r2.terraform_state_backend; Cloudflare Trust Hub SOC 2 Type II, retrieved 2026-07-24
    defends_against: physical-media compromise of the Terraform state store
    does_not_defend: a leaked R2 token reads the state object, which contains the key value (state holds sensitive-marked values); Terraform state is not a secrets vault
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:inherits the ledger row
in_transit:
  - connection: Doppler delivery of the secret to the host at container start (existing channel; PROXY_TLS_KEY precedent); no new connection is created by this PR
    tls: existing authenticated TLS to Doppler
    cert_verification: on
    does_not_defend: a host compromise after the secret is in the container environment
    disclosed_as: not-publicly-claimed
```

`python3 scripts/lint-encryption-posture.py` is run before and after (PASS expected; its secret-pair check applies only to ledger volume rows). No `exception` block: nothing is plaintext or unverified.

## Observability

```yaml
liveness_signal:
  what: the twice-daily terraform drift plan for apps/web-platform/infra reports exit 0 (no web-2 weight diff, no hello-key diff) once the merge's apply has landed
  cadence: 06:00 and 18:00 UTC, dispatched by the Inngest cron cron-terraform-drift
  alert_target: scheduled-terraform-drift.yml files a drift issue and emails on exit 2; a dead dispatch is covered by the existing cron monitor
  configured_in: .github/workflows/scheduled-terraform-drift.yml and apps/web-platform/server/inngest/functions/cron-terraform-drift.ts
error_reporting:
  destination: the apply workflow run log and its failure notification (the per-merge job fails loud on plan or apply error); grader refusals print ::error:: lines and exit 1 before anything is applied
  fail_loud: true
failure_modes:
  - mode: default left at 0 or flipped back by a stale branch
    detection: scheduled drift plan proposes web-2 1 -> 0; C.4-V2 fails in infra-validation
    alert_route: drift issue + CI red
  - mode: serve grader admits a pool it did not grade
    detection: the pn3/pn4/pn5 refusals in test-cf-lb-overlay-gate.sh
    alert_route: CI red on the PR
  - mode: hello secret absent or malformed after merge
    detection: apply run log "Creation complete" for both addresses; count-only prd read prints 1 (Phase 4.3)
    alert_route: failed apply run notification; postmerge fails the verification
  - mode: key value printed in a plan comment or log
    detection: tf_redact_random_ids fixtures for random_bytes.proxy_hello_hmac[0]; the key-material redaction census in the parity test
    alert_route: CI red on the PR
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml and scheduled-terraform-drift.yml (redacted by tf_redact_random_ids)
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: grep -A3 'variable "web2_lb_weight"' apps/web-platform/infra/variables.tf | grep -cE 'default +[=] +1$'
  expected_output: "1"
```

The probe is instant and prints the persisted-default property itself (it prints `0` on today's tree, `1` once the flip lands; the drift-clean and secret-present properties can only be observed after merge and are covered by Phase 4.3, because a pre-merge read of the live drift run would see the pre-merge state). The serve and drain grading is covered by the suites, not by this probe: a suite is the wrong command to discover a signal (preflight Check 10 caps a probe at 15 seconds; the gate suite measured about 5 seconds and the infra suite about 27, so neither is declared here).

## Guard Contract

### Guard 1 — serve-mode pool grading (wrapper over `cf_lb_gate_ga_pool_update`)

**Property.** A `serve` plan is admitted only if it contains the web_1 pool as an `update` or `no-op` entry whose after-state is {web-1:1, web-2:1} by resolved IP with no disabled, duplicate, mis-bound or foreign origin, and a `drain` plan is never admitted on a no-op pool alone.

**Assembly.** The grading logic (about 17 pool selectors in one inner function) is not edited. The assembly is the wrapper, which is the single chokepoint through which every caller reaches the inner grader: the only call site is the `Plan gate` step of `ga_pool_update` in `cf-lb-overlay.yml`, and the inner function is no longer called directly by anything (a census row asserts the workflow and the test suite call the public name only, so a later caller cannot bypass the serve normalization or its pool-absent refusal). The normalization touches exactly one entry kind: the entry whose address is `cloudflare_load_balancer_pool.web_1` and whose actions are exactly `["no-op"]`. The other arm graders (`cf_lb_gate_ga`, `cf_lb_gate_ga_monitor_update`) are separate functions and stay create/update-only.

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Expected RED | Why this row exists |
|---|---|---|---|
| 1 | In a sandbox copy of the lib, remove the serve normalization (wrapper passes the plan through) | pn1 and pn2 (must-pass shapes) go red | proves the no-op admission is the new code |
| 2 | Normalize in drain mode too | pn7 (drain + lone no-op pool) goes red | the guard's own mode scoping |
| 3 | Normalize EVERY no-op entry instead of only the pool | pn1 goes red (the hcloud no-ops become updates and trip the allow-set) | a normalization wider than the property |
| 4 | Delete the wrapper's pool-absent refusal | pn5 goes red on its message assertion (the bare rc stays 1 through the inner function's other refusals, which is why the message is asserted) | precondition satisfied (other entries exist) yet the property fails |
| 5 | Wrapper skips the inner grader for serve no-op plans (admits on the notice alone) | pn3 and pn4 go red | the old vacuous pass, reintroduced |
| 6 | Wrapper leaks the normalized copy (drop the `rm -f`) | pn8 and pn9 go red | cleanup on the success and failure paths |
| 7 | Dispatch default arm falls through to the inner function on the original file (or an empty probe result is treated as an update) | pn3 goes red | the empty-probe path that would reintroduce the vacuous pass |
| 8 | Drop the exact-entry predicate (`previous_address` / `importing` / `deposed` / single entry) | pn10 goes red | normalization wider than the property |

**Harness rows.** (H1) Delete one pn fixture: the exact `checks` floor goes red. Must-PASS that is not the canonical: pn1 (everything no-op) and pn2 differ from the canonical pu8 (0-to-1 update), in ways the contract explicitly permits. The pristine control runs first and must be green; each mutation asserts it LANDED (`cmp` against pristine) before asserting RED.

**Anchor.** The floor lives in the suite, so one diff can edit both; the independent anchors are the merge-base diff read by `soleur:review` and `scripts/guard-vacuity-floor.test.sh`, which derives its population from floor shape rather than a list. The pn1-pn8 labels are unique in the file (the `pu` series already runs to pu36), which keeps by-name presence checks meaningful.

### Guard 2 — the ga_overlay arm states web-2's weight explicitly

**Property.** In `cf-lb-overlay.yml`, exactly two plan steps pass `web2_lb_weight` (ga_pool_update from the mode-derived pin, ga_overlay as the literal 0), and no other workflow names it.

**Assembly.** Every `terraform plan` that targets or can reach the pool: the `ga_overlay` and `ga_pool_update` jobs, the monitor arms (pool not reached), the three staging arms (own root), the per-merge apply (hard target list), the drift workflow and the infra-validation plan job (full root; `-var`-free by design), plus any future job. Chokepoints, all existing except F8: C.4-F6 (the file-wide non-comment line count must be exactly two), C.4-F5 (the ga_pool_update step), the new F8 (the ga_overlay step, via its own `GAO_JOB`/`GAO_PLAN` extractor), and C.4-F1/F7 (repo-wide feeder files and other workflows).

**Mutation matrix.**

| # | Edit | Expected RED |
|---|------|--------------|
| 1 | ga_overlay `-var="web2_lb_weight=1"` | F8 |
| 2 | ga_overlay `-var` line deleted | F8 and F6 (count drops to one) |
| 3 | ga_overlay value becomes `${WEB2_LB_WEIGHT}` | F8 only (F2 excludes this file by design) |
| 4 | A third non-comment line naming the variable appears in the file | F6 |
| 5 | `scheduled-terraform-drift.yml` gains `-var=web2_lb_weight=...` | F7 |

**Harness rows.** Rows 1 and 2 are in-suite mutants on a `mktemp` copy (LANDED asserted, pristine control first); rows 3-5 are exercised once in the sandbox run. Must-PASS non-canonical: a comment-only edit to the `ga_overlay` step leaves F8 green.

**Anchor.** `MIN_CASES` is the suite's own count; the independent anchor is the repo-wide feeder census (F1), which fails if any new file names the variable.

### Guard 3 — the hello-key pair is count-gated, targeted together, never exposed

**Property.** `random_bytes.proxy_hello_hmac` and `doppler_secret.proxy_hello_hmac_key` exist only behind `var.host_proxy_tls_enabled`, are applied only by the per-merge saved plan, and the key value reaches no output.

**Assembly.** `apps/web-platform/infra/*.tf` (all files via `listInfraTfFiles`), the per-merge saved plan's `-target` set (`planTargets`), the dispatch jobs `web_host_create` and `web_host_replace`, and `OPERATOR_APPLIED_EXCLUSIONS`. Second-member rule: adding a third hello-related resource later reds the generic "every resource targeted or excluded" census; the pair test names exactly two.

**Mutation matrix.**

| # | Edit | Expected RED |
|---|------|--------------|
| 1 | Remove `-target=doppler_secret.proxy_hello_hmac_key` | T2 |
| 2 | Remove `-target=random_bytes.proxy_hello_hmac` | T2 |
| 3 | Drop `count` from either resource | T1 |
| 4 | Add either address to a dispatch job's `-target` | T2 |
| 5 | `visibility = "unmasked"`, or `length = 16`, or an `output` exposing the value | T3 |

**Harness rows.** T4 runs rows 1 and 3 as string-copy mutations of the pristine text (LANDED asserted, control first); rows 2, 4 and 5 run once in the sandbox. Must-PASS non-canonical: a reordered but equivalent resource block (attribute order swapped, a comment added) must stay green.

**Anchor.** The `-target` literals live in the workflow (source of truth) and the pair names in the test; a weakening needs both files edited; the independent anchor is the `infra-validation` plan comment showing the two additions (+2 relative to the base branch) and no pool block.

## Acceptance Criteria

### Pre-merge (verifiable on the PR)

- [ ] AC-1. `variables.tf` `web2_lb_weight` has `type = number`, `default = 1`, and the unchanged validation admitting only 0 or 1; `cloudflare-lb.tf` still has `weight = var.web2_lb_weight` on the web-2 origin and the literal `weight = 1` on web-1.
- [ ] AC-2. `cf_lb_gate_ga_pool_update` serve mode admits a pool `no-op` or `update` entry graded on {1,1} (pn1, pn2), refuses serve with the pool absent (pn5, distinct message), replaced (pn6) or graded wrongly on the no-op path (pn3, pn4); keeps drain update-only with its empty-set refusal (pn7) and remnant branch (pu15); no normalized copy leaks (pn8); the pre-existing vacuous serve admission (pool no-op at web-2 weight 0) now refuses (pn3).
- [ ] AC-3. `ga_pool_update` still passes `-var="web2_lb_weight=${WEB2_LB_WEIGHT}"` exactly once (drain explicit 0, serve 1); `ga_overlay` passes `-var="web2_lb_weight=0"` exactly once; no other job or workflow names the variable; the drift and PR-plan workflows stay `-var`-free.
- [ ] AC-4. The Phase 1.4 sweep output (`grep -rnIiE 'weight[ -]?0|default[ -]?0|drained'` over the four files) is in the work log with every remaining hit either a true statement about drain as an explicit act or the named `cloudflare-lb.tf` L160 attribute exception; the runbook "After the serve" section states default 1, clean drift, explicit drain, rollback lever and the inverted full-root hazard; runbook L424 corrected; the ADR-068 addendum exists; the `cloudflare` C4 phrase is corrected and `model.likec4.json` regenerated.
- [ ] AC-5. `proxy-hello-hmac.tf` exists with exactly the two count-gated resources; `random_bytes` length 32; secret `PROXY_HELLO_HMAC_KEY` in `soleur`/`prd`, masked, value `random_bytes.proxy_hello_hmac[0].hex`; the locked-provider schema check shows `hex` sensitive.
- [ ] AC-6. `apply-web-platform-infra.yml` carries `-target=random_bytes.proxy_hello_hmac` and `-target=doppler_secret.proxy_hello_hmac_key` directly after `proxy_tls_cert`, nothing else changed in that file, and its size is under 490,000 bytes.
- [ ] AC-7. Parity tests T1-T4 and the redactor fixture pass; each floor (`checks` in `test-cf-lb-overlay-gate.sh`, `MIN_CASES`, `TEST_FLOOR`, the redactor suite's floor) equals its measured post-change value exactly (derivation table below).
- [ ] AC-8. Every Guard Contract mutation row was run on a sandbox copy, control green first, mutation LANDED, RED for the named reason; evidence is in the work log.
- [ ] AC-9. Every pre-push gate in Phase 3.2 is clean; `regenerate-shard-manifest.py --incremental --write` produces no tsv diff; the kb-consumers baseline file is unchanged.
- [ ] AC-10. No file under `apps/web-platform/server` (or any application path) is touched: `git diff --name-only origin/main...HEAD` lists none; no other session's PR, #12330, #11694, #11676, #11669 or #10476 artifact is edited.
- [ ] AC-11. PR body: `Closes #12363` only; `Ref` for #12288/#12289/#12290; release-arm finding and revert rule stated; follow-up issues (4.2) created and linked.
- [ ] AC-12. The `infra-validation` plan comment contains the two `will be created` blocks for the new addresses, an add count exactly +2 against the base branch's same plan, and no `cloudflare_load_balancer_pool.web_1` block (relative check; the full-root plan carries unrelated diffs).
- [ ] AC-13. `decision-challenges.md` rows pass `technical-ruling-gate.sh --branch`.

### Post-merge (read-only, by `soleur:postmerge`)

- [ ] AC-15. (pre-merge, read-only) Phase 3.8 holds: the first drift run after the serve flip lists no pool change, and `WEB2_LB_WEIGHT` is absent from `prd_terraform`.
- [ ] AC-14. The apply run on the merge commit succeeded and shows `Creation complete` for `random_bytes.proxy_hello_hmac[0]` and `doppler_secret.proxy_hello_hmac_key[0]`; the next scheduled drift run after the apply logs `No drift detected in web-platform` on the `apps/web-platform/infra` leg with no `-var`; the count-only prd read prints `1`.

### Floor derivation (set to the measured value, never a guessed one)

| Floor | Where | Baseline (measured 2026-11-08) | Planned additions | Expected exact value | Derive with |
|---|---|---|---|---|---|
| `checks -lt N` | `tests/scripts/test-cf-lb-overlay-gate.sh` | 110 assertions, floor 98 (12 loose) | pn1 (2), pn2, pn3, pn4, pn5 (2), pn6, pn7, pn8 (2), pn9 (2), pn10 = 14 | 124 | run the suite, read `ALL TESTS PASSED (N assertions)` |
| `MIN_CASES` | `apps/web-platform/infra/lb-weight-gate.test.sh` | 282 passed, `MIN_CASES=282` | F8 (1) + two F8 mutants (1 each) = 3 net new (V2 and F6 are edits, count unchanged) | 285 | run the suite, read `=== Results: N passed` |
| `TEST_FLOOR` | `plugins/soleur/test/terraform-target-parity.test.ts` | 372 `test(` lines, floor 367 (5 loose) | T1-T4 = 4 | 376 | `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts` |
| redactor floor | `tests/scripts/test-tf-redact-random-ids.sh` | `MIN_ASSERTIONS` 327, measured 327 | the one `random_bytes.proxy_hello_hmac[0]` fixture (rows counted when written) | 327 + rows added | run the suite |

The "expected" column is a cross-check (baseline plus the enumerated additions), not the source of the number: the floor is the value the suite prints at commit time. If they differ, re-derive, note the correction in the work log, and set the floor to the measured value. Each mutant counts as one assertion only when it is written as one `c4_ok`/`c4_bad` call (the `wmut` helper style); a loop that reports once changes the arithmetic.

## Test Scenarios

- Gate: serve + everything-no-op {1,1} (pn1) and no-op with a policy create (pn2); serve + 0-to-1 update (existing pu8); serve + no-op at {1,0} (pn3); serve + web-1 at weight 0 on the no-op path (pn4); serve + pool absent (pn5); serve + replace verb (pn6); drain + lone no-op (pn7); drain remnant (pu15); no leaked temp copy (pn8).
- Census and mutation: Guards 1-3 matrices above.
- Redaction: the count-indexed `random_bytes` plan block never prints a value-like token.
- Integration (read-only, local): `terraform validate`, `fmt -check`, YAML parse of both workflows, the workflow-size gate, the destroy-guard counter suite.

## Sharp Edges

- The release push arm fires on this PR (accepted, ruling 7). The deploy restarts containers on both hosts; a container reads Doppler at start, so no running container sees the new secret until PR A's release deploys. Nothing is lost by that, and PR A must treat the secret's presence as a recorded precondition.
- `ga-pool-update mode=serve` against live {1,1} now passes the grader and applies a no-op plan; the §(c) gate chain, health precondition and relay bind probe still run first and can still refuse. "Serve admitted a no-op" is not "web-2 is proven healthy".
- After an INTENTIONAL drain, every full-root plan proposes `0 -> 1`; that is the intended loud signal, and the rollback lever is documented in the runbook (drain, then a PR returning the default to 0 if the drain is meant to persist).
- A `random_bytes` attribute read is only correct against the locked provider (3.9.0). A provider bump must re-run the schema check in Phase 2.2.
- `TEST_FLOOR` and `apply-web-platform-infra.yml` are hot spots shared with #12379, #12404, #10678 and #7390: re-derive the floor and re-measure bytes after any rebase, and never resolve a conflict in the `-target` list by dropping a sibling's lines.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled.
- Merge before 2026-11-12 or the two in-transit exceptions (#10538, #10479) will redden every PR on that date (unrelated, but it would block this merge).
- The brief said to keep the literal word-pair for terraform's apply subcommand and flag-tooling names out of Bash text: commands in this plan avoid them, and the work phase must too.

## Operator Holds

- Hold: Operator-reserved: <owner names the exact merge command for this PR>
