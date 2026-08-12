---
title: "Migrate the 5 secret-gate sites off the git-root fallback onto the bare plugin-root anchor"
date: 2026-08-12
slug: fix-git-root-fallback-untrusted-anchor
branch: feat-one-shot-7450-git-root-anchor-untrusted
issue: 7450
closes: 7450
type: security
priority: p0-critical
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-179, ADR-093, ADR-178, ADR-074, ADR-171]
related_issues: [7453, 6222, 7452, 7426]
---

> No `spec.md` exists for this branch, so `lane:` could not be carried forward — defaulted to
> `cross-domain` (fail-closed). The substantive assessment is single-domain (engineering);
> the fail-closed default only widens review, which is appropriate for a P0 security change.

## Overview

Five security-control invocations under `plugins/soleur/skills/**` resolve the script they
execute through `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`. The
default arm of that expansion trusts the git worktree, and on the review path the worktree
holds the reviewed party's files. Each of the five gates decides by exit code whether secrets
are emitted, so a substituted script that exits zero silently disables the gate while the
reviewer sees a pass. This plan migrates those five sites onto the anchor already ratified for
customer-facing plugin executables, corrects the superseded premise in the older decision
record, and adds a positive control so the gate can be driven red.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the brief cited by number was probed. Five premises held, three were stale —
and one of the stale ones changes the shape of the architecture deliverable.

| Premise as briefed | Probe | Verdict |
| --- | --- | --- |
| #7450 OPEN, `priority/p0-critical` + `type/security` | `gh issue view 7450` | **Holds.** Title: "P0: git-root fallback is not a trusted anchor — `gh pr checkout` puts contributor code behind 5 redaction gates" |
| Draft PR #7482 exists on this branch | `gh pr view 7482` | **Holds.** OPEN, `isDraft: true` |
| #7453 and #6222 both OPEN, neither to be closed here | `gh issue view` both | **Holds.** |
| All 5 secret-gate sites present and unmigrated on `main` | `git grep -n ':-\$(git rev-parse' -- plugins/` | **Holds.** All 5 present, byte-for-byte as briefed. |
| AC #3 already satisfied by #7426 | read `worktree-manager.sh`; `ls` the target | **Holds — evidence below.** |
| "#7453 … migrate to the bare anchor, **ADR-177**" | `ls` the ADR corpus | **STALE.** ADR-177 is *"A terminated suite is UNRESOLVED, not failed"* — test-runner taxonomy, unrelated. The bare-anchor decision is **ADR-179**. #7453's GitHub title carries the same wrong ordinal. |
| "AC #1 is an architecture decision; produce or amend an ADR" | read ADR-179 | **STALE IN FRAMING.** The decision is *already ratified*. See §Architecture Decision. |
| #6222's live sites are `review/SKILL.md:276` + `preflight/SKILL.md:1338`, both `bash scripts/domain-model-drift.sh drift --repo .` | `git grep -n 'domain-model-drift' -- plugins/` | **STALE.** Both are already migrated to bare `${CLAUDE_PLUGIN_ROOT}/scripts/domain-model-drift.sh` (review at the `Domain-model register drift note` item; preflight in the Check 11 fence). ADR-179's PR relocated that script into the payload and repointed its consumers. #6222's remaining members are a *different* set. |

### The decision is already made — ADR-179, not a new ADR

`knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
(status `accepted`, 2026-08-11, `amends: [ADR-093]`, `related: [7442, 7450, 6222]`) already
ratifies the anchor and already enumerates **exactly these five sites**:

> **R5.** *A severity-distinct subset of #7453, called out so it is not processed in file
> order.* Four shipped sites plus one test carry the **rejected option (d)** form … These are
> **secret-handling gates whose exit code decides whether secrets are emitted**, and after
> `gh pr checkout` the git root is the contributor's tree. Tracked at #7450 (P0). #7453's
> framing as a "~98-site convention migration" flattens that severity; **this subset goes first.**

ADR-179's options table already adjudicated all three alternatives AC #1 asks us to weigh:

| Option | ADR-179 disposition |
| --- | --- |
| Bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative>` | **CHOSEN** (option a) |
| `${CLAUDE_PLUGIN_ROOT:?…}` fail-closed hard error | **Rejected** (option b) — not the literal token, so not substituted; hard-fails the surface being repaired |
| `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse …)}` | **Rejected** (option d) — "#7450's exact vector … strictly worse than `./plugins/soleur` because it *looks* anchored" |
| A trusted-anchor resolver shim | **Rejected** (option e) — "any resolver that consults the *workspace* rather than the *installation* is CWD-shadowable" |

