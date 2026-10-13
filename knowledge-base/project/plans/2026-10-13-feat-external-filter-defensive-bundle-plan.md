---
title: "External-tool output-filter defensive bundle — rtk guard unwrap + detection markers + docs + evidence-gated posture"
type: fix
date: 2026-10-13
slug: feat-external-filter-defensive-bundle
branch: feat-fcc-token-optimizations
issue: 10230
closes: 10230
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# External-tool output-filter defensive bundle (#10230)

## Overview

Close the `rtk` command-wrapper bypass across Soleur's unwrap sites, make
external output filters (RTK, Headroom) visible at session start via
`SOLEUR_EXT_FILTER` markers, rebuild the gate-literal divergence harness and
measure RTK's filters before docs claim compatibility, and ship the support
attribution surface (canonical doc + bug-report fields + `external-env` label).
**No adoption** of FCC/RTK/Headroom — this is defense and honest documentation
for users who install these tools independently.

## Problem Statement / Motivation

Third-party output filters sit between Soleur's verbatim-string machinery and
the model. Two defects exist for users regardless of our posture:

1. **Guard bypass (security surface).** `rtk` is not in
   `destructive-command-guard.sh`'s wrapper table ("wrappers outside the table"
   is a stated NOT-DECIDED). A literal `rtk rm -rf ~` / `rtk git push --force` /
   `rtk run rm -rf ~` is judged on argv[0]=`rtk` and allowed — and RTK's own
   docs instruct agents to type `rtk`-prefixed commands in "full" mode. The same
   unwrap-table gap exists in `pkill-self-match-guard.sh` and `proc.sh`.
2. **Attribution gap (support surface).** No troubleshooting surface for plugin
   users exists (README §"Known Issues" is the only one), `bug_report.yml`
   captures no external-tool environment, and nothing detects a filter at
   session start — so "skill X broke" reports cannot be separated into "Soleur
   defect" vs "filter ate the evidence."

## Proposed Solution

- **Phase 1 — Unwrap fixes.** `rtk` joins the guard's wrapper machinery
  (`wrap_skip` arm + `fold_name` + `decide_walk` alternation + `redact_word` +
  `long_word_judged` + header prose), plus sibling unwrap tables
  (`pkill-self-match-guard.sh` PFX/`stage_word`, `proc.sh` `_PROC_WRAPPERS`).
  Verified RTK grammar (README, 2026-10-13): exec subcommands are
  `run|err|test|proxy|bypass|summary` (positional argv — consume the word, unwrap
  the inner command); `rtk run -c '<script>'` / `rtk err --shell <name>
  '<script>'` carry shell-string payloads → `unparsed-wrapper` ask (mirrors
  `env -S`); `gain|session|discover|init|telemetry` are non-exec (no unwrap);
  bare `rtk <cmd>` unwraps directly; `rtk -- <cmd>` is already covered by the
  `--` retry; bare `rtk run` is a graceful must-allow. Inner `rtk` unwraps
  free via `decide_walk` recursion — nested rows (`sudo rtk rm`, `rtk env
  rm`) pin it. Sibling tables get the same subcommand consumption, not just
  the list entry. Test-side: `STUB_NAMES` + python oracle (both `unwrap()`
  AND the `decide` dispatch tuple) + rows + `MIN_CASES` bump + README
  pinned-sentence sync.
- **Phase 2 — Detection.** New `plugins/soleur/hooks/ext-filter-detect.sh`
  SessionStart hook on `startup|resume|clear|compact` emitting
  `SOLEUR_EXT_FILTER tool=<name> version=<v> posture=<tier>` via
  `systemMessage` (operator-facing; model-facing `additionalContext` is a
  documented alternative, rejected for token cost). Posture lives in ONE
  committed constants line in the hook — three values: `unmeasured` (RTK
  default until Phase 3 evidence lands — the marker never asserts an
  unmeasured claim; the issue's "two severity tiers" maps as
  `literal-clean`/`measured-incompatible` plus this honest pre-evidence
  state, explicitly not an assurance), `literal-clean` (RTK only after the
  Phase 3 gate passes — asserts gate-literal survival on the corpus, NOT
  behavioral compatibility), `measured-incompatible` (Headroom). Clean
  detection emits
  `SOLEUR_EXT_FILTER tool=none` so "hook dead" is distinguishable from "no
  filter". Kill switch `SOLEUR_DISABLE_EXT_FILTER_DETECT=1`, fail-open,
  `devin-dispositions.tsv` row.
- **Phase 3 — Evidence gate.** `plugins/soleur/scripts/ext-filter-divergence.sh`
  plus committed corpus: run each corpus command verbatim vs `rtk`-filtered, diff
  the gate-literal set (see FR3 literal set). The control arm (deliberately
  lossy `head -3`) runs UNCONDITIONALLY — only the `rtk` arm skips when
  `command -v rtk` fails; a control arm reporting zero divergence exits
  non-zero with `INSTRUMENT-DEFECT` (a dead instrument must never satisfy the
  gate). Passing requires conjunctively: RTK-arm gate-literal divergence == 0
  AND control-arm divergence > 0. On pass, the same PR flips the hook's
  posture constant `unmeasured`→`literal-clean` and the doc's RTK
  claim lands; on any failure path, both stay at the honest tier.
- **Phase 4 — Support surface.** `docs/pages/known-external-tools.md` (canonical
  posture + three-rung diagnostic + footguns), README "Known Issues" third
  entry, `bug_report.yml` external-filter fields, `external-env` label.

## Technical Considerations

