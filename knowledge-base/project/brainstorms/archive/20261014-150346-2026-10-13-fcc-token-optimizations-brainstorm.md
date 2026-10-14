---
title: "FCC token-optimization techniques applied to Soleur — defensive bundle + evidence-gated RTK posture"
date: 2026-10-13
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [token-optimization, rtk, headroom, free-claude-code, hooks, external-tools, guard-bypass]
related_issues: [1055, 6297, 5692]
---

# FCC token optimizations — brainstorm

## The question

From <https://github.com/Alishahryar1/free-claude-code> (FCC, ~60k stars, AGPL-3.0):
can Soleur apply its token-optimization stack — "Up to 90% lower token usage. Optional
RTK filters common command output, and Headroom compresses tool results. Five FCC
optimizations handle quota probes, command-prefix detection, titles, suggestions, and
filepaths without calling a provider" — for our benefit and our users' benefit, with
explicit attention to instruction-following degradation and the quality of Soleur's
skills, agents, hooks, and outcomes.

## Measured floor (verified this session, not quoted from FCC's README)

- **This is substantially a re-litigation.** A measured `decided-no-build` spec already
  exists for Headroom — `knowledge-base/project/specs/archive/20261013-051752-feat-headroom-token-compression-eval/spec.md`
  (2026-09-07): 98.17% of operator tokens are cache reads (42 transcripts / 44,620
  messages); `tool_result` median 410 B; reachable compression ceiling ~5.6%
  theoretical, 2–3% realistic; 244/581 modified payloads lost ≥1 gate-relevant literal
  (2,367 `file:line` citations, 256 SHA/PR refs, 8 `SOLEUR_*` markers). Its
  re-evaluation criteria are enumerated and narrow: >15% reduction AND zero divergence
  on the gate-literal set AND confinement to non-grepped output.
- **The three mechanisms decompose by reachability.** Read FCC's
  `api/optimization_handlers.py` directly: the five "optimizations" (`try_quota_mock`,
  `try_prefix_detection`, `try_title_skip`, `try_suggestion_skip`, `try_filepath_mock`)
  are proxy-layer short-circuits that answer the harness's auxiliary provider calls
  locally — returning literal `"Conversation"` for titles, `""` for suggestions, a
  fabricated `"Quota check passed."` for probes, and deterministic regex extraction for
  prefixes/filepaths. A plugin sees tool-call lifecycle events, not provider API
  traffic — **all five are unreachable from Soleur's surface.**
- **Headroom is not reachable either, even ignoring the prior verdict.** PostToolUse
  can only append `additionalContext`; rewriting tool output requires
  `updatedMCPToolOutput`, which covers MCP tools only (Bash/Read/Grep results need a
  proxy — the credential-path defect the prior eval already found disqualifying).
- **RTK is the one genuinely new, reachable mechanism.** Apache-2.0 Rust binary;
  `rtk init -g` installs a PreToolUse hook that rewrites Bash calls (`git status` →
  `rtk git status`) and filters output per-command. Soleur already ships this exact
  mechanic — `.claude/hooks/grep-rewrite.sh` (ADR-162, `updatedInput` replaces
  `tool_input` wholesale). Caveat: the hook only reaches **Bash** — `Read`/`Grep`/`Glob`
  bypass it, so evidence shape diverges by which tool the model picked.
- **"Up to 90%" is scoped to terminal-output tokens**, per FCC's own README wording
  and RTK's own disclaimer ("90% of bash output is not 90% of your bill"; counts are
  `bytes/4` estimates). On Soleur's measured traffic distribution the whole-session
  figure is single-digit percent.