The residual gap is one of **scope, not of decision**: ADR-179 §Decision 1 says "every
customer-facing executable path in **plugin markdown**", but its Consequences scope the
skills corpus out ("The `~100` … sites under `plugins/soleur/skills/**` are **not** migrated
here … Deferred, blocked on this ADR"). So the deliverable is an **amendment extending
ADR-179 to this secret-gate subset of the skills surface**, not a fresh decision.

### Is the bare anchor safe for the CLI operator? (the AC #1 operator-experience question)

ADR-179 §R3 is explicit that loader substitution is **"CORROBORATED, not proven."** Two
independent pieces of evidence, plus one that is specific to the skills surface:

1. `knowledge-base/project/learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md`
   — *"`${CLAUDE_PLUGIN_ROOT}` is expanded by the plugin loader in all command/skill text,
   not just `!` blocks."* Names the **skill** surface directly, so the skills surface is
   already inside ADR-179 §R3's corroborated claim.
2. Shipped precedent on the **command** surface: `commands/go.md` and `commands/sync.md`
   both carry bare `${CLAUDE_PLUGIN_ROOT}/…` operands today.
3. ~~Shipped precedent on the skills surface itself — `preflight/SKILL.md` and
   `review/SKILL.md`.~~ **RETRACTED — this evidence is circular and must not appear in the
   amendment.** Measured: both bare-token skills sites landed in commit `98ad03aa8`
   (#7443, 2026-08-11) — *the same commit that introduced ADR-179*. Verified with
   `git log -1 -S'${CLAUDE_PLUGIN_ROOT}/scripts/domain-model-drift.sh'` against each file.
   They are not independent corroboration that the skills surface substitutes; they are the
   same unverified bet transplanted from the command surface roughly a day earlier. Caught
   by the plan-time CTO consult after this plan had already asserted it.

**Therefore this PR pays the measurement ADR-179 deferred.** §R3 states a direct run of a
bare token inside a bash fence "would close it outright, and remains a prerequisite for the
deferred `safe-bash.ts` migration (#7453)." The unknown now gates a **P0 secret gate**, and
retiring it costs minutes: ship a throwaway skill carrying a bare token in a ```bash fence
that prints its own expansion, and read the result. This is Phase 1 of the implementation and
it **precedes the amendment text**, because a negative result changes what the amendment
should say rather than merely weakening it (§R3a: under no-substitution, option (a)'s
advantage over `:?` evaporates). Asserting the fix without measuring it is precisely the
failure recorded in
`learnings/2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md`
— same week, same subsystem.

**The load-bearing asymmetry, and the reason this subset is safer to migrate than
`/soleur:sync` was.** If substitution does *not* happen, the bare form yields
`/skills/incident/scripts/redact-sentinel.sh` — root-anchored, nonexistent — the existing
`[[ -r "$SENTINEL" ]]` guard fails, and the skill halts at its documented exit-2. For
`/soleur:sync` that failure mode broke the feature ADR-179 was repairing, which is why §R3a
scopes the "becomes runnable" claim. **For a secret gate, refusing to run *is* the correct
outcome.** The gate exists to decide whether secrets may be emitted; an unresolved gate that
halts leaks nothing. The operator-experience cost is therefore bounded at "the incident /
legal-generate / linear-fetch skills refuse with a named error" — strictly preferable to the
current behaviour, where the gate silently resolves the reviewed party's file and passes.

### The five sites are three classes, not one — and ADR-179 §R5 mis-states this

ADR-179 §R5 calls all four shipped sites "secret-handling gates whose exit code decides
whether secrets are emitted." **Measured, that is false for one of them**, and the
differences change what each site needs:

| Site | Class | Existing guard | Halt cost | What the migration must do |
| --- | --- | --- | --- | --- |
| `incident/SKILL.md` | Secret gate | **Has** `[[ -r "$SENTINEL" ]] \|\| { … exit 2; }` with a documented exit-2 contract | Operator re-runs a PIR | Anchor swap **+ identity preflight** |
| `legal-generate/SKILL.md` | Secret gate | Has the same guard | Operator re-runs a legal draft | Anchor swap **+ identity preflight**; stay byte-identical to `incident` |
| `linear-fetch/SKILL.md` | Secret gate | **NONE** — verified: the `persist_safe_summary` bullet is a bare pipeline with no readability check and no exit-code dispatch | Empty persist-safe summary | **Highest residual risk in the set.** Anchor swap **+ add the missing guard** + identity preflight |
| `compound/SKILL.md` | **Not a secret gate** — `token-efficiency-report.sh` prints a top-3 cost table and appends `te-*` warnings to `.claude/.rule-incidents.jsonl` | n/a (advisory, explicitly non-blocking) | An advisory table is skipped | Anchor swap only; **do not assert the P0 secret-gate rationale for it** |

Two consequences:

- **`linear-fetch` is under-fixed by an anchor swap alone.** With no `[[ -r ]]` check, an
  unresolved root yields exit 127 and **empty stdout** — which an agent can persist as "the
  redacted text" or improvise around. The guard is the fix; the anchor is the other fix.
- **`compound` conflates ADR-179 decision 3's two roots, and only one moves.** The **code
  root** becomes `${CLAUDE_PLUGIN_ROOT}`. The **data root** is separately and *correctly*
  `TE_REPORT_REPO_ROOT`, defaulting to `git rev-parse --show-toplevel` **inside the script** —
  the script measures the workspace, so its data root *should* be the git root. Say this
  explicitly in the amendment or a reviewer reads the migration as internally inconsistent.
  (Its inputs are monorepo-only telemetry, so the customer-surface half of the rationale does
  not apply to this site either; it degrades to empty rather than failing.)

### The identity preflight is mandatory, and `[[ -r ]]` does not satisfy it

ADR-179 §(a) *Correction (review, measured)* is decisive and this plan initially missed it:

> Measured: with an ambient `CLAUDE_PLUGIN_ROOT` pointing at an attacker-chosen directory, a
> `test -d "$X/scripts"` preflight **passed** and the hostile payload **executed**.
> … **The preflight must verify plugin IDENTITY, not directory shape.**

`[[ -r "$SENTINEL" ]]` is a shape check of exactly that defeated kind. The bare anchor is
"strictly better than a `:-` default … but it is **not** safe by construction, and the
preflight is what carries it" — which is why ADR-179 makes decision 2 *mandatory rather than
defence-in-depth*. **Swapping the anchor without adding the identity preflight ships half of
ADR-179 and none of its decision 2.** The shipped form to reuse verbatim is `go.md` /
`sync.md`:

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
```

### Sweep — complete, classified (hr-write-boundary-sentinel-sweep-all-write-sites)

**Pattern A — `:-$(git rev-parse` under `plugins/`: 6 occurrences / 6 files.**

| Site (content anchor) | Class |
| --- | --- |
| `incident/SKILL.md` — `SENTINEL="…/skills/incident/scripts/redact-sentinel.sh"` | **IN SCOPE** — secret gate |
| `legal-generate/SKILL.md` — `SENTINEL="…/skills/incident/scripts/redact-sentinel.sh"` | **IN SCOPE** — secret gate |
| `linear-fetch/SKILL.md` — the `persist_safe_summary` bullet piping through `redact-linear-urls.sh` | **IN SCOPE** — secret gate |
| `compound/SKILL.md` — `bash "…/skills/compound/scripts/token-efficiency-report.sh"` | **IN SCOPE** — same form, same threat |
| `incident/test/redact-sentinel.test.sh` — `ANCHOR='…'` (Test 18 coupling fence) | **IN SCOPE** — pins the unsafe form as expected |
| `git-worktree/scripts/worktree-manager.sh` — `common_dir="${_common_dir:-$(git rev-parse --git-common-dir …)}"` | **BENIGN — excluded.** Not a script-execution anchor: it resolves the git *common dir* for lease state, and `--git-common-dir` is a different subcommand from `--show-toplevel`. Nothing is executed from it. |

Brief's count of 5 in-scope sites: **confirmed exact.**

**Pattern B — `$SCRIPT_DIR/../../..` climbing chains under `plugins/`: 45 occurrences.
Zero defects.**

| Count | Class | Resolution |
| --- | --- | --- |
| 35 | `plugins/soleur/test/**` harnesses | `REPO_ROOT` — monorepo-only test harnesses, never a customer execution path |
| 8 | `skills/*/scripts/**` executables (`community` ×3, `flag-create`, `flag-delete`, `flag-set-role`, `user-set-role`, `git-worktree`) | 3 levels → `plugins/soleur/scripts/` — **in-payload, trusted, layout-invariant.** ADR-178's rationale applies verbatim: in-plugin shell "can construct a layout-invariant `$SCRIPT_DIR` path and so needs no anchor at all" |
| 2 | `linear-fetch/scripts/parity.test.sh`, `plugins/soleur/test/session-state.test.sh` | `REPO_ROOT` — test harnesses |

**Pattern C — NEW FINDING, not named in the brief, not in ADR-179 §R4/§R5.** Two sites use an
**unconditional** `$(git rev-parse --show-toplevel)/plugins/soleur/…` to execute a plugin
script — a *third* form, with no `${CLAUDE_PLUGIN_ROOT}` arm at all:

- `preflight/SKILL.md` — `FORM_A_AWK="…/skills/preflight/scripts/parse-form-a.awk"`
- `preflight/SKILL.md` — `PROBE_GATE="…/skills/preflight/scripts/probe-verb-gate.sh"`

Both carry #7450's threat model (after `gh pr checkout`, the git root is the contributor's
tree) and `probe-verb-gate.sh` is itself a gate. **Their committed rationale is now
falsified**: the comment above `FORM_A_AWK` argues for git-root because
"`CLAUDE_PLUGIN_ROOT` is unset in a plain session, which would silently make the path
CWD-relative" — true of the `:-plugins/soleur` form it was written against, **not** of the
bare form, whose unset-expansion is root-anchored rather than CWD-relative. Neither is a
secret-emission gate, so per the routing rule they go to **#7453**, flagged
severity-above-baseline. Recorded so the next pass does not process them in file order.

**Pattern D — `${CLAUDE_PLUGIN_ROOT:-` under `plugins/`: 110 occurrences.** The #7453 bulk.
**Pattern E — bare `${CLAUDE_PLUGIN_ROOT}`: 24 occurrences / 7 files.** The migrated precedent.

### AC #3 — already satisfied by #7426, with evidence

`git-worktree/scripts/worktree-manager.sh` reads
`_SS_LIB="$SCRIPT_DIR/../../../scripts/lib/session-state.sh"` — **three** levels up from
`plugins/soleur/skills/git-worktree/scripts/`, resolving to
`plugins/soleur/scripts/lib/session-state.sh`, which exists in the payload (`ls` confirms,
28 037 bytes, mode 0775). The issue's cited five-level `.claude/hooks/lib/session-state.sh`
walk **does not exist anywhere under `plugins/`** — `git grep '\.claude/hooks' -- plugins/`
returns only markdown documentation links, no `source`/exec statement. PR #7426 (ADR-178)
relocated the library into the payload. **No work is planned for AC #3.**

### `safe-bash.ts` coupling — no change required

`EXACT_LITERAL_SAFE_COMMANDS` in `apps/web-platform/server/safe-bash.ts` is a closed set of
exactly two literals, both `worktree-manager.sh list|ls`. None of `redact-sentinel.sh`,
`redact-linear-urls.sh`, or `token-efficiency-report.sh` appears in it. These invocations
already fail the metachar denylist and run via the autonomous/sandbox path; swapping
`$( … )` for a bare `${ … }` does not move them across that boundary. **ADR-179's warning
that the migration "requires changing `safe-bash.ts`'s exact-literal set" applies to the
`list`/`ls` sites in the #7453 bulk pass, not to this subset** — a further reason this subset
can ship ahead of it.

### Institutional learnings

| Learning | Bearing |
| --- | --- |
| `learnings/best-practices/2026-07-08-adr093-anchored-literal-migration-needs-parity-test-and-grep-F.md` | **Two live constraints.** (1) A security-critical literal duplicated across sibling SKILL.md files needs a byte-identity parity test *in the same PR* — that is exactly Test 18, which must be **retargeted, never deleted**. (2) `grep -c` on a `${…}` needle silently returns 0 because `$`/`{`/`}` are not literal in BRE. **Every AC in this plan uses `grep -F`.** |
| `learnings/best-practices/2026-07-08-plugin-root-migration-ac-grep-scope-and-anchor-preservation.md` | **SUPERSEDED BY ADR-179 — do not follow.** It instructs "preserve the EXACT original fallback anchor per site — never homogenize", naming the git-root form as correct precedent. That convention is precisely what #7450 exists to reverse. Flagged loudly because a `/work` agent that consults learnings before ADRs would preserve the vector and produce a green no-op PR. |
| `learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` | A guard whose oracle derives from the artifact it guards is a tautology — deleting an arm shrinks both sides. Drives the AC #5 decoy design: the positive control must be an **independent** producer, not a set-difference over the suite. |
| `learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | The Guard Contract gate's origin. Assembly is **structural, not a snapshot**; a matrix row must add a *second* member after a compliant first. |
| `learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md` | "'The command is deployed' ≠ 'the scripts it shells out to are deployed.'" The original ADR-093 motivation. |
| `learnings/2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md` | Same week, same area: a brief that omits the disqualifying fact gets a confident wrong ruling. Drove the disqualifying-facts framing in this plan's CTO brief. |

### Property List (Phase 0.6b)

- **P1.** No secret-gate script path resolves through a tree the reviewed party controls.
- **P2.** When the plugin root does not resolve, the gate refuses rather than passing.
- **P3.** A future edit that reintroduces any CWD- or git-root-shadowable anchor at a
  secret-gate site fails CI.
- **P4.** The recorded architecture is not misleading about which anchor is canonical, on
  which surface, and why the git-root premise was wrong.
- **P5.** The anti-substitution guard can be driven RED by a planted decoy.

### Cut List (Phase 0.6b)

| Mechanism the ask proposes | Property | Already covered by | Disposition |
| --- | --- | --- | --- |
| "Produce a NEW ADR for the anchor mechanism" | P4 | **ADR-179** (accepted, `related: [7450]`, §R5 pre-scopes these 5 sites) | **CUT** → amendment to ADR-179 instead. A second ADR restating a ratified decision creates two records to keep in sync. |
| A trusted-anchor resolver (`resolve-git-root.sh`-style shim) | P1 | ADR-179 option (e), explicitly rejected: workspace-consulting resolvers are CWD-shadowable | **CUT — not researched further.** |
| `${CLAUDE_PLUGIN_ROOT:?…}` fail-closed expansion | P2 | ADR-179 option (b), rejected: `:?` is not the literal token either, so it is never substituted | **CUT.** P2 is bought instead by the existing `[[ -r ]]` guard plus the bare form's root-anchored unset-expansion. |
| `worktree-manager.sh` session-state anchor work (AC #3) | — | PR #7426 / ADR-178 | **CUT** — verified already satisfied. |
| A new bespoke guard script for the anchor form | P3 | `apps/web-platform/test/plugin-root-anchoring.test.ts` (356 lines; already implements runner-position + direct-exec detection and an identity-preflight anchor) | **CUT** → extend the existing guard's scope. A second scanner would leave two assemblies to drift apart. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200`, then a
standalone `jq --arg path` `contains` test per planned file path.

**None.** No open `code-review`-labelled issue names any of the seven planned paths. The two
open issues touching this area — #7453 and #6222 — are not `code-review`-labelled; both are
handled explicitly in §Implementation Phases (comment-only, no scope change).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Codebase reality | Plan response |
| --- | --- | --- |
| AC #1 requires producing or amending an ADR, treating the anchor as undecided | ADR-179 (accepted 2026-08-11) already chose the bare anchor and already rejected all three alternatives the brief asks us to weigh; its §R5 names these exact 5 sites | Reframe AC #1 from *decide* to *extend scope*. Deliverable is an **amendment to ADR-179**, designed in §Architecture Decision, authored at `/work`. |
| #7453 is "the bare anchor, ADR-177" | ADR-177 is the test-runner result taxonomy. The bare-anchor ADR is **ADR-179** | Correct the ordinal in the #7453 comment. Do not create an ADR at 177 or 180. |
| ADR-177's direction should be checked for consistency with our decision | Not applicable as briefed; the real question is ADR-**179** consistency | **Answered explicitly:** fully consistent — we adopt ADR-179's chosen option verbatim and extend its stated scope. No divergence, so no counter-decision to record. |
| #6222's live sites are the two `domain-model-drift.sh` bare-relative invocations | Both already migrated to bare `${CLAUDE_PLUGIN_ROOT}/scripts/domain-model-drift.sh` by ADR-179's PR | Re-scope the #6222 comment against ADR-179 §R4's re-derived table, not the stale two-site list. |
| AC #3 needs `worktree-manager.sh` work | Three-level in-payload anchor; target exists | **No work.** Recorded as already-satisfied-by-#7426 with evidence. |
| The 5 sites are the whole `:-$(git rev-parse` surface | 6 occurrences; the 6th is a benign `--git-common-dir` default | 5 in scope, 6th classified and excluded with reasoning. |
| (not in brief) | 2 **unconditional** git-root anchors executing plugin scripts in `preflight/SKILL.md` | New finding. Routed to #7453 with a severity flag; not folded in (not secret-emission gates). |

## User-Brand Impact

**If this lands broken, the user experiences:** `/soleur:incident`, `/soleur:legal-generate`
and `/soleur:linear-fetch` refuse to complete, halting at the redaction gate with
`redact-sentinel.sh unreadable` (exit 2). The operator cannot produce a post-incident report
or a legal draft until the plugin root resolves. No data is lost and nothing leaks — the
failure is a refusal, not a corruption.

**If this leaks, the user's data is exposed via:** a reviewer runs `/soleur:review` on a
contributor PR, which instructs `gh pr checkout`. The redaction gate then resolves
`redact-sentinel.sh` **from the contributor's tree**. A hostile PR ships a two-line
`redact-sentinel.sh` that `exit 0`s. The operator's post-incident report — which by
construction quotes production logs and therefore carries API keys, Supabase service-role
tokens, and customer identifiers — is written to `post-mortems/` and pushed **with the
redaction gate reporting a pass**. The operator sees a green gate and has no signal that
redaction never ran.

**Brand-survival threshold:** `single-user incident`.

One operator, one hostile PR, one leaked post-mortem is a terminal-class event for a product
whose entire proposition is that a non-technical founder can run engineering safely. The
threshold sets `requires_cpo_signoff: true` and enrols `user-impact-reviewer` at review time.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-179 — do not write a new ADR.** ADR-179 already ratified the mechanism; the gap
is that its Decision 1 is scoped to the customer-facing *command* surface while these five
sites are on the *skills* surface, which its Consequences explicitly deferred.

The amendment (authored at `/work`, designed here) must say:

1. **Scope extension.** ADR-179 Decision 1's canonical bare
   `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>` form extends from
   `plugins/soleur/commands/**` to **secret-gate invocations in
   `plugins/soleur/skills/**`**, defined as the closed set of gate scripts in
   §Guard Contract. The remaining ~105 non-gate skills sites stay deferred to #7453.
2. **Why this subset can precede #7453.** #7453 is blocked on a `safe-bash.ts`
   exact-literal edit; measured, none of these three scripts is in
   `EXACT_LITERAL_SAFE_COMMANDS`, so this subset carries no allowlist edit and is not
   actually blocked by that coupling.
3. **The fail-closed asymmetry that makes a secret gate different from `/soleur:sync`.**
   ADR-179 §R3a scopes the "becomes runnable" claim to the substitution branch because a
   refusing `/soleur:sync` is a broken feature. For a gate whose exit code authorises secret
   emission, a refusal **is** the correct unresolved-root behaviour, so this subset is
   sound under **both** branches of §R3 — strictly stronger than ADR-179's own position on
   its original surface. Record this explicitly; it is the substantive new reasoning.
4. **§R3 retired by measurement, not by argument.** Record the Phase 1 probe — the artifact,
   the invocation, and the raw output — and upgrade §R3 from "corroborated" to "proven" (or,
   on a negative, re-plan; see Phase 1). **Do NOT cite `preflight/SKILL.md` or
   `review/SKILL.md` as independent skills-surface evidence** — both landed in `98ad03aa8`,
   the ADR-179 commit itself, so the citation is circular. This plan asserted it before
   measuring and is corrected here.
5. **Correct §R5's own wording** and retire it from "recorded, deliberately not fixed here"
   to done, with a pointer to this PR. R5 currently calls all four shipped sites
   "secret-handling gates whose exit code decides whether secrets are emitted"; that is false
   for `token-efficiency-report.sh`, which is an advisory cost report. Record the three
   classes from §Research Insights.
6. **Distinguish code root from data root** for the `compound` site, so the migration does
   not read as internally inconsistent: the code root moves to `${CLAUDE_PLUGIN_ROOT}`; the
   script-internal `TE_REPORT_REPO_ROOT` data root correctly stays git-root-defaulted,
   because the script measures the workspace. This is ADR-179 decision 3 applied honestly.
7. **Record that this subset needed no `safe-bash.ts` change**, so ADR-179's deferral
   reasoning (which cites the exact-literal edit as the blocker) is not read as blocking it.
8. **Record the Pattern C `preflight` sites** as a newly-identified residual — same threat
   shape, arguably RCE-class rather than gate-bypass — routed to #7453, with the note that
   their falsified rationale comment was corrected in this PR.

### ADR-093 §Amendment premise correction (AC #4)

**Partially done already; the body text is still wrong.** ADR-093's header block was updated
when ADR-179 landed and now states the premise is falsified. But the `## Amendments` body
still asserts it verbatim:

> The fallback branch **cannot** be made "fail-closed on unset" at the shell layer: it is the
> *correct, trusted* path for CLI/worktree/local-operator use (var legitimately unset,
> **git-root = the operator's own checkout**), and the shell cannot distinguish
> trusted-local-unset from untrusted-server-unset.

That paragraph is the one a reader reaches when following the `:-` guidance, and it is the
one AC #4 targets. The correction must (a) mark the parenthetical false and say why —
`review/SKILL.md` instructs `gh pr checkout`, after which git-root is the *contributor's*
checkout, and ADR-074 already models `contributor` as untrusted; (b) note that the claimed
impossibility ("cannot be made fail-closed at the shell layer") was resolved by ADR-179 not
at the shell layer but by removing the default arm entirely; (c) keep the surrounding
`#6223` export-invariant reasoning intact — it remains correct for the server surface.

**Do not rewrite ADR-093's Decision.** It is `Accepted` and its decision still holds; only
the Amendment's premise is falsified.

### C4 views

**No C4 impact.** Enumerated against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — read in
full rather than keyword-grepped, per the completeness mandate:

- **External human actors:** the change adds none. The untrusted `contributor` actor this
  threat model turns on is **already modelled** (ADR-074, `model.c4`) and its trust
  relationship to the reviewer is unchanged — this PR closes a path that violated the
  existing model, it does not alter the model.
- **External systems / vendors:** none added or removed. No new webhook, API, or store.
- **Containers / data stores:** none. The change edits markdown operands, a bash test, a
  vitest file, and two ADRs.
- **Actor↔surface access relationships:** none change. The plugin-payload↔CLI relationship
  is the same edge; only the *path expression* used to traverse it changes.
- **Element descriptions falsified by the change:** none found. No element description
  asserts an anchor form.

`/work` must re-read all three files and re-confirm this before concluding; the enumeration
above is the plan's evidence, not a substitute for that check.

### Sequencing

The amendment lands **in the same PR** as the migrations. The decision it records is not
conditional on anything this PR discovers — ADR-179 already made it — so there is no
adopting/accepted soak. Splitting would leave `main` carrying an ADR whose §R5 says the
subset is unfixed while the fix is merged.

**Ordinal note:** this PR creates **no new ADR ordinal**, so the collision class that hit
#7418 and #5990 does not apply. Both edits are to existing files.

## Guard Contract

### Guard 1 — secret-gate anchor guard (extends `plugin-root-anchoring.test.ts`)

**Property.** No invocation of a secret-gate script anywhere in plugin skill markdown
resolves its operand through a path the caller's working directory or git worktree controls.

**Assembly.** The chokepoint is the existing operand-extraction pass in
`apps/web-platform/test/plugin-root-anchoring.test.ts` — `RUNNER_RE` (command-position, which
already handles `cd x && bash foo` and `FOO=1 bash foo`) plus `DIRECT_EXEC_RE` (runner-less
`./x`). Today that pass is scoped to `plugins/soleur/commands/**/*.md`; the file's own
docstring names the skills corpus as "an open bypass of THIS guard, since moving a producer
into a SKILL.md escapes the scope below onto a surface that is equally customer-facing."

The extension must be **structural on both axes**, because a snapshot on either one is
invalidated by a one-line edit:

- *File axis:* enumerate **every** `plugins/soleur/skills/**/SKILL.md`, not the four known
  filenames. A fifth skill that pipes through `redact-sentinel.sh` must be caught.
- *Script axis:* derive the gate-script set as (a) every
  `plugins/soleur/skills/*/scripts/redact-*.sh` **discovered on disk**, plus (b) a closed
  extras constant `{ token-efficiency-report.sh }`. A newly added `redact-foo.sh` is then
  covered without editing the guard.

Both invocation regexes and the operand rule are reused unchanged from the command-surface
pass — one assembly, not two.

**Named residual (stated, not hidden):** a *new* gate script that is neither `redact-*` nor
in the extras constant is not auto-covered. Widening the extras constant is a reviewable
diff, which is the ADR-155 / ADR-179-decision-6 closed-vocabulary shape deliberately reused
here rather than a self-serve syntactic marker.

**Mutation matrix.** Derived from the design above, not from the implementation.

| # | Mutation | Must |
| --- | --- | --- |
| M1 | Revert `incident/SKILL.md`'s `SENTINEL=` to the `:-$(git rev-parse --show-toplevel)/plugins/soleur` form | RED |
| M2 | Change `linear-fetch/SKILL.md`'s operand to CWD-relative `bash scripts/redact-linear-urls.sh` | RED |
| M3 | **Second member after a compliant first** — add a new `plugins/soleur/skills/<new>/SKILL.md` invoking `redact-sentinel.sh` via `$(git rev-parse --show-toplevel)/…` while all four existing sites stay compliant | RED (proves the file axis quantifies over all SKILL.md, not the four it was written against) |
| M4 | **Own dispatch / anti-vacuity** — make the discovery pass yield zero gate invocations (point the scan root at an empty dir, or empty the extras constant) | RED via an explicit `scanned >= 5` floor. A guard reporting "0 checked" and exiting 0 is the defect this row exists for. |
| M5 | Add `skills/<x>/scripts/redact-newthing.sh` on disk and invoke it with a git-root anchor | RED (proves the script axis is derived, not a snapshot) |
| M6 | Wrap a compliant invocation as `cd /tmp && bash $(git rev-parse --show-toplevel)/…/redact-sentinel.sh` | RED (command-position, not line-start — the measured #7442 bypass) |

### Guard 2 — decoy positive control in `redact-sentinel.test.sh` (AC #5)

**Property.** The anchor literal **as committed** in the secret-gate SKILL.md files, expanded
in a session where `CLAUDE_PLUGIN_ROOT` is unset and the CWD is a git worktree the reviewed
party controls, does not resolve to a script inside that worktree.

**Assembly.** A single new test in
`plugins/soleur/skills/incident/test/redact-sentinel.test.sh`. The oracle is the **committed
SKILL.md text**, extracted at runtime — *not* a literal duplicated into the test. This is the
independent-producer requirement: a test that hardcodes its own expected anchor is a
set-difference over one producer and goes vacuous the moment someone edits both together.

Construction:

1. `mktemp -d`; `git init` it — this is the synthetic contributor tree.
2. Plant the decoy at `<tree>/plugins/soleur/skills/incident/scripts/redact-sentinel.sh`
   containing `#!/usr/bin/env bash` + `exit 0`, mode 0755.
3. **Prove the decoy is a live hazard** — invoke it directly on a file carrying a synthesized
   secret and assert it exits 0. A decoy that could not pass is not a positive control.
4. Extract the anchor expression from the committed `incident/SKILL.md`.
5. With `CLAUDE_PLUGIN_ROOT` unset and CWD inside the synthetic tree, expand the extracted
   expression.
6. Assert the resolved path is **not** under the synthetic tree.

**RED before / GREEN after (cq-write-failing-tests-before).** Before the migration the
extracted literal carries the git-root default, so step 5 resolves to the decoy and step 6
fails — the suite is RED and the test has demonstrated the actual vulnerability. After the
migration the literal is bare, expands to a root-anchored `/skills/…` path outside the
synthetic tree, and step 6 passes.

**Fixtures are synthesized only** (cq-test-fixtures-synthesized-only), and the secret's
literal form stays out of plan/ADR prose — the suite's existing in-file style
(`sk-`-shaped synthetic runs) is the precedent; GitHub push protection rejects literal
token shapes in prose regardless of allowlists.

**Test 18 is retargeted and STRENGTHENED, never deleted.** A naive `ANCHOR` swap preserves
only the weak property that two files agree, and leaves the corpus unguarded. Per
`cq-assert-anchor-not-bare-token` the replacement asserts **three** things:

1. **Coupling (preserved).** The bare literal appears exactly `1×` in each of
   `incident/SKILL.md` and `legal-generate/SKILL.md` — the existing fence.
2. **Identity preflight present at each gate site.** Anchor on something a comment cannot
   produce — the `grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"'` manifest check at the
   site — not on a bare token that prose could satisfy.
3. **Corpus-wide negative.**
   `grep -rF '${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)' plugins/soleur/`
   returns **zero**. This single assertion mechanically closes ADR-179 §R5 and stops the form
   reappearing *anywhere*, which per-file counts structurally cannot do.

| # | Mutation | Must |
| --- | --- | --- |
| M7 | Change the decoy from `exit 0` to `exit 2` | RED at step 3 — the hazard-liveness assertion |
| M8 | Revert `incident/SKILL.md` to the git-root form | RED at step 6 |
| M9 | Delete the anchor extraction and hardcode the bare literal in the test | RED — an added assertion must require the extracted string to be found in the committed file, so a test that stops reading its producer fails |
| M10 | Point Test 18's `ANCHOR` at the old literal while the SKILL.md files carry the new one | RED (count 0, not 1) |

## Observability

The gate fires on `apps/web-platform/test/**`, which is not one of the code-class paths that
mandate this section; it is included because the change alters a runtime security control on
observability layer 7 (ADR-171), where the CLI surface is not otherwise inspectable.

```yaml
liveness_signal:
  what: plugin-root-anchoring.test.ts gate-scope assertions + redact-sentinel.test.sh Tests 18/19
  cadence: every PR, and every full-suite run
  alert_target: CI red on the PR (blocking)
  configured_in: .github/workflows/ci.yml (vitest) and scripts/test-all.sh discovery (bash suite)
error_reporting:
  destination: CI job log; the bash suite's own FAIL lines and non-zero exit
  fail_loud: yes — redact-sentinel.test.sh ends `[[ "${FAIL}" -eq 0 ]]`, so any failure is a non-zero suite exit
failure_modes:
  - mode: a secret-gate site regains a git-root or CWD-shadowable anchor
    detection: Guard 1 operand rule over the structural file+script assembly
    alert_route: CI red, blocking merge
  - mode: the guard scans zero gate invocations and passes vacuously
    detection: Guard 1 M4 floor assertion (scanned >= 5)
    alert_route: CI red, blocking merge
  - mode: the two redact-sentinel call sites drift apart
    detection: Test 18 byte-identity count (1 in each)
    alert_route: CI red, blocking merge
  - mode: at runtime the plugin root does not resolve on a CLI or marketplace surface
    detection: the skill's existing `[[ -r "$SENTINEL" ]]` guard -> documented exit 2 with a named message
    alert_route: in-session operator-visible refusal. Layer 7 (ADR-171) residual — session-scoped, leaves no durable artifact after the session ends. This is the SAME gap ADR-179 records for SOLEUR_SYNC_ROOT_UNRESOLVED and tracks at #7452; this PR does not close it and does not widen it.
logs:
  where: CI job logs; in-session stderr for the runtime refusal
  retention: GitHub Actions default retention
discoverability_test:
  command: grep -Fc '${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh' plugins/soleur/skills/incident/SKILL.md plugins/soleur/skills/legal-generate/SKILL.md
  expected_output: "plugins/soleur/skills/incident/SKILL.md:1 and plugins/soleur/skills/legal-generate/SKILL.md:1"
```

No soak-gated or time-gated close criterion — the ADR is true at merge, so §2.9.1
follow-through enrolment does not apply.

## Implementation Phases

Ordering is dependency-directed: the contract-changing test lands before the migration it
verifies, so the RED/GREEN transition is observable (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (no edits)

1. Re-read all five sites; confirm they still carry the git-root form
   (`hr-always-read-a-file-before-editing-it`).
2. Re-run the Pattern A/B/C sweeps and confirm the counts in §Research Insights.
3. Re-read `apps/web-platform/server/safe-bash.ts` and re-confirm none of the three scripts
   is in `EXACT_LITERAL_SAFE_COMMANDS`. Confirm also that `SAFE_BASH_PATTERNS` contains no
   `bash <path>` regex at all — if so, all three scripts fall to the review gate both before
   and after migration, making the change behaviour-neutral on that surface under **either**
   branch of §R3.
4. Re-read all three `.c4` files and re-confirm the no-impact conclusion.
5. Confirm `plugins/soleur/skills/*/scripts/redact-*.sh` discovery returns the expected
   script set for Guard 1's script axis.
6. **Confirm `redact-sentinel.test.sh` actually executes in the run that will gate this PR.**
   It is discovered by the `plugins/soleur/skills/*/test/*.test.sh` glob in
   `scripts/test-all.sh`, but that runner also has a `skip_suite` relevance gate and
   `325a1a5c0` path-gated the heavy batteries. A P0 guard that fires only when
   `skills/incident/**` changes will not fire on a future `linear-fetch` or `preflight` edit.
   Verify which arm applies and record it; if it is path-gated, widen the predicate to the
   full gate-site set in this PR.

### Phase 1 — MEASURE: retire ADR-179 §R3 (must precede the amendment text)

Settle whether the plugin loader substitutes a **bare** `${CLAUDE_PLUGIN_ROOT}` inside a
```bash fence in **SKILL.md** text. Ship a throwaway skill whose fence prints its own
expansion, invoke it, and read the result. Record the exact artifact, invocation, and raw
output in the PR body.

- **Positive** (token substituted to the installed root) → §R3 is retired from "corroborated"
  to "proven"; proceed as planned and say so in the amendment.
- **Negative** (token reaches bash literally and expands empty) → **STOP and re-plan.** Under
  §R3a the chosen option's advantage over `:?` evaporates and the correct skills-surface
  decision may differ. Do not proceed to Phase 4 on a negative.

This is the one unknown gating a P0 secret gate, ADR-179 already named it a prerequisite for
the wider migration, and it is minutes of work.

### Phase 2 — RED: the decoy positive control

Add the Guard 2 test to `redact-sentinel.test.sh` per §Guard Contract. Run the suite and
**record the failure output in the PR body** — this is the evidence that the vulnerability
was real and the guard is not vacuous. Do not migrate anything yet.

### Phase 3 — RED: extend the anchor guard

Extend `plugin-root-anchoring.test.ts` to the structural gate assembly (Guard 1). Its
docstring's "DELIBERATELY OUT OF SCOPE" block must be updated in the same edit — the skills
bypass it names is exactly what this closes for the gate subset, and it must keep naming the
~105 non-gate sites still deferred to #7453. Run; record the failure.

### Phase 4 — GREEN: migrate the five sites, with guards

Per site, replace the git-root default with the bare anchor. **Payload-relative** — the root
already *is* `plugins/soleur`, so `${CLAUDE_PLUGIN_ROOT}/skills/…`, never
`${CLAUDE_PLUGIN_ROOT}/plugins/soleur/skills/…` (ADR-179: "the highest-frequency way to get
the migration wrong").

**The anchor swap is necessary and not sufficient at every gate site — each also gets the
ADR-179 decision-2 identity preflight** (manifest exists AND names `"soleur"`), because
`[[ -r ]]` is a shape check of the kind ADR-179 measured as bypassable.

1. `incident/SKILL.md` — `SENTINEL=` operand + identity preflight ahead of the existing
   `[[ -r ]]` guard (keep both; they catch different failures).
2. `legal-generate/SKILL.md` — same, ending byte-identical to (1).
3. `linear-fetch/SKILL.md` — operand **+ add the missing readability guard and exit-code
   dispatch**, which this site has never had. Empty stdout must not be persistable as "the
   redacted text". This is the largest behavioural change in the PR.
4. `compound/SKILL.md` — operand only. **Code root** moves to `${CLAUDE_PLUGIN_ROOT}`; the
   script-internal `TE_REPORT_REPO_ROOT` **data root** stays git-root-defaulted and must not
   be touched.
5. `incident/test/redact-sentinel.test.sh` — retarget Test 18's `ANCHOR` (see §Guard 2).

**Also correct the surrounding prose, which the brief does not list and a
bash-line-only sweep misses** (`cq-assert-anchor-not-bare-token`): `incident/SKILL.md`
currently reads "the platform-trusted copy; **git-root fallback for CLI/worktree**" and
`legal-generate/SKILL.md` reads "**falling back to the git-root for CLI/worktree**". Both
sentences document the removed vector as correct behaviour. Leaving them turns the migration
into a diff that contradicts its own file.

**Correct the falsified counter-argument in `preflight/SKILL.md`** (the comment above
`FORM_A_AWK`). Its premise — that `CLAUDE_PLUGIN_ROOT` is unset in a plain session — is true
and is ADR-179's own headline finding; its **conclusion**, resolving via git-root, is
ADR-179's explicitly-rejected option (d). Leaving a committed, well-reasoned argument
*against* the doctrine this PR ratifies is rule-corpus contamination: the next agent reads it
as authority and propagates it. **The comment correction is in scope even though the two
sites it guards are routed to #7453** (see §Decision Challenges). Do not migrate those two
operands here.

Verify the two suites now pass.

### Phase 5 — The ADR work

1. Amend ADR-179 per §Architecture Decision, as
   `## Amendment — 2026-08-12 (#7450): extend the canonical anchor to the skills secret-gate
   subset`. Keep `status: accepted`. **Edit §R5 in place** to record closure — an amendment
   that leaves R5 reading as an open deferral is how R5 gets re-worked by a future agent —
   and correct R5's false "all four are secret-handling gates" wording.
2. Correct ADR-093's `## Amendments` body paragraph per AC #4.

### Phase 6 — Downstream comments (no code)

1. **#7453** — comment with: the ratified anchor form; the corrected ordinal (**ADR-179**,
   not ADR-177 — its title carries the wrong number); confirmation that this subset shipped
   ahead and required **no** `safe-bash.ts` change, so that coupling blocks only the
   `list`/`ls` sites; and the two newly-found Pattern C `preflight/SKILL.md` unconditional
   git-root sites, flagged severity-above-baseline with their falsified rationale comment.
   Do not close.
2. **#6222** — comment re-scoping the remedy. Its current proposal
   (`$(git rev-parse --show-toplevel)/scripts/…` "with the same server-safety reasoning as
   the redaction gates") is **falsified**: that reasoning is precisely what #7450 removed.
   State the correct disposition: `${CLAUDE_PLUGIN_ROOT}` **cannot** anchor #6222's members
   because they are **repo-root `scripts/`** files that do not ship in the payload, so the
   remedy is one of ADR-179's two other instruments — **relocate into the payload** (the
   Decision-3 relocatability test: caller-supplied data root + code root moves atomically +
   all consumers repointed) or **gate behind the monorepo sentinel** (Decisions 4-6, with
   membership in `MONOREPO_ONLY_AREAS`). Note that its two cited `domain-model-drift.sh`
   sites are already remediated, and point at ADR-179 §R4's re-derived table as the live
   member list. Do not close.

### Phase 7 — Exit

Full `bash scripts/test-all.sh`. Then `/soleur:review` (with `user-impact-reviewer`, enrolled
by the `single-user incident` threshold), then `/soleur:ship`.

## Acceptance Criteria

Every grep needle containing `${…}` uses **`grep -F`** — `grep -c` on such a needle silently
returns 0 because `$`, `{` and `}` are not literal in BRE.

### Pre-merge (PR)

1. **AC1 — zero git-root defaults remain at gate sites.**
   `git grep -c ':-\$(git rev-parse' -- plugins/soleur/skills/` returns **1** hit, and that
   hit is the benign `worktree-manager.sh` `--git-common-dir` default. (Not 0: the benign
   site is deliberately retained.)
2. **AC2 — the bare anchor is present and byte-identical across the coupled pair.**
   `grep -Fc '${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh'` returns
   exactly `1` for **each** of `incident/SKILL.md` and `legal-generate/SKILL.md`.
3. **AC3 — no doubled payload segment.**
   `git grep -Fc '${CLAUDE_PLUGIN_ROOT}/plugins/soleur'` over `plugins/` returns **0**.
4. **AC4 — the other two gate sites migrated.** `grep -Fc` confirms the bare anchor in
   `linear-fetch/SKILL.md` (`redact-linear-urls.sh`) and `compound/SKILL.md`
   (`token-efficiency-report.sh`), 1 each.
5. **AC5 — prose corrected.** `git grep -niE 'git-root fallback|falling back to the git-root'
   -- plugins/soleur/skills/` returns **0**.
5a. **AC5a — corpus-wide negative.**
   `git grep -rF '${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)' -- plugins/soleur/`
   returns **0**, asserted by Test 18 itself and not only by a one-off command.
5b. **AC5b — §R3 measured, not argued.** The PR body carries the Phase 1 probe artifact, its
   invocation, and its raw output, with an explicit positive/negative verdict. The amendment
   cites that measurement and **does not** cite `preflight`/`review` as skills-surface
   evidence (`git grep -c 'preflight/SKILL.md' <ADR-179>` in an evidentiary context = 0).
5c. **AC5c — identity preflight at every gate site.** Each of `incident`, `legal-generate`
   and `linear-fetch` carries the ADR-179 decision-2 manifest+name check;
   `grep -Fc '"name"[[:space:]]*:[[:space:]]*"soleur"'` returns ≥1 in each of the three files.
5d. **AC5d — `linear-fetch` gained the guard it never had.** Its `persist_safe_summary`
   invocation performs a readability check and dispatches on exit code; empty stdout from an
   unresolved or failing scrubber cannot be returned as the persist-safe summary. Asserted by
   a test, not by inspection.
5e. **AC5e — `preflight/SKILL.md`'s falsified rationale comment corrected.** The comment no
   longer advocates git-root resolution. Its two operands are **unchanged** (routed to
   #7453), and the PR body says so explicitly so the omission reads as a decision.
5f. **AC5f — `compound`'s data root untouched.** `git diff` shows no change to
   `TE_REPORT_REPO_ROOT` or its default in `token-efficiency-report.sh`; only the SKILL.md
   code-root operand moved.
6. **AC6 — the decoy positive control was RED before the fix.** The PR body carries the
   captured Phase 2 failure output, and the test passes at HEAD.
7. **AC7 — Guard 1 mutation matrix.** Each of M1-M6 applied on a scratch copy drives the
   suite RED; each reverted returns it GREEN. Results recorded as a 6-row table in the PR
   body. **M4 (own-dispatch floor) and M3 (second member) are mandatory rows** — a matrix
   missing either does not satisfy this AC.
8. **AC8 — Guard 2 mutation matrix.** M7-M10 likewise, 4-row table.
9. **AC9 — Test 18 retained and retargeted.** The byte-identity coupling test still exists
   and asserts exactly 1 occurrence in each of the two files, against the new literal.
10. **AC10 — ADR-179 amended.** Contains the scope extension, the no-`safe-bash`-change
    finding, the fail-closed-asymmetry reasoning, the skills-surface substitution evidence,
    and §R5 retired with a pointer to this PR.
11. **AC11 — ADR-093 §Amendment corrected.** The `git-root = the operator's own checkout`
    parenthetical no longer asserts the false premise;
    `grep -Fc 'git-root = the operator' <ADR-093>` returns **0** in an asserting context, and
    the surrounding #6223 export-invariant reasoning is intact (spot-checked by reading, not
    by count).
12. **AC12 — no new ADR file.** `git diff --name-only origin/main...HEAD` shows **no added**
    file under `knowledge-base/engineering/architecture/decisions/`; both ADR paths appear as
    modifications only.
13. **AC13 — `safe-bash.ts` untouched.** It does not appear in
    `git diff --name-only origin/main...HEAD`.
14. **AC14 — AC #3 dispositioned, not silently dropped.** The PR body states
    `worktree-manager.sh` was verified already-satisfied by #7426, with the three-level
    anchor and the payload-file existence as evidence.
15. **AC15 — suite green.** `bash scripts/test-all.sh` passes, and the vitest file passes via
    `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
    (the package uses vitest, not `bun test`; the repo root declares no npm `workspaces`, so
    no `npm run -w` form).
16. **AC16 — downstream comments posted.** #7453 and #6222 each carry the Phase 5 comment and
    **both remain OPEN** (`gh issue view <n> --json state` returns `OPEN`).
17. **AC17 — `Closes #7450` in the PR body** (not the title).

### Post-merge (operator)

None. Every step above is automatable in-session via `gh` and the local suites; there is no
infrastructure, no credential mint, and no dashboard action in this change.

## Domain Review

**Domains relevant:** Engineering, Legal (advisory).

### Engineering

**Status:** reviewed — see §Architecture Decision and §Guard Contract. A CTO domain-leader
consult was run at plan time specifically to pressure-test the amend-vs-new-ADR instrument,
the §R3 substitution risk on the skills surface, the Pattern C routing decision, and the
`safe-bash.ts` no-change finding.

### Legal

**Status:** reviewed (assessment, no agent spawn required).
**Assessment:** `legal-generate/SKILL.md` is edited, but only its anchor operand and one
prose clause — no legal content, template, or disclosure changes. The change **strengthens**
an existing PII/secret-disclosure control and introduces no new processing activity, no new
data category, and no new recipient. No Article 30 register entry is created or modified. No
CLO escalation.

### Product/UX Gate

**Not applicable.** The mechanical UI-surface override did not fire: `## Files to Edit`
contains no path matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`,
and no UI-surface term. Tier **NONE** — this is an orchestration/security change with no
user-facing surface. `ux-design-lead` is therefore not required and does not appear in a
skipped-specialist list.

**Domains assessed and not relevant:** Finance, Sales, Marketing, Support, Operations.

## GDPR / Compliance Gate (Phase 2.7)

The canonical regulated-data regex does not match — no schema, migration, `.sql`, auth flow,
or API route is touched. Of the four expansion triggers, only (b) fires
(`single-user incident` threshold), so the gate is invoked at assessment level.

**Finding: compliance-positive, no action.** The change reduces the probability of
unauthorised disclosure of personal data and secrets by removing an attacker-controllable
path from a redaction control. It creates no new processing activity, no new LLM/external-API
data flow, and no new distribution surface. No Critical finding; nothing to write to
`compliance-posture.md`; no `compliance/critical` issue.

*Advisory only and not legal advice.*

## Gates Skipped (recorded so the next reader can see the check ran)

- **Phase 1.4 network-outage checklist** — no SSH/connectivity keyword; no `provisioner`
  block. Skipped.
- **Phase 1.8 skill-description budget** — no `description:` frontmatter is edited in any
  SKILL.md. Skipped.
- **Phase 2.8 IaC routing** — no server, service, secret, DNS record, cron, or vendor
  account. Skipped.
- **Phase 2.11 encryption posture** — no persistent store and no new cross-component
  connection. Skipped.

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | Decoy planted in a synthetic contributor tree; anchor extracted from the **pre-fix** `incident/SKILL.md`; `CLAUDE_PLUGIN_ROOT` unset; CWD inside the tree | Resolves **into** the tree → test RED. Demonstrates the live vulnerability. |
| T2 | Same, with the **post-fix** literal | Resolves outside the tree → GREEN |
| T3 | Decoy invoked directly on a synthesized-secret file | Exits 0 — proves the decoy is a real hazard, not an inert file |
| T4 | Guard 1 over the four migrated sites | PASS, and reports `scanned >= 5` |
| T5 | Guard 1 with the scan yielding zero invocations | RED on the floor assertion, never a silent pass |
| T6 | New SKILL.md added with a non-compliant gate invocation, all existing sites compliant | RED |
| T7 | New `redact-*.sh` added on disk and invoked non-compliantly | RED |
| T8 | `cd /tmp && bash $(git rev-parse …)/…/redact-sentinel.sh` (command-position bypass) | RED |
| T9 | Test 18 byte-identity across `incident` + `legal-generate` | 1 occurrence in each |
| T10 | Existing redact-sentinel behavioural tests (1-17) | Unchanged — the migration must not alter redaction semantics |
| T11 | `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts` | Green, command-surface assertions unaffected |
| T12 | `bash scripts/test-all.sh` | Green |

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| **The loader does not substitute a bare token in SKILL.md**, so the three skills refuse for the CLI operator | **Unknown — deliberately unquantified.** The one skills-surface evidence this plan first cited was measured circular (same commit as ADR-179) | **Phase 1 measures it before anything else**, and a negative result halts the plan rather than degrading it. This is the plan's single largest open unknown and it is retired first, not carried. Even on a positive, the refusal remains the *correct* failure for a secret gate. If it materialises, the remedy is a loader fix — **never** restoring the default arm. |
| **Anchor swapped without adding the identity preflight**, shipping half of ADR-179 | Medium — the anchor is the visible half of the change, and `[[ -r ]]` *looks* like a guard | ADR-179 measured a `test -d` shape check passing while a hostile payload executed. AC5c asserts the manifest+name check at all three gate sites; Guard 2's Test 18 assertion 2 anchors on it. |
| **`linear-fetch` migrated but left guardless**, so an unresolved root yields empty stdout that an agent persists as "the redacted text" | Medium — it is the only one of the three whose diff *looks* complete after a one-line swap | AC5d requires the readability check + exit-code dispatch, asserted by a test. Called out as the largest behavioural change in the PR so it is not treated as a one-liner. |
| **`compound`'s data root migrated along with its code root**, breaking a report that is *supposed* to measure the workspace | Medium — homogenising both roots is the natural reading of "migrate the site" | AC5f asserts `TE_REPORT_REPO_ROOT` and its default are untouched; the amendment records the two-root distinction explicitly. |
| **The P0 guard is path-gated** and never fires on a future `linear-fetch` or `preflight` edit | Medium — `325a1a5c0` path-gated the heavy batteries and `test-all.sh` has a `skip_suite` relevance arm | Phase 0 step 6 verifies which arm applies and widens the predicate to the full gate-site set in this PR if needed. |
| **A `/work` agent follows the superseded 2026-07-08 "preserve the exact original fallback anchor" learning** and keeps the git-root form, producing a green no-op PR | Medium — the learning is directly on-topic and reads authoritatively | Flagged in bold in §Research Insights; Guard 1 M1 makes preservation fail CI; AC1 asserts the residual count. |
| **Payload-relative path written as `${CLAUDE_PLUGIN_ROOT}/plugins/soleur/…`** — ADR-179 calls this the most frequent migration error | Medium | AC3 asserts 0 occurrences repo-wide. |
| **Test 18 deleted rather than retargeted**, dissolving the coupling fence between the two `redact-sentinel.sh` sites | Medium — deleting a failing pin is the path of least resistance | AC9 requires it to exist and assert 1-in-each; Guard 2 M10 drives it RED. |
| Guard 1's assembly implemented as a hardcoded four-file list | Medium | M3 and M5 are mandatory matrix rows and cannot pass against a snapshot. |
| Scope creep into #7453's ~105 sites or #6222's members | Low | Both are comment-only in Phase 5; AC16 requires both to stay OPEN. |
| The Pattern C `preflight` sites are read as in-scope and folded in | Low | Explicitly routed to #7453 with reasoning; not in `## Files to Edit`. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is
  filled with a concrete artifact and a concrete exposure vector.
- **`grep -c` on a `${…}` needle silently returns 0.** Every AC here uses `grep -F`. A
  verification that reports 0 is far more likely to be a BRE escaping bug than a real
  absence.
- **ADR-179 §R3's honesty is load-bearing — do not upgrade "corroborated" to "proven."** The
  new skills-surface evidence strengthens the corroboration; it is still not a direct
  measurement of a bare token in a SKILL.md bash fence under a controlled A/B. Record it as
  what it is.
- **#7453's GitHub title cites ADR-177, which is a different ADR.** Anyone working that issue
  from the title alone will read the test-runner taxonomy ADR and find nothing about anchors.
  The Phase 5 comment must correct it explicitly.
- The `worktree-manager.sh` `${_common_dir:-$(git rev-parse --git-common-dir …)}` hit is
  **not** a defect and must survive AC1. A sweep that drives the `:-$(git rev-parse` count to
  0 has broken worktree lease resolution.

## Decision Challenges

Two challenges were raised at plan time and recorded (headless arm — not asked) in
[`knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/decision-challenges.md`](../specs/feat-one-shot-7450-git-root-anchor-untrusted/decision-challenges.md);
`ship` renders them into the PR body and files an `action-required` issue.

- **DC-1 (user-challenge)** — whether the two `preflight/SKILL.md` git-root sites should be
  folded in. They are arguably RCE-class rather than gate-bypass-class, which outranks the
  five in-scope sites on severity; but their `gh pr checkout` reachability is unestablished.
  **The plan follows the operator's direction** (route to #7453) and folds in only the
  falsified rationale comment.
- **DC-2 (mechanical, applied)** — AC #1 asked for a decision ADR-179 had already made. The
  deliverable became an amendment rather than a new ADR; flagged so the reduced scope reads
  as a finding, not as an unmet acceptance criterion.

## Files to Edit

- `plugins/soleur/skills/incident/SKILL.md` — `SENTINEL=` operand + the "git-root fallback
  for CLI/worktree" prose clause
- `plugins/soleur/skills/legal-generate/SKILL.md` — `SENTINEL=` operand + the "falling back
  to the git-root" prose clause
- `plugins/soleur/skills/linear-fetch/SKILL.md` — the `persist_safe_summary` piped invocation
  **+ the readability guard and exit-code dispatch this site has never had** + identity
  preflight
- `plugins/soleur/skills/compound/SKILL.md` — the `token-efficiency-report.sh` invocation
  (**code root only** — the script's `TE_REPORT_REPO_ROOT` data root is not touched)
- `plugins/soleur/skills/preflight/SKILL.md` — **the falsified rationale comment above
  `FORM_A_AWK` only.** Its two git-root operands are deliberately NOT migrated here (DC-1)
- `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — retarget Test 18; add the
  Guard 2 decoy test
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — extend to the structural gate
  assembly; update the out-of-scope docstring
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`

## Files to Create

None.