- **Attack Surface Enumeration (security fix).** Every argv[0]-anchored unwrap
  site is a potential `rtk <cmd>` evasion path:
  - `plugins/soleur/hooks/destructive-command-guard.sh` — covered by this plan.
  - `.claude/hooks/pkill-self-match-guard.sh` (`PFX` regex :224, `stage_word`
    case :344) — covered; `rtk pkill -f` is already denied (substring gate
    position-independent); the gap is the read-only self-match arm
    (`rtk ps aux | grep pat`).
  - `plugins/soleur/scripts/lib/proc.sh` (`_PROC_WRAPPERS` :75) — covered;
    fail-closed direction (blind spot, not wrongful kill).
  - **Boundary-anchored gates (NOT covered — deferral filed):** ~12 gates match
    `gh`/`git` at command boundaries (`pre-merge-rebase.sh:121,127` — the
    `gh pr merge` review-evidence gate is highest-severity — plus
    `pre-merge-auto-close-scan`, `ship-unpushed-commits-gate`,
    `ship-soak-followthrough-gate`, `ship-net-issue-flow-gate`,
    `ship-operator-step-gate`, `ship-runbook-ssh-gate`,
    `cla-signed-author-gate`, `prod-write-defer-gate`,
    `follow-through-directive-gate`, `guardrails.sh`×3). Same exposure shape
    (direct `rtk`-typed commands only — auto-rewritten input is judged on the
    original per ADR-264) but a different fix mechanism
    (`(prefix)*`-tolerant boundary) and a different review profile → own issue,
    `deferred-scope-out`.
  - Already-safe sites (position-independent or fail-closed):
    `filing-shape.pl` (scans any argv index), `browser-snapshot-credential-guard`,
    `doppler-secrets-delete-redirect`, `git-commit-secret-scan`,
    `grep-rewrite.sh`, `operator-stage-approval.sh` (fails closed to deny).
- **Hook composition.** A user-installed RTK PreToolUse rewriter is a third
  `updatedInput` emitter the two-rewriter allowlist (ADR-264) cannot see — it
  lives in user settings, not this repo. Auto-rewrites are safe by ADR-162
  clause 6 (gates judge original input); the detection marker documents
  co-firing rather than preventing it.
- **Detection surface choice.** `version-banner.sh` is `startup`-only;
  `compaction-state.sh` carries `startup|resume|clear|compact` but a different
  job. New dedicated hook mirrors `codex-session-start.sh`'s registration
  shape. Marker survives compaction boundaries — the failure it explains
  post-dates context loss.
- **FR3 corpus shape.** Prior eval's transcript corpus was never committable
  (operator paths); RTK's filters are per-command, so the corpus is a command
  list replayed verbatim-vs-`rtk` — committable this time, no transcript
  privacy issue. Reuses the prior literal set + Bash-shaped additions.
- **NFR:** none affected (no server/infra paths; hook hot-path inherits the
  fail-open + bounded-runtime conventions of sibling hooks).

## Research Insights

- **Premise Validation (Phase 0.6):** all cited artifacts verified live —
  #10230 OPEN (created this session); #1055/#6297/#5692 OPEN (token
  instrumentation tracking — verified `gh issue view`, not inherited); archived
  `decided-no-build` spec + re-evaluation criteria exist
  (`knowledge-base/project/specs/archive/20261013-051752-feat-headroom-token-compression-eval/spec.md`);
  wrapper table gap confirmed (`wrap_skip` arms enumerate
  `sudo|doas|env|command|nohup|time|timeout|nice` — no `rtk`);
  `hooks.json` SessionStart matchers enumerated (version-banner is
  `startup`-only — informs the new-hook design); `bug_report.yml` +
  `docs/pages/` present; `external-env` label does not exist yet; `LICENSE`
  exists on `main` (leader claim refuted). **One fabrication caught:**
  `RTK_DISABLED=1` does not exist in RTK's docs — real disable is config
  `mode = "disabled"` / `enabled = false`, or `rtk run <cmd>` passthrough;
  docs must not repeat the invented env var.
- **Property List (Phase 0.6b):** P1 direct `rtk`-prefixed destructive commands
  get unwrapped verdicts (existing mechanism: wrapper table — extend, no new
  machinery); P2 filter presence attributable per session (existing: none —
  new marker); P3 compatibility claim measured not asserted (existing: none —
  rebuilt harness, mandated by operator-chosen Approach B); P4 user
  self-diagnosis of filter-vs-defect (existing: README Known Issues — extend
  plus new canonical doc + template fields).
