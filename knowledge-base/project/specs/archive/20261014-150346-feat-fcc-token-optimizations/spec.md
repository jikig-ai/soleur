---
title: "External-tool output-filter defensive bundle — rtk guard unwrap + detection markers + docs + evidence-gated posture"
issue: [10230]
branch: feat-fcc-token-optimizations
lane: cross-domain
type: fix
date: 2026-10-13
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-13-fcc-token-optimizations-brainstorm.md
---

# Spec — #10230 external-tool output-filter defensive bundle

## Problem Statement

Third-party output filters (RTK's Bash-output rewriter, Headroom's tool-result
compressor) sit between Soleur's verbatim-string machinery and the model. Soleur
evaluated adopting FCC's stack and decided **no adoption** — but the evaluation
surfaced two defects that exist for users *regardless* of our posture: (1) `rtk` is
not in `destructive-command-guard.sh`'s wrapper table, so a direct `rtk rm -rf ~` or
`rtk git push --force` bypasses the guard (auto-rewritten commands are safe — the
guard judges original input per ADR-264 — the bypass is direct `rtk`-prefixed
invocations, which RTK's docs instruct agents to type); (2) Soleur has no
external-filter detection or troubleshooting surface, so "skill X broke" reports
cannot be attributed to filtered output vs. real defects.

## Goals

- Close the `rtk` guard bypass with test coverage.
- Make external-filter presence visible at session start (named marker, tool +
  version, severity tier) so bug reports arrive attributable.
- Measure RTK's filter set against the prior eval's gate-literal divergence
  criteria **before** documenting "compatible-with-caveats" — the posture claim is
  evidence-gated, not assumed.
- Ship a canonical known-external-tools doc + README Known Issues entry +
  bug-report external-filter fields + `external-env` triage label.

## Non-Goals

- Adopting, bundling, vendoring, or recommending any FCC/RTK/Headroom component.
- Any proxy behavior in the plugin (falsifies DPD §2.1(d); barred on the sandbox
  path by AGPL §13 + BYOK credential path).
- Quota-probe or aux-call suppression of any kind (circumvention-shaped on
  subscription auth; conflicts with the AUP).
- Aggregate filter-presence telemetry (flag for later only if issue volume
  justifies — CCO).
- Re-litigating Headroom: the archived `decided-no-build` spec's verdict and
  re-evaluation criteria carry verbatim.
- Token instrumentation — tracked by #1055, #6297, #5692; do not re-file.

## Functional Requirements

### FR1: `rtk` unwrap in destructive-command-guard

`rtk` joins the wrapper table (`sudo doas env command nohup time timeout nice`).
Raw-exec subcommands (`rtk run <cmd>`, `rtk proxy <cmd>`, `rtk summary <cmd>` — the
exact set verified against RTK's CLI at implementation) unwrap like `--` separators.
Verdicts: `rtk rm -rf ~` == `rm -rf ~` verdict; `rtk git push --force` ==
force-push verdict. Filter-only subcommands that re-exec a command (`rtk git status`
runs real `git status`) unwrap identically. Guard test suite gains `rtk` cases
including `rtk run`-nested forms.

### FR2: SessionStart detection markers

When an RTK or Headroom hook/proxy is detected (hook entries in settings files,
`command -v rtk`/`headroom`, `ANTHROPIC_BASE_URL` pointing at a local proxy), emit
`SOLEUR_EXT_FILTER tool=<name> version=<v> posture=<tier>` via the version-banner
pattern. Two severity tiers: `compatible-with-caveats` (RTK, once measured) vs
`measured-incompatible` (Headroom) — the incompatible tier warns harder. Marker text
names the docs page. Fires on `startup|resume|clear|compact` per the hooks.json
SessionStart matcher so compaction cannot lose it.

### FR3: Gate-literal divergence measurement (evidence gate)

Rebuild the deleted §3b scaffold and run RTK's filter set over the prior eval's
enumerated gate-literal set (`hr-verify-repo-capability-claim-before-assert`,
`hr-third-party-content-grep-on-undertaking`, `hr-type-widening-cross-consumer-grep`,
`extract-block.cjs` marker `indexOf`) plus a Bash-shaped set RTK actually touches
(porcelain formats, `gh --json` fields, test-runner summaries, `pipeline-tally.sh`
verdict tokens, `SOLEUR_*` markers). Acceptance bar per the archived spec's
re-evaluation criterion 2: zero divergence before docs assert compatibility. The
harness is **kept** this time (committed under the spec dir or a scripts/ path —
decide at plan; prior scaffold was deleted and that was recorded as a loss).

### FR4: Docs + support surface

- Canonical: `plugins/soleur/docs/pages/known-external-tools.md` — per-tool posture
  (RTK compatible-with-caveats date-stamped to the measurement; Headroom
  measured-incompatible citing the archived spec anchor; FCC aux opts documented as
  proxy-only + why Soleur won't ship them), three-rung diagnostic (is a filter
  active → symptom-shape match → verbatim-vs-filtered repro), footgun list
  (evidence asymmetry, filtered test output, rewrite invisibility, marker loss,
  recall/recovery commands, Headroom-in-credential-path privacy callout), current
  telemetry defaults per tool (Headroom's beacon default drifted — re-verify).
- README "Known Issues" third entry linking the doc.
- `bug_report.yml`: external-filter dropdown (none/RTK/Headroom/other/don't know) +
  detection-marker field + filtered-vs-verbatim output field.
- `external-env` triage label created and referenced by the doc.

## Technical Requirements

### TR1: No new runtime surface

Detection is read-only session-start output; the guard change is a table/mechanic
extension inside the existing fail-closed design. No new network calls, no vendored
code, no settings writes on the user's behalf.

### TR2: Evidence ordering

FR3 runs before FR4's RTK compatibility wording lands — or the doc ships with the
claim date-stamped and marked "pending divergence measurement" and the measurement
is a blocking follow-up in the same PR. (CCO: support owns the risk if the caveat is
silently wrong.)

### TR3: Legal constraints carried from CLO assessment

No FCC code (AGPL-3.0 — clean-room techniques only); RTK/Headroom referenced, never
vendored (Apache-2.0 §4 notices if ever distributed); no "free claude code" phrasing
(Anthropic mark); docs disclose telemetry defaults; no probe-suppression tooling or
how-to.

## Open questions carried from brainstorm

- Does `claude -p` headless surface SessionStart output retrievably? If not, the
  env/proxy check becomes rung 1 of the diagnostic for headless reports.
- Does RTK support per-command exclusion? If yes, "keep the savings, exclude the
  gates" is the doc's gold path over global `RTK_DISABLED=1`.
- Exact `rtk` subcommand set executing raw commands — verify against RTK's CLI.
- Whether the divergence set needs the Bash-shaped additions or the prior
  enumerated set suffices.
