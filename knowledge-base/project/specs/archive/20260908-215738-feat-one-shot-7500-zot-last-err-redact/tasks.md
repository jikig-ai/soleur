---
title: "Tasks — zot_last_err redaction decision (#7500)"
branch: feat-one-shot-7500-zot-last-err-redact
issue: 7500
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-08-arch-zot-last-err-redact-decision-plan.md
---

# Tasks

Derived from the plan's Implementation Phases. Phase A ships with immediate effect; Phase B is
inert until the next registry host replace; Phase C is the record.

## 1. Setup and preconditions

- [ ] 1.1 Re-read the plan's `## Research Insights`. Do **not** re-derive the measurements — they are
      recorded with the commands that produced them.
- [ ] 1.2 Re-run the baseline so the before/after is this session's:
      `bash apps/web-platform/infra/registry-userdata-budget.sh --json` (expect `stored_bytes` ≈ 13,692).
- [ ] 1.3 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` (expect 10 passed, 0 failed).
- [ ] 1.4 Confirm `zot_last_err_src` still has zero runtime consumers before widening its enum
      (`hr-type-widening-cross-consumer-grep`).

## 2. Phase A — the public egress (RED first)

- [ ] 2.1 Write `scripts/zot-restart-loop-alarm-scrub.test.sh` from Guard 2's mutation matrix (6 rows
      RED, 3 must-PASS including the post-Phase-B idempotency row). Assert at the
      **`emit_and_exit()` chokepoint**, never at the single `last_err=` site.
- [ ] 2.2 Register it with a `run_suite` line in `scripts/test-all.sh` — `scripts/*.test.sh` is NOT in
      `SUITE_GLOBS`. Then `bash scripts/lint-orphan-test-suites.sh` must still report
      `orphan test suites: none` (baseline 410 covered / 0 orphaned).
- [ ] 2.3 Implement the scrub at `emit_and_exit()`: credential-header masking, a length bound, a
      conservative character class. **No `clientIP` masking** — cut, owned by #7530.
- [ ] 2.4 Mirror the assertion at the workflow publication boundary (AP-025). **No markdown fencing** —
      cut to the capability-gap issue (different threat, unguarded here).
- [ ] 2.5 Render `zot_last_err_src` **interpolated into `CAUSE`** (the workflow parses only
      `^ZOT_ALARM_CAUSE=`), derived from the **same row** as the tail. Stop presenting a `fallback`
      sample — or a `REDACTION_FAILED` placeholder — as a cause.
- [ ] 2.6 Fix the comment in `scripts/zot-restart-loop-alarm.sh` that reads "surface the redacted log
      tail" so it describes what the code now does (step 2.3 makes it accurate).
- [ ] 2.7 Update `scripts/zot-restart-loop-alarm.test.sh` — it exists, asserts on `CAUSE` text, and its
      fixtures omit `zot_last_err_src=`. Decide and RECORD the legacy-row rule for an absent tier tag.

## 3. Phase B — the producer (RED first)

- [ ] 3.1 Write `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` from Guard 1's mutation
      matrix. **No behavioural suite for the heartbeat exists** — build it on the
      `zot-log-shipper.test.sh` template: extract from the template, apply
      `local.registry_rationale_strip`, assert the stripped result is still valid bash, execute against
      synthesized PATH stubs (`docker`, `curl`, `htpasswd`, `df`, `hostname`, `date`), results-file
      tally, harness canary, assertion floor.
- [ ] 3.2 Register it as an explicit `run: bash …` step in `.github/workflows/infra-validation.yml`
      (the runner greps the WORKFLOW; `git ls-files` is only the orphan detector).
- [ ] 3.3 Duplicate `CRED_HDRS` / `HDR_KEEP` / `redact()` into `zot-disk-heartbeat.sh`.
      **Do not extract to a shared sourced file** — see the plan's coupling argument.
- [ ] 3.4 Call `redact()` **PER LINE** of `ZOT_ERR_RAW`, **before** the sanitizer. Both halves are
      load-bearing and both were measured: applied to the whole multi-line blob, `redact()` takes the
      non-JSON denylist branch and an unanticipated header (`X-Secret`) leaks in the clear at RC=0;
      applied post-sanitizer, the quotes are gone and the JSON branch can never fire.
- [ ] 3.5 Wrap the call as a SINGLE `|| { degrade }` branch so all three RC=1 paths funnel through one
      handler by construction. Set `zot_last_err=REDACTION_FAILED` (no `=`, no spaces) and the
      companion token `zot_last_err_src=<tier>:redact_failed` — do not overload the tier enum.
      Keep the wrapper **outside** the shared function body so the two `redact()` bodies stay
      byte-comparable.
- [ ] 3.6 Add the tier gate FIRST in the chain (before `redact()`, before the sanitizer): when
      `ZOT_ERR_SRC=fallback`, emit the parsed `message` only. **Degrade CLOSED without `jq`** (emit
      `none`, never the raw line). Do **not** implement it by blanking `ZOT_ERR_RAW` — the existing
      `[ -n … ] || { …; ZOT_ERR_SRC=none; }` would reset the tier tag Phase A renders.
- [ ] 3.7 Add the drift check (NOT byte-equality — it would force `[zot-log-shipper]`-tagged dead
      code into the heartbeat): `def scrub: with_entries` appears exactly 2× in the rendered,
      strip-applied template; `CRED_HDRS` and `HDR_KEEP` each 2× and byte-identical; the heartbeat
      side has a per-line loop.
- [ ] 3.8 Extend `apps/web-platform/infra/registry-boot-guard.test.sh` for the new
      `zot_last_err_src` value.
- [ ] 3.9 Re-run `registry-userdata-budget.sh --json`; record before/after. Must stay
      **< 20,000 B** (`REGISTRY_GZIP_BUDGET`).

## 4. Phase C — the record

- [ ] 4.1 **Mint ADR-211** (re-probe the ordinal against all `origin/*` refs immediately before
      merge). `redact()` appears in ZERO ADRs — verified — so amending ADR-184's "decision about
      redact()" would amend a decision it never recorded. Set `status: adopting`.
- [ ] 4.1b Amend `ADR-184` with ONLY: a new Alternatives row for the redaction question, plus a
      one-line `## Decision` pointer scoping its §3 sanitizer to the shipper. Leave the existing
      "Widen the reporter's `zot_last_err` field" row byte-unchanged.
- [ ] 4.2 `model.c4`: amend the two edge descriptions (`zotRegistry -> betterstack`,
      `github -> betterstack`) AND add the missing egress relationship — a `#external` `publicReader`
      actor plus `github -> publicReader`, with the `views.c4` include lines so it renders. Re-run the
      C4 count-parity gate (adding a relationship is a larger parity risk than a description edit).
- [ ] 4.2b Every Phase-C artifact carries BOTH the scope limit (headers object / JSON branch / per
      line / NOT clientIP / sink layer is a denylist) AND a delivery-state qualifier for the producer
      half. This is AC12 and nothing else gates it.
- [ ] 4.3 Art. 30 register: new dated brackets on PA-8 §(g), §(c), **and** the Better Stack Vendor
      Mapping row (which also names #7500). **Additive only** — quote superseded text, never edit it.
      Route the final cell list through the CLO attestation.
- [ ] 4.4 Write the Phase 5.5 CLO attestation under `knowledge-base/legal/audits/`.
- [ ] 4.5 File the capability-gap issue: no gate covers runtime publication of third-party or system
      output to a public artifact by agent-authored automation. Cross-reference #7844 (same class)
      and #7331.
- [ ] 4.6 Enrol the soak follow-through: `scripts/followthroughs/zot-last-err-redact-7500.sh`, the
      tracker directive, and the `follow-through` label.

## 5. Verification

- [ ] 5.1 Work through the plan's `### Pre-merge (PR)` acceptance criteria 1–14 in order, recording
      the measured output of each.
- [ ] 5.2 Confirm no `breach-register.md` row was added (AC12) — the measured fact pattern found no
      credential and no personal data.
- [ ] 5.3 State in the PR body, in these words, that **Phase B is INERT until the next
      `registry-host-replace`**.
- [ ] 5.4 Use `Closes #7500` in the PR body.