- **Cut List:** the "opt-in RTK companion hook" (operator chose defensive
  bundle over adoption); extending `version-banner.sh` to the wide matcher
  (banner UX ≠ session-state detection — separate hook instead); aggregate
  filter-presence telemetry (CCO: flag-don't-build → deferred inside #10231).
- **Key file:line anchors:** guard `wrap_skip` arms 1055–1167,
  `fold_name` 1173–1184, `decide_walk` alternation 1222, `redact_word`
  allowlist 337, `long_word_judged` 526, header prose 46–57; `--` retry
  1240–1246 does NOT cover `rtk run` (no literal `--`); prefilter at 458
  already passes `rtk rm` (contains `rm`). Test: `STUB_NAMES` 226, python
  oracle `unwrap()` 539–587 + dispatch 601, `MIN_CASES` 2823, README-pinned
  sentence rows 93–102/1095–1162, rule-id roster `_RID_EXPECT` 1012 +
  `.claude/hooks/README.md` row 450. Hooks.json SessionStart 35–82; new hook
  needs `devin-dispositions.tsv` row (devin-matcher-parity rule 1).
  `docs/pages/` precedent: `goal-primitive.md` frontmatter shape.
- **Headroom §3b rebuild inputs:** literal set = `file.ext:line` citations,
  SHA/`#PR` refs, `SOLEUR_*` markers, `eval-gate:block` markers, `[id: …]`
  anchors + three grep-discharged gates
  (`hr-verify-repo-capability-claim-before-assert`,
  `hr-third-party-content-grep-on-undertaking`,
  `hr-type-widening-cross-consumer-grep`) + `extract-block.cjs` `indexOf`;
  scaffold `run_eval.py`/`divergence.py` was deleted — rebuild faithful via
  denominator (payloads/commands the gates parse) + literal set; instrument
  needs a **known-divergent control arm** (the "un-run instrument" class,
  learnings/2026-08-02).
- **Conventions to mirror:** kill switch `SOLEUR_DISABLE_<NAME>=1` first
  executable statement; fail-open `trap 'exit 0' EXIT`;
  `{"systemMessage": "…"}` envelope (zero model tokens) vs
  `hookSpecificOutput.additionalContext` (model-facing); `SOLEUR_HOOK_TRACE`
  seam; xtrace refusal only if the hook ever handles credentials (it won't).
- **CLI-verification (verified 2026-10-13, sources: RTK README main +
  `src/main.rs` via review agents):** `rtk session`, `rtk gain --history`,
  `rtk discover`, `rtk init --show`, `rtk run <cmd>`, `rtk proxy`,
  `rtk summary`, config `mode = "disabled"`, `RTK_TELEMETRY_DISABLED=1`,
  `-c`/`--command`, `--shell <name>`, `err|test|summary` string-join to
  `sh -c` upstream — all real. `RTK_DISABLED=1` — **not real**, do not
  cite. Residual: `rtk <sub> --help` per-subcommand flag tables at work
  time; RTK may also emit its own permission decisions in its PreToolUse
  hook (ordering vs Soleur's guard is a documented caveat, not a blocker —
  Soleur's gates judge the original input per ADR-264).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (file:line) | Plan response |
|---|---|---|
| "add `rtk` to the wrapper table" | Six coordinated sites: `wrap_skip` arm + `fold_name` + `decide_walk` alternation + `redact_word` + `long_word_judged` + header prose — plus test oracle/stub/MIN_CASES/README-pin | FR1 enumerates all sites; paper-resolution lint satisfied |
| bypass is "the guard" | Same unwrap-table gap in `pkill-self-match-guard.sh` + `proc.sh`; ~12 boundary-anchored gates share the class (different mechanism) | pkill/proc fold into Phase 1; boundary class → `deferred-scope-out` issue |
| "version-banner pattern" | version-banner is `startup`-only; spec wants `startup\|resume\|clear\|compact` | Dedicated `ext-filter-detect.sh`, not banner extension |
| `RTK_DISABLED=1` recall path | Does not exist | Docs cite `mode = "disabled"` + `rtk run` passthrough; re-verify RTK config docs at implementation |
| divergence = "the prior literal set" | Prior set was tool_result-shaped; RTK touches Bash output (porcelain, `gh --json`, test summaries, `pipeline-tally` verdicts, `SOLEUR_*` echoes) | Corpus = both sets (spec open question resolved: include Bash-shaped additions) |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies checked against
the `## Files to Edit`/`Create` list below; no matches. (Check re-run recorded
here after the file lists stabilized.)

## User-Brand Impact

- **If this lands broken, the user experiences:** a destructive command
  executes that the guard's stated coverage promised to intercept (`rtk rm
  -rf ~` allowed through), or a Soleur gate silently reads filtered output and
  the user cannot tell "Soleur is broken" from "a filter ate the evidence" —
  both land on Soleur's name, not the filter's.
- **If this leaks, the user's workflow is exposed via:** command strings
  (paths, branch names, flags) echoed into an unvetted third-party filter's
  processing path — the docs' Headroom-in-credential-path callout exists
  precisely so a BYOK user learns their key transits a third-party proxy
  *before* installing it.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one allowed `rtk rm -rf ~` or one
  filtered `pytest` tail shipping a regression is the incident this bundle
  prevents — carried forward from the brainstorm framing.

## Observability

The deliverable IS observability machinery; its own failure mode is a hook
that silently does not run (fail-open convention) — the marker's presence in
session output is the liveness signal.

```yaml
liveness_signal:
  what: "SOLEUR_EXT_FILTER marker emitted per session boundary (or its deliberate absence when no filter detected)"
  cadence: "per SessionStart (startup|resume|clear|compact)"
  alert_target: "operator session output (systemMessage); SOLEUR_HOOK_TRACE seam for debugging"
  configured_in: "plugins/soleur/hooks/hooks.json + plugins/soleur/hooks/ext-filter-detect.sh"
error_reporting:
  destination: "stdout marker; hook faults exit 0 (fail-open) per sibling-hook convention"
  fail_loud: "SOLEUR_HOOK_TRACE=1 emits trace lines to stderr; detection is advisory, never blocking"
failure_modes:
  - mode: "rtk installed but undetected (binary moved/renamed, hook config elsewhere)"
    detection: "SOLEUR_EXT_FILTER absent while `rtk session` shows coverage — rung-1 diagnostic in the docs"
    alert_route: "bug_report.yml external-filter field captures marker line at filing"
  - mode: "detector faults on a user's environment (missing settings.json, unreadable file)"
    detection: "fail-open exit 0; SOLEUR_HOOK_TRACE=1 shows the fault arm"
    alert_route: "none — advisory surface, fault must never break a session"
logs:
  where: "session stdout (marker); no persistence (stateless detection per session boundary)"
  retention: "session lifetime"
discoverability_test:
  command: "bash plugins/soleur/hooks/ext-filter-detect.sh --self-test"
  expected_output: "SOLEUR_EXT_FILTER"
```

## Guard Contract

### Guard 1 — `rtk` unwrap parity in `destructive-command-guard.sh`

**Property.** A command whose argv[0] chain contains `rtk` (optionally with
leading options and/or an exec subcommand `run|err|test|proxy|bypass|summary`) is
judged on the inner command's verdict, identically to the unwrapped form;
payload forms the guard cannot read (`-c`/`--command` strings, `--shell`
scripts, joined-string payloads, unknown `-*` words after the exec word)
produce `unparsed-wrapper` asks, never silent allows.

**Assembly.** Every word-walk path through `decide_walk` → `wrap_skip` →
`fold_name` (the single chokepoint for argv[0] resolution), plus the two
mirrored literal lists (`redact_word` :337, `long_word_judged` :526) that
enumerate wrappers by name, plus the sibling unwrap tables in
`pkill-self-match-guard.sh` and `proc.sh` (three input models — lexer token
array, pipeline-stage text, `/proc` argv — so the unwrap *code* stays
per-site by design; a shared function would be three functions wearing one
name). The python oracle (`test/…hook.test.sh` `unwrap()` 539–587) is the
independent second implementation sharing no code — assembly is both copies.
The exec-subcommand *data* (not the code) now lives in ~6 places — the
canonical grammar table is `plugins/soleur/scripts/lib/ext-filter-grammar.tsv`
(created in Phase 1 so the parity suite has a source before Phase 4 docs
exist; the doc cites and reproduces it) — and
`plugins/soleur/test/rtk-grammar-parity.test.sh` extracts the set from
each site and asserts equality against canonical (parity by extraction —
the oracle is never wired to the table).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `rtk` from the `decide_walk` alternation (1222) → `rtk rm -rf ~` row | RED (was allow, must deny) |
| 2 | Drop the `wrap_skip` `rtk` arm only → `rtk run rm -rf ~` row (guard sees `rtk` then can't unwrap) | RED |
| 3 | `rtk` absent from oracle's `unwrap()` OR the `decide` dispatch tuple (:601 — the drifty one) → executed `rtk` rows report HARNESS DEFECT | RED (suite fails, not just wrong verdict) |
| 4 | `fold_name` missing `rtk` → uppercase `RTK rm -rf ~` (`L` row — stub PATH can't resolve `RTK` on a case-sensitive FS, so literal kind not `X`) | RED (macOS case-fold class) |
| 5 | `redact_word` :337 missing `rtk` → credential-flag-preceded `rtk` quote row | RED |
| 6 | `long_word_judged` :526 missing `rtk` → overlong-word under `rtk rm` row | RED (bound-path under-ask) |
| 7 | Nested: `sudo rtk rm -rf ~` and `rtk env rm -rf ~` (inner `rtk` via `decide_walk` recursion) | RED-covered |
| 8 | Second member after compliant first: `rtk -v run rm -rf ~` (option + subcommand) alongside `rtk rm -rf ~`; `rtk run -c 'rm -rf ~'` → `unparsed-wrapper` ask (shell-string payload) | both RED-tested + string-payload ask row |
| 9 | Harness row: `rtk git push --force-with-lease` must-deny AND `rtk git status` must-PASS (allow) — proves the arm discriminates on the inner command, not on `rtk` presence; bare `rtk run` must-allow | push=RED-covered, status+bare-run=PASS control |
| 10 | `MIN_CASES` floor not bumped → row-count gate | RED |

### Guard 2 — `SOLEUR_EXT_FILTER` detection

**Property.** When an RTK or Headroom hook/proxy presence is detectable at
SessionStart, exactly one `SOLEUR_EXT_FILTER` marker per tool per event fires
with `tool=`+`version=`+`posture=` populated; clean detection emits
`SOLEUR_EXT_FILTER tool=none` — a marker always fires unless killed or the
hook itself died (fail-open), which is what makes liveness observable.

**Assembly.** The hook's detection arms (`command -v rtk`, `command -v
headroom`, settings-file hook-entry grep for `rtk`/`headroom` PreToolUse
entries, `ANTHROPIC_BASE_URL` non-default/loopback proxy check) — the
chokepoint is the hook's own dispatch; settings files are the input assembly
(`~/.claude/settings*.json`, `$cwd/.claude/settings*.json`). Epistemics
(corrections folded in from review): a **named posture requires identity
corroboration** — a bare PATH basename hit emits `tool=<name> via=path
posture=unmeasured` (name-collision safe); the BASE_URL arm alone emits the
neutral `tool=proxy posture=unknown` — NEVER a named vendor claim (a generic
LiteLLM/Helicone/corporate proxy must not be mislabeled Headroom);
`version=unknown` floors posture at `unmeasured`. Posture constants live in
one committed line, gated by Phase 3; `measured_at=` records the evidence
date so a screenshot carries the claim's vintage.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `rtk` from the detect set → stub-PATH fixture with fake `rtk` | RED (marker absent where expected) |
| 2 | Hook exits before emit on a stub `rtk`+`headroom` fixture → "0 detected" | RED (vacuous pass class: exit 0 with no emit) |
| 3 | Kill-switch `SOLEUR_DISABLE_EXT_FILTER_DETECT=1` with filter present → marker suppressed | PASS-only assertion (correct suppression, not detection) |
| 4 | `posture=` for headroom emits `measured-incompatible`; for rtk `unmeasured` pre-gate and `literal-clean` only when the Phase-3-gated constant says so | RED on tier swap or premature upgrade |
| 5 | Remove the `ANTHROPIC_BASE_URL` proxy arm → `ANTHROPIC_BASE_URL=http://localhost:<port>` fixture | RED |
| 5b | BASE_URL proxy fixture MUST emit `tool=proxy posture=unknown`, never `tool=headroom` | RED on named emit (misattribution class — indicts the user's own infra) |
| 5c | Stub `headroom` binary whose `--version` is non-Headroom → `posture=unmeasured` (name-collision) | RED on `measured-incompatible` emit |
| 5d | `version=unknown` path → posture floors at `unmeasured` | RED on any named posture |
| 6 | Dedup: same tool found by two arms (PATH + settings hook) → one marker | PASS |
| 7 | must-PASS: clean fixture emits `SOLEUR_EXT_FILTER tool=none` (not silence, not a false positive) | PASS control |
| 8 | Registration: `hooks.json` group present with `startup\|resume\|clear\|compact` + `timeout: 10` + quoted bash command spelling; `devin-dispositions.tsv` row present (mirror `compaction-state-hook.test.sh` scenario 16 / guard `_reg` block) | RED on dropped registration |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`destructive-command-guard.sh` unwraps `rtk` (and its raw-exec subcommands `rtk run`/`rtk proxy`/`rtk summary`); `rtk rm -rf ~` and `rtk git push --force` produce the same deny/ask verdicts as unwrapped forms; test-suite cases added." [issue #10230] | Phase 1 / Guard 1 / Files-to-Edit 1–3 | mapped |
| 2 | "SessionStart emits `SOLEUR_EXT_FILTER tool=<name> version=<v> posture=<tier>` when RTK/Headroom hooks are detected — two severity tiers" [issue #10230] | Phase 2 / Guard 2 / Files-to-Create 1 + test | mapped |
| 3 | "Gate-literal divergence measurement runs over RTK's filter set before docs land; the harness is kept this time" [issue #10230] | Phase 3 / Files-to-Create divergence harness + corpus | mapped |
| 4 | "`plugins/soleur/docs/pages/known-external-tools.md` canonical doc + README \"Known Issues\" entry + `bug_report.yml` external-filter fields + `external-env` triage label" [issue #10230] | Phase 4 / Files-to-Edit README, bug_report.yml + Create doc + label task | mapped |
| 5 | "please pay special attention to degradation in following instructions, and quality of our skills, agents, hooks and outcomes" [brief] | Evidence gate (Phase 3) + footgun documentation + boundary-anchor deferral issue | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| pkill-self-match-guard + proc.sh unwrap parity | — | inferred — justification: identical unwrap-table defect class on sibling boundary components (research found same gap); fixes owe users regardless of adoption (ask 1's rationale) |
| boundary-anchor deferral issue (not a fix) | — | inferred — justification: ~12 gates share the class via a different mechanism; different-subsystem rule keeps them out of this PR |
| `devin-dispositions.tsv` row | — | inferred — justification: devin-matcher-parity.test.sh fails on unregistered hooks.json entries |
| `external-env` label creation | "`external-env` triage label" [issue #10230] | asked |
| `SOLEUR_DISABLE_EXT_FILTER_DETECT` kill switch | — | inferred — justification: sibling-hook convention (`SOLEUR_DISABLE_<NAME>=1` first executable statement, ADR-277 D5) |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (hooks, test, scripts, docs, README), `.claude/hooks` (pkill guard, dispositions), `.github` (issue template)
- Planned files: ~18 | Estimated changed lines: ~900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — at the line-estimate boundary but one coherent defect class + its detection/docs; the boundary-anchor class is already split out as a separate issue. (If the diff lands materially over, the natural seam is Phase 3+4 vs Phase 1+2.)

## Acceptance Criteria

1. `rtk rm -rf ~`, `rtk git push --force`, `rtk run rm -rf ~`, `rtk err rm -rf ~`, `rtk test rm -rf ~`, `rtk proxy git push -f`, `rtk summary rm -rf ~`, `rtk -v run rm -rf ~`, `sudo rtk rm -rf ~`, `rtk env rm -rf ~` produce identical verdicts to unwrapped forms in `destructive-command-guard-hook.test.sh`; ask rows: `rtk run -c 'rm -rf ~'`, `rtk run --command 'rm -rf ~'`, `rtk run --shell fish -c 'x'`, `rtk err --shell fish 'rm -rf ~'`, `rtk run --ultra-compact rm -rf ~`, `rtk err 'rm -rf ~'` (joined-string payload) → `unparsed-wrapper`; `RTK rm -rf ~` (uppercase) covered by an `L` row; `rtk git status`/`rtk ls`/bare `rtk run`/`rtk gain` remain allow; `MIN_CASES` bumped; oracle `unwrap()` + `decide` tuple + stubs updated (oracle keeps its own literal `rtk` arm — parity is asserted by extraction, never shared evaluation); `redact_word`/`long_word_judged` include `rtk` with enumerated rows; named mutation rows join the committed M-battery with `DCG_ROWS` selectors; header prose documents the version-pinned grammar + `plugins/soleur/README.md` NOT-DECIDED sentence updated in sync (suite pins both).
2. `pkill-self-match-guard.sh` and `proc.sh` unwrap `rtk` **including the exec-subcommand word** (`rtk run ps aux`, `rtk run bash x.sh` land on the inner command, not `run`); their test suites gain `rtk` rows.
3. `SOLEUR_EXT_FILTER tool=<t> version=<v> posture=<p>` emits on `startup|resume|clear|compact` — `tool=none` on clean detection, one marker per detected tool (dedup across arms); `posture=unmeasured` for rtk until Phase 3 passes, `measured-incompatible` for headroom; `SOLEUR_DISABLE_EXT_FILTER_DETECT=1` suppresses; hook exits 0 on all fault paths; `hooks.json` + `devin-dispositions.tsv` registered and pinned by suite registration checks.
4. `scripts/ext-filter-divergence.sh` + corpus committed; runs offline (no transcript content); control arm runs unconditionally — `SKIPPED reason=rtk-absent` applies only to the rtk arm; exit non-zero with `INSTRUMENT-DEFECT` when the control arm shows zero divergence. **Gate: RTK-arm gate-literal divergence == 0 AND control-arm divergence > 0** — on pass, the same PR flips the hook constant to `literal-clean` and AC5's positive wording lands; otherwise hook+doc stay at `unmeasured`/pending wording and the report lands in the PR body.
5. `known-external-tools.md` carries: the canonical wrapper-grammar table (version-pinned); RTK posture per AC4 outcome stamped `measured on rtk <v>, <date>` + re-run instruction; Headroom `measured-incompatible` with the eval scope INLINE (version/date/mode/244-of-581/restructuring example); tier definitions (`unmeasured` is explicitly not an assurance); symmetric-methodology line; the `SOLEUR_EXT_FILTER` marker declared a stable contract (fields + enum frozen); three-rung diagnostic incl. a no-marker path for non-Claude surfaces; footguns (`RTK_DISABLED` absent — real disable is `mode = "disabled"` / `rtk run`); telemetry defaults dated+sourced; no vendor-maturity flags; FCC framed on reachability only. README Known Issues gains a third entry (one-sentence summary + link); `bug_report.yml` gains the dropdown + marker field (Claude-Code-only note) + verbatim-vs-filtered field (redact hint) + triage instruction to apply `external-env`; `external-env` label exists (verified `gh label list` post-creation).
6. Boundary-anchor deferral issue filed per review §5 mechanics: `--label deferred-scope-out`, `--milestone`, body carries `Mandated-By:`/`User-Impact:` lines + `## Scope-Out Justification`, `--body-file` absolute path in its own call, `code-simplicity-reviewer` CONCUR recorded before filing, PR body carries `Tracks #<issue>` + `Mandated-By:` (net-issue-flow gate), verified `gh issue view` post-filing.

## Test Scenarios

- `X @@ rtk rm -rf ~ @@ deny` / `X @@ rtk git push --force @@ ask` / `X @@ rtk run rm -rf ~ @@ deny` / `X @@ rtk -v run rm -rf ~ @@ deny` / `X @@ rtk proxy git push -f @@ ask` / `X @@ rtk git status @@ allow` rows in the guard suite.
- Mutation: delete the `rtk` `wrap_skip` arm → suite reddens on the new rows (Guard 1 row 2).
- ext-filter-detect suite: stub-PATH `rtk` fixture emits `tool=rtk`; corroborated `headroom` fixture emits `posture=measured-incompatible` only when version resolved AND ≤ the eval version (else `unmeasured`); bare-PATH-without-corroboration fixture emits `via=path posture=unmeasured`; generic `ANTHROPIC_BASE_URL=localhost` proxy fixture emits `tool=proxy posture=unknown` — never a named tool; clean fixture emits `SOLEUR_EXT_FILTER tool=none`; kill-switch suppresses; missing settings.json still exits 0.
- Divergence harness: `bash scripts/ext-filter-divergence.sh` on a host with `rtk` present emits the per-class table; on a host without `rtk` it exits 0 with `SKIPPED reason=rtk-absent` (not a fail — the harness must not brick CI).
- Docs: `eleventy` build passes with the new page; `rtk`/`headroom` command tokens in the doc each carry a verified-source annotation.

## Implementation Phases

### Phase 1 — Unwrap fixes (security surface)

1. `plugins/soleur/hooks/destructive-command-guard.sh`: header prose (46–57)
   gains the verified RTK grammar; a `wrap_skip` `rtk` arm; `fold_name` `rtk`
   arm; `decide_walk` alternation 1222 += `rtk`; `redact_word` allowlist 337
   += `rtk`; `long_word_judged` 526 += `rtk`. Arm semantics (verified 2026-10-13
   against RTK README + `src/main.rs`; re-verify per-subcommand `--help` at work
   time — Kieran/DHH both flagged README-vs-source drift):
   - Exec subcommands `run|err|test|proxy|bypass|summary` (case-SENSITIVE match —
     clap rejects `rtk RUN`): consume the word, then loop option-skip ↔
     non-option until a command word lands. Exec set is version-pinned in the
     header prose so a future RTK subcommand is a checklist edit (an unknown
     word after `rtk` still unwraps at it — `rtk <newsub> rm` lands on
     `<newsub>` → allow; accepted residual, documented).
   - Payload-as-string forms → `unparsed-wrapper` ask, never silent allow:
     `-c`/`--command` (+ `=` forms), `--shell <name>` (+ `=`), and — because
     upstream `err|test|summary` join trailing args to `sh -c` — ANY payload
     word under those three that is quoted or carries shell metacharacters
     (`;|&(){}$`) asks (the lexer `f[]` quote flags discriminate; plain
     multi-word `rtk err rm -rf ~` is verdict-identical either way).
   - Any `-*` word AFTER the exec word that isn't a consumed value →
     `unparsed-wrapper` ask (`rtk run --ultra-compact rm -rf ~` —
     `--ultra-compact`/`--skip-env` are `global = true` upstream, so flags
     legally sit post-subcommand; asking is the drift-safe posture, matching
     the guard's ask-not-miss convention).
   - Non-exec set (`gain|session|discover|init|telemetry|config|hook|mcp`,
     finalize vs `--help`): no unwrap — judged as argv[0]=`rtk` → allow.
   - Bare `rtk run` → must-allow; `rtk -- <cmd>` / `rtk run -- <cmd>` → pinned
     rows on the existing `--` retry; nested `sudo rtk rm` / `rtk env rm`
     (`rtk env` is RTK's own env-listing subcommand — a false deny on it is
     the safe direction; pin deliberately) / `rtk rtk rm` recurse free.
2. `plugins/soleur/test/destructive-command-guard-hook.test.sh`: `STUB_NAMES`
   += `rtk`; python oracle `unwrap()` arm + `decide` dispatch tuple 601; new
   `X` rows (incl. nested `sudo rtk`/`rtk env`) + `L` row for uppercase
   `RTK` + `redact_word`/`long_word_judged` rows; `MIN_CASES` bump; mutation
   suite row for the dropped-`rtk`-arm mutant (labels crafted so
   `DCG_ROWS=<ERE>` selects them).
3. `.claude/hooks/pkill-self-match-guard.sh`: `PFX` regex += `rtk` AND
   `stage_word` consumes the exec-subcommand word (else `rtk run ps aux`
   lands WORD=`run`, fail-open on the read-only arm);
   `.claude/hooks/pkill-self-match-guard.test.sh`: `rtk` rows incl.
   `rtk run` forms.
4. `plugins/soleur/scripts/lib/proc.sh`: `_PROC_WRAPPERS` += `rtk` AND the
   wrapper walk consumes the exec-subcommand word (else `rtk run bash x.sh`
   stays invisible — fail-closed blind spot, still worth closing).
5. `plugins/soleur/README.md`: update the pinned NOT-DECIDED sentence + add
   the Known Issues third entry (Phase 4 content lands same PR).
6. `.claude/hooks/lib/filing-shape.test.sh`: add an `rtk`-prefix LEXER row
   (`rtk gh issue create …` → filing detected) — the invariant lives in the
   position-independent stdin `gh` scan (`filing-shape.pl`:53), NOT in
   `filing-shape-corpus.json` (which feeds `filingShape()` on normalized argv
   where `rtk` at index 0 correctly returns `none`). Per the suite's own
   routing rule: verdict/refusal rows → guardrails.test.sh; lexing rows →
   filing-shape.test.sh.

6b. `plugins/soleur/test/rtk-grammar-parity.test.sh` (new): extracts the
   exec-subcommand set from each site (`wrap_skip` arm, header prose, README
   sentence, pkill `stage_word`, proc walk comment, python oracle, canonical
   table in `known-external-tools.md`) and asserts set equality — parity by
   extraction; the oracle keeps its own literal arm (a wired oracle is not a
   second implementation).

### Phase 2 — Detection

7. `plugins/soleur/hooks/ext-filter-detect.sh` (new): detection arms per
   Guard 2 assembly; `systemMessage` envelope; marker shape is strictly
   `key=value` — `SOLEUR_EXT_FILTER tool=<t> version=<v> posture=<p>
   via=path|settings-hook|proxy-env measured_at=<YYYY-MM-DD|->
   ref=known-external-tools` (severity escalation lives in the doc, never in
   marker adjectives — the marker is a per-session public claim); posture
   corroboration + `version=unknown` floor + proxy-neutral emit per Guard 2;
   three-tier constants (`unmeasured` default for rtk — flipped by Phase 3
   evidence); `tool=none` emit on clean detection; dedup across arms;
   stdin envelope read via the bounded `timeout 5 cat` convention
   (compaction-state.sh:123–129 — a hung SessionStart hook is worse than a
   crashed one); `SOLEUR_HOOK_TRACE=1` → trace lines to stderr
   (unkept-promise convention); `SOLEUR_DISABLE_EXT_FILTER_DETECT`;
   fail-open; `--self-test` printing the marker for the discoverability
   probe; harness skips mirror version-banner (`CODEX_THREAD_ID`,
   `PLUGIN_ROOT`) and the doc/bug-report field must note the marker is
   Claude-Code-only (Devin source matchers are dead — no-marker ≠ clean on
   non-plugin surfaces). Any `path=` field MUST be tilde-collapsed
   (`~/.claude/settings.json`) — never an absolute home path (GDPR note).
8. `plugins/soleur/hooks/hooks.json`: new SessionStart group,
   `startup|resume|clear|compact`, `timeout: 10`.
9. `.claude/hooks/devin-dispositions.tsv`: row (mirror version-banner's
   disposition).
10. `plugins/soleur/test/ext-filter-detect-hook.test.sh` (new; model on
    `version-banner-hook.test.sh` stub-PATH fixtures) including
    registration checks: hooks.json group present + matcher +
    `timeout: 10` + command spelling (mirror `compaction-state-hook.test.sh`
    scenario 16 / the guard's `_reg` block) — a dropped registration must
    redden, not ship silent.

### Phase 3 — Evidence gate

11. `plugins/soleur/scripts/ext-filter-divergence.sh` (new) +
    `plugins/soleur/scripts/ext-filter-divergence-corpus.txt` (new): corpus =
    per-command lines replayed verbatim vs `rtk`-prefixed; literal classes
    scored per the Research Insights set; control arm (`head -3`) runs
    UNCONDITIONALLY and must report divergence — zero control divergence
    exits non-zero `INSTRUMENT-DEFECT`; `SKIPPED reason=rtk-absent` exit 0
    applies only to the rtk arm. Corpus constraints (stated at authoring):
    every command read-only, deterministic, offline (no network/auth — an
    unauthed `gh` fails identically on both arms = vacuous measurement), and
    emitting >3 lines so the `head -3` control can actually diverge.
    Grammar-drift canary: on the rtk-present arm, scrape `rtk --help` for the
    canonical exec-subcommand set and emit non-fatal `GRAMMAR-DRIFT` when it
    disagrees with the committed canonical table.
12. Run it on the operator host (rtk installed) and persist the report to
    `knowledge-base/project/specs/feat-fcc-token-optimizations/ext-filter-divergence-report.md`
    — the durable artifact `ship` folds into the PR body (work never authors
    the body; per the PR-body-persistence sharp edge). On the conjunctive
    pass (rtk-arm == 0 AND control > 0): flip the hook's posture constant to
    `literal-clean` in the same commit. On any failure path: hook +
    doc keep `unmeasured` / pending wording; the report still lands.

### Phase 4 — Support surface

13. `plugins/soleur/docs/pages/known-external-tools.md` (new; frontmatter per
    `goal-primitive.md`) — the canonical grammar table is reproduced here from
    `plugins/soleur/scripts/lib/ext-filter-grammar.tsv` (the Phase-1
    canonical source the parity guard extracts from) — plus: posture table
    with RTK tier per Phase 3 outcome **stamped with measured version + date**
    and "re-run `ext-filter-divergence.sh` after an rtk upgrade" (posture is a
    point-in-time statement); Headroom `measured-incompatible` claims carry
    the eval's scope INLINE (version 0.37.0, date, library-mode, corpus shape,
    244/581 payloads, restructuring example) — not a bare citation to an
    internal spec; tier definitions in one sentence each (`unmeasured` = "the
    divergence harness has not run against this tool — not an assurance");
    symmetric-methodology line (the same gate applies to every tool — the
    asymmetry is evidence, not favoritism); the marker declared a stable
    contract (field names + posture enum frozen); three-rung diagnostic with
    an explicit no-marker path for non-Claude surfaces; footguns; telemetry
    defaults each dated+sourced; per-command-exclusion note if RTK supports
    it (re-verify `RTK_*` env vars against live RTK docs — do NOT write
    `RTK_DISABLED=1`; real disable is `mode = "disabled"` or `rtk run`
    passthrough). Brand hygiene: NO vendor-maturity flags in public copy
    (internal diligence stays internal); FCC framed on reachability only
    ("proxy-layer, unreachable from plugin hooks") — never characterize
    probe-mocking as circumvention in the public doc; README entry summarizes
    one sentence + link, no standalone verdict.
14. `.github/ISSUE_TEMPLATE/bug_report.yml`: `filter:` dropdown
    (none/rtk/headroom/other/don't know) + `session-start-marker` text field
    (description: paste the full line incl. `via=`/`measured_at=`; note the
    marker is Claude-Code-only — a Devin/other-harness report has no marker
    by design, and the template says so) + `filtered-vs-verbatim` textarea
    with a "redact secrets and personal paths" hint (GDPR note). The
    `filter` description instructs triage to apply the `external-env` label
    when value ≠ none (issue forms cannot conditionally label).
15. `gh label create external-env` + boundary-anchor deferral issue per
    review §5 mechanics: `code-simplicity-reviewer` CONCUR first (granted —
    conditional on severity ranking); body file written in its own tool call
    (`--body-file` absolute literal path) carrying `Mandated-By:`/
    `User-Impact:` lines + `## Scope-Out Justification`; `--label
    deferred-scope-out` + `--milestone` (resolve the milestone name via
    `gh api repos/{owner}/{repo}/milestones` at filing); verify
    `gh issue view` + `gh label list` post-filing; PR body carries
    `Tracks #<issue>` + `Mandated-By:` (net-issue-flow gate). Issue-body
    requirements: (a) census enumerated by grepping the boundary-anchor
    pattern itself (`(^|&&|\|\||;|\\s--\\s)` over `.claude/hooks/` +
    `plugins/soleur/scripts/` — MUST include `precommit-guard.sh:49`, which
    already carries a launcher alternation and sits OUTSIDE `.claude/hooks`),
    (b) severity ranking (`pre-merge-rebase.sh` review-evidence gate first),
    (c) the fix MUST land a shared wrapper-boundary fragment (a
    `.claude/hooks/lib/` constant/helper consumed by all boundary-anchored
    gates — else ~12 divergent prefix lists recreate this drift class), and
    (d) reference the canonical grammar table from step 13 so the two copies
    cannot diverge. Note the sharp-edge precedent: `rtk <cmd>` is the same
    argv-prefix class as PR #3689's `with_lock` bypass
    (`learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md` SE1).

### Files to Edit

- `plugins/soleur/hooks/destructive-command-guard.sh`
- `plugins/soleur/hooks/hooks.json`
- `.claude/hooks/pkill-self-match-guard.sh`
- `.claude/hooks/pkill-self-match-guard.test.sh`
- `.claude/hooks/lib/filing-shape.test.sh`
- `plugins/soleur/scripts/lib/proc.sh`
- `plugins/soleur/test/proc.test.sh`
- `plugins/soleur/test/destructive-command-guard-hook.test.sh`
- `plugins/soleur/test/destructive-command-guard-mutation.test.sh` (if new mutant added)
- `plugins/soleur/README.md`
- `.claude/hooks/devin-dispositions.tsv`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.claude/hooks/README.md` (hook registry row, if the new hook carries rule ids)

### Files to Create

- `plugins/soleur/hooks/ext-filter-detect.sh`
- `plugins/soleur/test/ext-filter-detect-hook.test.sh`
- `plugins/soleur/scripts/lib/ext-filter-grammar.tsv`
- `plugins/soleur/test/rtk-grammar-parity.test.sh`
- `plugins/soleur/scripts/ext-filter-divergence.sh`
- `plugins/soleur/scripts/ext-filter-divergence-corpus.txt`
- `plugins/soleur/docs/pages/known-external-tools.md`

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Support (carried forward
from brainstorm `## Domain Assessments`; CPO/CMO assessments informed scope
but map to no plan-time action)

### Engineering

**Status:** reviewed (brainstorm carry-forward — CTO)
**Assessment:** RTK reachable via the `updatedInput` mechanic Soleur already
ships (`grep-rewrite.sh`, ADR-162); Headroom unreachable for Bash/Read/Grep;
five FCC opts proxy-only. Verbatim-string machine → confident-false-negative
is the loss class; measurement-before-claim is the bar.

### Legal

**Status:** reviewed (brainstorm carry-forward — CLO)
**Assessment:** AGPL reference-only for FCC; depend-don't-vendor for
RTK/Headroom; no probe-suppression shipped or documented; disclose telemetry
defaults; DPD §2.1(d) stays literally true.

### Operations

**Status:** reviewed (brainstorm carry-forward — COO)
**Assessment:** Vendor maturity flags noted; wrapper-table fix is prerequisite
independent of adoption; docs-pointer shape minimizes support burden.

### Support

**Status:** reviewed (brainstorm carry-forward — CCO)
**Assessment:** Three-rung diagnostic + marker-named-version + bug-report
fields + `external-env` label + canonical-doc placement prescribed; the
`RTK_DISABLED` fabrication was corrected in this plan.

**Brainstorm-recommended specialists:** none invoked — CLO's `soleur:gdpr-gate`
recommendation fires conditionally at plan Phase 2.7 (single-user threshold),
handled there, not a named-specialist spawn.

### Product/UX Gate

**Tier:** none — no UI-surface files in Files to Create/Edit (docs `.md` is
excluded per `ui-surface-terms.md`; bug_report.yml is a form schema, not a UI
surface).