- **Live defect found independent of adoption** (COO): `rtk` is not in
  `destructive-command-guard.sh`'s wrapper table (`sudo doas env command nohup time
  timeout nice`); "wrappers outside the table" is a stated NOT-DECIDED. A literal
  `rtk rm -rf ~` or `rtk git push --force` is judged on argv[0]=`rtk` and allowed.
  Auto-rewritten commands are safe (per ADR-264 the guard judges original input); the
  bypass is only for direct `rtk`-prefixed invocations — which RTK's own docs instruct
  agents to type in "full" mode. Users may install RTK regardless of our posture.
- **License gates.** FCC is AGPL-3.0 → read-for-ideas only; clean-room reimplementation
  of techniques is lawful, no vendoring/porting; FCC on the hosted sandbox path is
  additionally barred by AGPL §13 + BYOK credential path + DPD §2.1(d) falsification.
  RTK/Headroom are Apache-2.0 → depend, never vendor (per the prior eval's TR3).
- **ToS posture.** Quota-probe mocking is circumvention-shaped on subscription auth
  and would conflict with Soleur's own AUP (§4.3(d), rate-limit clause) and falsify
  DPD §2.1(d) ("the Plugin does not act as an intermediary for any API calls") if
  shipped in-plugin. BYOK + documented `ANTHROPIC_BASE_URL` + traffic that still
  reaches Anthropic is the permitted envelope.
- **Soleur's support surface has no external-tool channel.** No troubleshooting page
  for plugin users (README §"Known Issues" is the only surface); `bug_report.yml`
  captures nothing about external tool environment; plugin users' only channel is
  GitHub Issues.

## Decision

**Approach B — defensive bundle with an evidence gate** (operator-chosen 2026-10-13):

1. Fix the `rtk` guard bypass in `destructive-command-guard.sh` (wrapper table +
   raw-exec subcommands `rtk run`/`rtk proxy`/`rtk summary`) — a security fix owed to
   users regardless of our posture.
2. SessionStart detection markers (`SOLEUR_EXT_FILTER tool=<name> version=<v>
   posture=<tier>`) naming tool, version, and posture tier — RTK "compatible-with-
   caveats", Headroom "measured-incompatible" — two severity tiers.
3. Rebuild the deleted divergence harness and measure RTK's filters against the prior
   spec's gate-literal set **before** docs land the "compatible" claim.
4. Docs: canonical `docs/pages/known-external-tools.md` + README Known Issues entry +
   `bug_report.yml` external-filter fields + `external-env` triage label.

Domain-leader fan-out ran (CPO + CLO + CTO mandatory triad + CMO + COO + CCO).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | No adoption of FCC techniques — no build, no bundle, no proxy | All five FCC opts are proxy-layer; a plugin cannot intercept provider calls, and shipping proxy behavior falsifies DPD §2.1(d) and strains the AUP. |
| 2 | RTK posture: compatible-with-caveats, evidence-gated | Operator choice; deterministic filtering is a different loss class than Headroom's restructuring — it may pass the divergence bar Headroom failed. The claim is NOT made until measured. |
| 3 | Headroom posture: measured-incompatible | Carries the archived `decided-no-build` verdict verbatim; docs cite the spec anchor + re-evaluation criteria rather than re-deriving. |
| 4 | Fix the `rtk` guard bypass unconditionally | The bypass exists for any user who installs RTK independently — a defect in our guard, not an adoption decision. |
| 5 | Detection markers carry tool + version + two severity tiers | Version is required for reproducibility (RTK's filter registry changes per release); incompatible-tier detection (Headroom) should alarm harder than caveats-tier (RTK). |
| 6 | Bug-report attribution fields over aggregate telemetry | Highest-signal triage data is filtered-vs-verbatim output; no aggregate filter-presence telemetry built now (flag for later if issue volume justifies). |
| 7 | BYOK token reduction remains an open user-value objective | Carried from the prior spec's Key Decision 2b; this brainstorm does not close it — the honest levers are instrumentation (#1055/#6297/#5692) and native emission discipline, not compression. |
| 8 | Productize Candidate: `gate-literal-divergence` harness | Rebuilt for this eval, reusable for the next external filter/compressor tool — a recurring category. Filed as a follow-up issue candidate. |

## Open Questions

- Does `SOLEUR_EXT_FILTER` fire once per session or per compaction/resume? A
  once-per-session marker can be lost to compaction before the failure it explains.
- Does `claude -p` headless surface SessionStart output anywhere a CI user can
  retrieve it? If not, the env/proxy-check rung promotes to step 1 for headless
  reports.
- Does RTK support per-command exclusion (an allowlist for gate-verbatim commands)?
  If yes, "keep the savings, exclude the gates" becomes the gold-path doc
  recommendation over global `RTK_DISABLED=1`.
- Which `rtk` subcommands execute raw commands and must unwrap (`run`, `proxy`,
  `summary`, `test`, `err`?) — to be enumerated against RTK's CLI at implementation.
- Should the divergence harness reuse the prior eval's enumerated gate-literal set
  verbatim, or does the RTK arm need a Bash-output-shaped set (porcelain formats,
  `gh --json` fields, test-runner summaries)?

## User-Brand Impact

- **Artifact:** Soleur's gate/guard integrity under third-party output filters — the
  user-facing surface is "skills that verify correctly" and the destructive-command
  guard's promise.
- **Vector:** a filtered/restructured tool result hides an error or a gate literal; a
  guard bypass executes a destructive command; each reads as a Soleur failure while
  the cause is external.
- **Threshold:** single-user incident — one filtered `pytest` tail or one `rtk rm`
  bypass reaching a user is the incident this bundle exists to prevent.

## Lane

`cross-domain` (forced by `USER_BRAND_CRITICAL` triad; no operator override).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Mechanisms split cleanly by reachability — RTK yes via PreToolUse
`updatedInput` (precedent: `grep-rewrite.sh`, ADR-162), Headroom no (PostToolUse can't
rewrite Bash/Read output), five FCC opts no (proxy-only). Soleur is a verbatim-string
machine; measured loss class is confident-false-negative on gate literals. Aux calls
are a rounding error for plugin users, not a cost center. Recommends
measurement-and-recommendation over build; pilot must reuse the prior divergence test
as go/no-go.

### Legal (CLO)

**Summary:** AGPL makes FCC reference-only (clean-room techniques lawful, no
vendoring); FCC on the sandbox path is triple-barred (§13 + credential path + DPD
falsification). Permitted envelope: BYOK + documented base URL + traffic that reaches
Anthropic. Quota-probe suppression is the disqualifying behavior — circumvention-shaped
on subscription auth and internally inconsistent with Soleur's AUP. Docs should
disclose each tool's telemetry defaults (Headroom's beacon default drifted since the
last eval — re-verify at write time).

### Product (CPO)

**Summary:** The question was substantially answered with measurements in the archived
spec; FCC's contribution is a different delivery vehicle, not a different mechanism
class. "Up to 90%" does not transfer — reachable surface measured at 2–3%. Worst user
outcome is the silent-gate failure class. The real prerequisite remains token
instrumentation (#1055/#6297/#5692), never executed. Separable non-proxy adaptation
worth noting: "Soleur emits less" (denser output by convention) is quality-preserving
by construction.

### Marketing (CMO)

**Summary:** Deliberately do not claim the number — "up to 90%" is FCC's layer and
FCC's measurement; Soleur's ownable story is "efficiency as discipline" (ADR-151
index/body split, skill-description budget, haiku-pinned researchers, semantic
model pins). A "how Soleur already manages token budget" piece is substantiated today.
Endorsement risk is asymmetric: a broken gate reads as Soleur's failure, not the
filter's.

### Operations (COO)

**Summary:** Vendor maturity flags on both tools (anomalous star-to-age growth,
bus factor ~1 on Headroom, Beta self-classification, contradictory telemetry docs);
partial harness coverage (RTK: no Devin/Grok; Headroom: no Devin). Found the
`rtk`→wrapper-table guard bypass and flagged it as a prerequisite fix independent of
adoption. Recommended path at the time: docs-pointer interim — upgraded by operator to
the evidence-gated bundle.

### Support (CCO)

**Summary:** No plugin troubleshooting surface or external-tool field in
`bug_report.yml` — the largest attribution gap. Prescribes a three-rung diagnostic
(is a filter active → symptom-shape match → verbatim-vs-filtered repro), detection
markers naming tool+version, a canonical `docs/pages/known-external-tools.md` + README
Known Issues pointer + `external-env` triage label, and a documented footgun list
(evidence asymmetry, filtered test output, rewrite invisibility, marker loss,
recall/recovery commands, Headroom-in-credential-path privacy callout).

## Capability Gaps

- **Token-usage baseline absent** — `api-spend-ledger.jsonl` empty; tracked by
  #1055, #6297, #5692 (evidence: prior spec §Follow-up; `ls api-spend-ledger.jsonl`
  absent from repo root). Not a new gap; do not re-file.
- **Gate-literal divergence harness does not exist** — prior eval's §3b scaffold was
  deleted; must be rebuilt from the brainstorm's prose (evidence: CPO's read of the
  archived brainstorm; `find` for harness files under `plugins/soleur/` returned none).
- **No plugin troubleshooting surface** — `plugins/soleur/docs/pages/` has no
  troubleshooting doc; README §"Known Issues" is the only shipped surface (evidence:
  CCO directory listing; `bug_report.yml` field enumeration).
- **No `external-env` triage label** — `gh label list` not yet run; to verify at
  implementation.

## Session Errors

- CLO's initial claim "no root LICENSE file exists" was **refuted by `ls`/`git
  ls-tree`**: `LICENSE` exists on `main` and in this worktree. Recorded so the error
  is not propagated into the spec.
- Prior-session correction carried forward: the 2026-09-07 eval's grep-divergence
  scaffold was deleted (noted in that brainstorm's Session Errors §5); the rebuild is
  a real line item, not a free re-run.
