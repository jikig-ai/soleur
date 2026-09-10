---
title: "Serena MCP — adopt for Soleur dev sessions and/or Soleur users?"
date: 2026-09-10
status: decided-verified
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [mcp, context-engineering, external-tool-eval]
related_adrs: [ADR-052, ADR-058, ADR-041, ADR-093, ADR-209, ADR-151]
related_issues: [5708, 1055, 3722, 7920]
external_tool: https://github.com/oraios/serena
supersedes_deferral: none
---

# Serena MCP — evaluation

## The question

> "Brainstorm whether Serena MCP is worth adopting for Soleur — for our own dev
> sessions and/or for Soleur end users."

This evaluation was explicitly deferred by the Headroom record (2026-09-07, Key
Decision #6: "Serena MCP is separable and may be considered on its own merits …
Not evaluated here"). This is that evaluation.

Two halves, different reasons, **both no**. Neither reason is the reason that
killed Headroom.

## What Serena actually is (verified, not summarised from the pitch)

MIT, Python, ~29.1k stars, 1,975 forks, created 2025-03-23 (~537 days), pushed
2026-09-08. From **Oraios AI Jain & Panchenko IT-Berater Partnerschaft**,
Lorschstr. 7, 80634 München — Partnerschaftsregister AG München PR 2486. A real
partnership, not a GmbH; no DPA, no standalone privacy policy, no commercial
terms published.

Installed `uv tool install -p 3.13 serena-agent`. An MCP server giving an agent
**symbol-level** code retrieval and editing through Language Server Protocol
backends for 40+ languages.

- **Retrieval:** `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`,
  type hierarchy, `search_for_pattern`.
- **Editing:** `replace_symbol_body`, `insert_before/after_symbol`,
  `replace_content`, rename, move, safe-delete, plus `execute_shell_command`.
- **Memories:** markdown written to `<project>/.serena/memories/*.md`, plus an
  onboarding pass over the project.
- Language servers are **downloaded on demand at first use** (SHA256-pinned in
  code), not vendored.

This is a well-built, genuinely useful tool. The verdict below is about fit.

## Pre-registered falsification criteria

Committed to disk **before any measurement**, in
`2026-09-10-serena-mcp-eval-PREREGISTRATION.md` (commit `f2b04cabb`), so the
thresholds could not be fitted to results. Operator-confirmed 2026-09-10.

| # | Criterion | Threshold |
|---|---|---|
| A1 | Share of tool-result bytes spent navigating **code** files | > 15% |
| A2 | Token reduction on that slice, symbol-wise vs grep+read | > 25% |
| A3 | Divergence on grep-discharged gates | zero |
| B1 | Egress-proven local-only AND installable within ADR-052 | binary |
| B2 | Cold-start amortizes against measured per-workflow savings | net positive |
| B3 | Evidence that code search is a felt user cost | non-zero |
| W1/W2 | Write tools pass the write-boundary sweep and are attributable | separate gate |

A1's level is deliberate: Headroom died at a 2–3% reachable surface, so 15%
asserts Serena must address a materially larger slice than the tool we most
recently rejected.

## Axis A — operator dev sessions: A1 FAILS, measured

### The repo is not the shape Serena is for

Measured **pinned at `origin/main` = `b4db399d9`** (whole-corpus `cat | wc -l`, not
`xargs wc -l | tail -1` — see Session Errors #1 for the wrong method that preceded
it). The pin is load-bearing: an unpinned count drifts as this very PR adds files,
so three runs of the same question legitimately disagree.

| Class | Lines | Share |
|---|---:|---:|
| `.md` prose | 1,499,709 | **63.3%** |
| `.ts` | 391,254 | 16.5% |
| `.sh` | 345,681 | 14.6% |
| `.tsx` | 83,655 | 3.5% |
| `.sql` + `.py` | 47,663 | 2.0% |

Of 474,909 TS/TSX lines, **286,531 are tests**; non-test application code is
~188,378 lines, **≈8% of tracked lines**. 9,045 of 9,700 markdown files sit under
`knowledge-base/`. On markdown and shell — 78% of the corpus — `find_symbol` and
`replace_symbol_body` do nothing and Serena degrades to `search_for_pattern`,
i.e. the grep we already have.

### A1, measured on real transcripts

Corpus: 60 local Claude Code transcripts for this project (650,915,359 B = 0.61 GiB),
30,134 `tool_result` blocks, 29,317,517 result bytes. Each result was attributed
back to the `tool_use` that produced it and classified by target file type.

**The corpus grows while the session runs** — this session appends to it — so a
re-run drifts by ~±0.03 percentage points and will not reproduce these figures to
the last digit. An independent re-run during review returned 5.85% / 87.97%. The
drift is far smaller than the margin to the threshold, so it does not touch the
verdict; it is recorded so a future reader does not mistake drift for a discrepancy.

| Class | Share of tool-result bytes |
|---|---:|
| navigating **prose** (`.md`) | 25.94% |
| navigating **shell** (`.sh`) | 24.29% |
| navigating unknown/ambiguous | 23.53% |
| navigating **config** (`.yml`/`.tf`/`.json`) | 8.35% |
| non-navigation tools | 6.33% |
| **navigating code (`.ts`/`.py`/`.sql`/…)** | **5.86%** |
| non-navigation bash | 5.70% |

**Total navigation traffic is 87.97%** of tool-result bytes — agents in this repo
do almost nothing but look things up. They just don't look up *code*.

Because the ambiguous bucket is large, A1 was **bracketed** rather than reported
as a point estimate. A deliberately over-generous upper bound — counting a
navigation result as "code" if *any* code extension appears anywhere in the
command, so a `grep` touching one `.ts` and five `.md` files scores as code —
gives **11.16%**.

| A1 bound | Value | Threshold | Verdict |
|---|---:|---:|---|
| Lower (dominant extension) | 5.86% | > 15% | FAIL |
| Upper (any code ext mentioned, over-generous) | **11.16%** | > 15% | **FAIL** |

**The generous bound does not reach the threshold.** A1 fails conclusively, and
it fails without needing the ambiguous bucket adjudicated.

**A2 and A3 were not run.** Under a pre-registration where all criteria must
hold, A1's failure settles Axis A alone, and running A2 after seeing A1 fail
would be measurement theatre. Stated plainly so no future reader assumes a
reduction figure exists: **there is no measured A2 number for Serena.**

The honest counterpoint, recorded because it is real: `cc-dispatcher.ts` (4,478
lines), `ws-handler.ts` (3,402), `soleur-go-runner.ts` (3,363) and
`agent-runner.ts` (3,186) are exactly where symbol-scoped reads beat whole-file
reads. That is a genuine win across roughly four files, against a ~20-tool MCP
schema tax paid on **every turn** of a stream that is 98.17% cache-read
(Headroom §2). The narrow win does not survive the fleet-wide cost.

## Axis B — Soleur end users: structurally blocked, and unmeasurable

Kept deliberately un-merged from Axis A. **Users run BYOK on their own Anthropic
key (ADR-041) — tokens are real money to them, and the operator's flat-subscription
"$0 marginal" fact does not transfer.** Axis B is not rejected on cost grounds.

### The insertion point exists — unlike Headroom — and is worse than none

This is the substantive difference from the Headroom evaluation, which had no
user-side insertion point at all. Here there is one:
`agent-runner.ts:1172-1177` reads `mcpServers` from the **deployed** plugin's
`plugin.json` and uses the names for `canUseTool` allowlisting.

But all four current entries are `type: "http"` vendor-operated URLs:

```json
"context7":   { "type": "http", "url": "https://mcp.context7.com/mcp" },
"cloudflare": { "type": "http", "url": "https://mcp.cloudflare.com/mcp" },
"vercel":     { "type": "http", "url": "https://mcp.vercel.com" },
"stripe":     { "type": "http", "url": "https://mcp.stripe.com" }
```

There is **no stdio entry anywhere in `plugins/`**. Serena would be the first —
the first *executed code* in the plugin, a different review class entirely. And a
stdio server spawns as a child of the CLI process, which connects plugin servers
at container level, **outside the bwrap sandbox**: un-`denyRead`'d, with full
container filesystem access and allowlisted egress. That is a strictly weaker
boundary than the Bash tool it would replace.

### B1 — FAILS on three independent hard stops

| Blocker | Evidence |
|---|---|
| No Python, no `uv` | `Dockerfile:2,42` → `node:22-slim`; the only apt installs are `ca-certificates git bubblewrap socat qpdf jq` and `gh` |
| Egress is default-drop and omits every host Serena needs | `cron-egress-allowlist.txt` (23 hosts) contains **no** `pypi.org`, `files.pythonhosted.org`, `astral.sh`, `registry.npmjs.org`, `objects.githubusercontent.com`. ADR-052's 2026-06-29 amendment states npm is deliberately excluded and must not be re-added |
| bwrap egress never reaches PyPI | `agent-runner-sandbox-config.ts:218` — `allowedDomains: opts?.allowGithubEgress ? [...GITHUB_EGRESS_DOMAINS] : []`, and `agent-runner-query-options.ts:288` sets `allowGithubEgress: Boolean(args.ghToken)`. So on the repo-connected path it is `github.com` + `api.github.com`, **not** empty — but never PyPI, which is what the install needs |

`uv tool install serena-agent` fails; the on-demand language-server downloads
fail. Both are **expected** to fail closed and page Sentry — flagged as expected, not
asserted: the Agent SDK's behaviour on an absent plugin-declared stdio binary is
unverified (see Open Questions). Making Axis B work is an image rebuild
plus per-language LSP baking plus a new write sentinel — net-new architecture,
not a config line.

One incidental benefit of that same posture: Serena's news beacon (below) would
also be dropped at the firewall.

### B2 — cannot be evaluated, and this corrects the brief's premise

The evaluation was asked to use the per-workflow LLM cost instrumentation that
shipped in PR #7916 (merged `b4db399d9`, migration 136, live in prd) as the
baseline Headroom lacked. **It cannot serve as that baseline for either axis**,
and forcing it to would have been the error the Headroom record was written to
prevent:

- **For Axis A it is the wrong population.**
  `sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ)` is `SECURITY DEFINER`,
  `search_path`-pinned, `service_role`-only, keyed on `user_id`, and fed from
  `conversations.total_cost_usd`. It measures **cloud-sandbox tenant
  conversations**. Operator-local Claude Code sessions write nothing to it.
- **For Axis B it is the wrong grain.** It is conversation-grain and
  first-workflow-wins. Sizing Serena's user value needs per-tool or per-turn token
  attribution, and **ADR-209 explicitly extends the turn-grain non-goal "from
  accounting into attribution"** (`ADR-209:59`), having rejected a per-turn
  `usage_events` table as reopening NG3.

So the measurement Axis B needs is one this instance has **architecturally
declined to build**. That is a legitimate answer, not a gap to paper over. #1055
remains open for per-agent attribution and is the nearest track.

### B3 — demand is absent

An all-state issue search returns zero reports of slow or costly code search; the
only hit is our own deferral (#5708). #1691 (BYOK cost indicator) shipped, so a
user *would* see cost. #1866 (budget controls) was deferred with the explicit
trigger "when beta users provide feedback on cost anxiety" — it has not arrived.
Beta users number **1**, and that tester runs the self-hosted CLI, not the
sandbox. Serena-in-sandbox has zero users.

The empirical-demand gate
(`2026-05-13-brainstorm-mcp-tier-classify-defer-when-empirical-demand-absent.md`)
fires here on absence of measurement, not on a rival pain.

**Correction to inherited framing:** the 2026-06-29 codebase-memory record said
"the evidenced user pain is session continuity." That is now stale — #5240/#5313/
#5340 closed and #5274 was deferred as largely redundant. The 2026-09 statement is
blunter: there is no evidenced user pain of any kind, because there is no measured
user. Separately, that record's Axis-B gate "needs repo-connect GA" **is now met**
— #1060 is closed and `ensureWorkspaceRepoCloned` clones the founder's repo into
the agent's cwd. Do not re-inherit "users have nothing to index"; that half is
false. The blockers are the three in B1, not the absence of a codebase.

## Axis C — knowledge-base markdown

Not a Serena question. A code-symbol engine is inert on prose, and the underlying
KB semantic-search need routes to the pgvector track, which is itself **not
implemented**: #4043 closed (R@5 0.1449 against a 0.4 threshold), #4176 closed,
#4119 open and ADR-gated. Inherited unchanged from the 2026-06-29 record.

## Write tools — the separate gate (operator decision)

Gated separately from retrieval at the operator's instruction, and this is where
the sharpest finding sits. Under Axis B, `replace_symbol_body` /
`insert_after_symbol` / `replace_content` would write to the user's connected repo
**from outside the bwrap boundary**, bypassing `filesystem.allowWrite:
[workspacePath]` and the per-sibling `denyRead` that prevents cross-tenant reads.

`hr-write-boundary-sentinel-sweep-all-write-sites` requires enumerating all write
sites when a guard is added; here the inverse happens — a new write path appears
that **no existing sentinel covers**. `canUseTool` would see one opaque
`mcp__…__replace_symbol_body` call with no path argument it can validate against
`isPathInWorkspace`. W1 fails; W2 fails.

This also *reopens a deliberately closed capability*: the Concierge path hard-blocks
Edit/Write via `CC_PATH_DISALLOWED_TOOLS` and routes Bash through `safe-bash.ts`.
Serena ships `execute_shell_command`. It is not a read-only add-on.

## Legal — not the blocker, but two live conditions

- **MIT**, confirmed via `gh api repos/oraios/serena/license`; PyPI `serena-agent`
  1.7.0 also MIT. No vendored binaries — language servers fetch at runtime.
- **Declaring it in `plugin.json` is not distribution.** A `mcpServers` entry is a
  dependency pointer; upstream hosts serve the bits. "Depend, do not vendor" holds.
  **The trigger that flips it:** baking `serena-agent` or fetched LSP artifacts into
  a *publicly published* container image — that is conveyance, and Serena ships **no
  `NOTICE`/`THIRD_PARTY_NOTICES`** to satisfy the resulting notice obligations.
- **Bundled-license threads that were actually checked**, rather than assumed:
  C# Roslyn is MIT (not the VS-restricted license); Kotlin LSP is Apache-2.0 (the
  JetBrains CDN is a host, not a license). **Unverified and therefore off:** Java
  (Red Hat VSIX bundling JDTLS + a bundled JRE 21) and Terraform (`terraform-ls`
  against HashiCorp's BUSL migration).
- **One phone-home.** `src/serena/dashboard.py` fetches
  `https://oraios-software.de/serena_news.json` via `urllib`, ETag-cached, with
  **errors silently swallowed**. No posthog/sentry/mixpanel/segment. Local analytics
  only; memories are pure filesystem writes.
- **No new Article 30 row.** Limb 3 (infrastructure) is engaged, but the governing
  row is **PA-2**, whose TOM cell already covers workspace checkouts. Serena is
  self-hosted code in Jikigai's own compute — no personal data reaches Oraios, so
  there is no recipient and no Art. 28 relationship. **Do not add Oraios to the
  sub-processor table**; that would over-claim.
- **Supply chain:** contribution concentration measured at ~95% across the vendor's
  two named principals — bus factor is the firm. **No `SECURITY.md`** (contents API
  returns 404 — definitive absence, not a profile null), so there is no disclosure
  channel.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Do not adopt Serena for operator dev sessions.** | A1 measured 5.86%, and **11.16% even at a deliberately over-generous upper bound**, against a pre-registered 15%. 63.4% of the repo is prose and only ~8% is non-test app code. The real win exists across ~4 large TS files and does not survive a ~20-tool schema tax on every turn. |
| 2 | **Do not adopt Serena for Soleur users.** | B1 fails on three independent hard stops (no Python/`uv`; egress default-drop omitting PyPI/astral; bwrap egress limited to GitHub-only or nothing, never PyPI). B3 demand is zero with one beta user who is not on the sandbox. **Not** rejected on cost grounds — BYOK users pay real dollars per token. |
| 3 | **Serena's write tools are rejected on their own gate, independently of retrieval.** | An un-bwrapped stdio write path that no existing sentinel covers, reopening a capability the Concierge path deliberately hard-blocks. This verdict stands even if Axis A were later reversed. |
| 4 | **Serena's memories/onboarding are never adopted, in any pilot.** | A second opaque store competing with the git-tracked, verbatim, founder-readable KB that is the stated moat. Same separable-and-must-stay-unused shape as `headroom learn`. |
| 5 | **The shipped cost instrumentation is not a usable baseline for this question**, and the brief's premise is corrected accordingly. | Migration 136 is tenant-side and conversation-grain; operator-local sessions never touch it, and ADR-209 extends the turn-grain non-goal into attribution. |
| 6 | **This tracks #5708 rather than superseding it.** | Same tool class, same three axes. Add this record to #5708; do not open a parallel track. One axis is now known to be *worse* than that eval knew — it did not have the un-bwrapped stdio finding. |
| 7 | Re-evaluation criteria recorded (below). | Keeps the door open on evidence, not vibes. |

## Re-evaluation criteria (ALL must hold)

**Axis A:**
1. Repo composition shifts such that non-test application code exceeds **25%** of
   tracked lines (today ~8%), **or** a measured re-run of A1 on a fresh transcript
   corpus exceeds **15%** at the *lower* bound; **and**
2. a timeboxed pilot shows **≥20%** per-task token reduction on a TS-heavy task set
   with **zero** divergence on `file:line` citations, rule-id anchors, and
   `eval-gate:block` markers.

**Axis B — all three, and note (a) is currently blocked by our own ADR:**
1. Tool- or turn-grain token attribution exists (today an explicit ADR-209
   non-goal); **and**
2. ≥3 of the Phase-4 founders run against non-trivial repos on the **sandbox**
   (not the self-hosted CLI); **and**
3. #1443 exit interviews name search cost or latency **unprompted**; **and**
4. the sandbox gains a Python runtime and an egress posture that permits the
   install — which is itself an ADR-052 weakening and needs its own ADR.

Measure Axis B **on the sandbox**. Never inherit an operator-transcript figure for
it — that is the Headroom §1 error run in reverse.

## Non-Goals

- Vendoring Serena source into this repo.
- Publishing any container image with `serena-agent` or fetched LSP artifacts baked in.
- Adopting Serena's memories/onboarding.
- Re-evaluating pgvector Stage 3 (separable; ADR-gated).

## Open Questions

- **A2 has no measured value.** A1 settled Axis A alone, so no reduction figure was
  produced. A future re-evaluation must generate one rather than assume the tool
  would have cleared 25%.
- **The `nav_unknown` bucket is 23.53%** and was never adjudicated — the bash-command
  extension heuristic is noisy. It does not change the verdict (the generous bound
  already fails), but a future run wanting a point estimate must classify it.
- **The stdio-MCP failure mode is unverified.** No test in this repo pins Agent SDK
  behaviour when a plugin-declared stdio server's binary is absent. A spike would
  settle it — only if Axis B is reopened.
- Whether the four large TS files that *would* benefit justify a scoped, non-MCP
  alternative (e.g. a symbol-index skill over `server/` alone) is a different and
  cheaper question, unexplored here.

## User-Brand Impact

- **Artifact:** the Soleur agent's code-navigation and file-write path — in the
  rejected user-facing variant, an un-bwrapped stdio MCP subprocess inside each
  user's sandbox with read and write access to their private connected repository.
- **Vector:** a third-party LSP-driven write path outside the sandbox boundary could
  modify or exfiltrate a user's private source across the per-tenant `denyRead`
  boundary, with `canUseTool` unable to validate the target path — a cross-tenant
  read or an unattributable write to a founder's repo.
- **Threshold:** single-user incident.
- **Mitigation captured:** Axis B rejected; write tools rejected on an independent
  gate (Decision 3); any future reopening requires an ADR that explicitly weakens
  ADR-052 containment and ships a write sentinel covering MCP-originated writes.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing, Operations,
Sales, Finance, Support assessed low-relevance — an internal capability-adoption
decision with no customer-facing or positioning surface.

### Engineering (CTO)

NO-GO on both axes. Serena's competency is inert on 78% of this repo (63.4% prose,
14.6% shell) and non-test app code is ~8% of tracked lines. Axis B has three
independent hard stops — no Python in `node:22-slim`, an egress allowlist that
deliberately omits PyPI/npm per ADR-052's 2026-06-29 amendment, and
a bwrap egress policy that reaches at most `github.com`/`api.github.com` and never PyPI. The disqualifier is the write surface: a
plugin-declared stdio server connects at container level outside bwrap, so
`replace_symbol_body` would write to a user's repo through a path no existing write
sentinel covers.

### Product (CPO)

Operator: pilot at most, folded into #5708 — not a parallel track. Users: DEFER;
the value is real but the evidence, the instrument and the surface are not. Demand
is zero across all-state issue search, beta users number one and that tester is not
on the sandbox. The BYOK goal is legitimate — users pay their own key — but it is
unmeasurable today because ADR-209 makes turn-grain attribution an explicit
non-goal. Serena also costs ~20 tool schemas on every turn, including the
marketing/legal/finance conversations that are the CaaS thesis, where it is pure
loss. Do not adopt memories: a second opaque store against a git-tracked-KB moat.

### Legal (CLO)

Not the blocker. MIT confirmed at source; declaring an `mcpServers` entry is
dependency, not distribution — but baking artifacts into a published image would be
conveyance, and Serena ships no notices file. Operator self-use CLEAR. User-facing
CLEAR-WITH-CONDITIONS: block `oraios-software.de` (a silently-failing news beacon),
keep Java and Terraform language servers off pending JRE-21/BUSL verification, pin
by version and hash, never commit `.serena/`. **No new Article 30 row** — PA-2
governs and no personal data reaches Oraios; adding Oraios as a sub-processor would
over-claim. No `SECURITY.md` (404, definitive) means no disclosure channel.

## Session Errors

Recorded because this document's authority rests on having measured something, and
**two of its three instruments were wrong before they were right** — the same
pattern the Headroom record was forced to admit.

1. **The repo-composition measurement was wrong three different ways, and the wrong
   number reached this document's first draft.** `git ls-files … | xargs wc -l | tail -1`
   under-reports catastrophically: `xargs` splits into batches and emits a `total`
   per batch, so `tail -1` captures only the **final batch**. It returned KB markdown
   as 38,440 lines; the true figure at `origin/main` (`b4db399d9`) is **1,410,271** — a
   **36.7×** undercount. A subagent
   reported 24,941 by the same mechanism, and its table's cumulative column ran past
   100% (102.5%) without that being caught as the tell it was.
   **Recovery:** re-derived with `git ls-files -z | xargs -0 cat | wc -l`, which
   corroborated the CTO agent's independently-produced 1,499,642 for all markdown to
   within 0.005% (pinned value 1,499,709; the two runs measured different working-tree
   states, which is precisely why the table above is pinned to a ref). **Prevention:** never
   use `wc -l | tail -1` over a file list; and treat a percentage column summing past
   100% as instrument failure, not rounding.

2. **The A1 instrument returned 0.00% and the number was false.** v1 classified only
   `Read`/`Grep`/`Glob` results, reporting `nav_code = 0.00%` — which reads as "agents
   never look at code" and would have produced the same NO-GO for an entirely wrong
   reason. Cause: this repo runs in bypass-permissions mode, whose instructions tell
   agents to read with `cat`/`sed` and search with `grep` **through the Bash tool**.
   Bash carried **93.19%** of all tool-result bytes and v1 was blind to every byte of
   it. **Recovery:** v2 parses Bash commands for read/search verbs and target paths;
   `nav_code` moved 0.00% → 5.86%. **Prevention:** before trusting a share, check
   where the *denominator* actually went — a 93% bucket labelled "other" is the
   finding, not the background.

3. **Both instrument versions were validated against synthesized known-positive and
   known-negative fixtures before being trusted** — v1 reproduced 1000/500/250/77
   bytes across four classes exactly; v2 additionally proved a Bash `sed` on a `.ts`
   classified as code and a `git commit` did not. This is what caught error #2 as a
   classifier gap rather than a finding. Recorded as what *worked*, per the Headroom
   record's closing note.

4. **A1 was nearly reported as a point estimate.** 5.86% with a 23.53% ambiguous
   bucket sitting next to a 15% threshold is not a conclusion — the ambiguity
   straddled the gate. The bracketing run (11.16% upper) is what makes the failure
   conclusive. **Prevention:** when an unadjudicated bucket is larger than the margin
   to the threshold, bracket before concluding.

5. **The brief's premise that the new cost instrumentation gives "a real baseline to
   measure against" did not hold**, and was corrected rather than force-fitted. It is
   tenant-side and conversation-grain; Axis A never touches it and Axis B needs a
   grain ADR-209 declares a non-goal. Recording this under
   `wg-every-session-error-must-produce-either` because quietly measuring the wrong
   thing to satisfy a stated premise is precisely how a wrong number acquires
   authority.

Reproduction artifacts: `a1_measure.py` (v1), `a1_v2.py`, `a1_bracket.py` and both
fixtures were written to the session scratchpad. They contain no transcript content
and are reproducible from the method described above; the transcript corpus itself
is not committable (operator paths, session content).
