---
title: "/soleur:sync — plugin-root gate verifies identity but not freshness: a stale install passes, then dies on a bare ENOENT"
date: 2026-08-11
slug: fix-sync-producer-freshness-probe
branch: feat-one-shot-7474-sync-producer-freshness-probe
issue: 7474
closes: 7474
type: bug
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-179, ADR-171, ADR-155]
related: [7442, 7443, 7450, 7452]
---

> Spec lacks valid `lane:` — defaulted to `cross-domain` (fail-closed). No
> `knowledge-base/project/specs/feat-one-shot-7474-sync-producer-freshness-probe/spec.md`
> exists; this plan was entered directly from the issue.

## Overview

`/soleur:sync` Phase 0 verifies that the resolved plugin root is genuinely the Soleur
payload. That check answers *identity*, and it answers it correctly. It does not answer
*freshness*: a genuine Soleur install predating the producers the command invokes
satisfies every predicate the gate tests, so the run proceeds and the first producer
invocation fails as an unlabelled ENOENT with no marker and no diagnosis.

This plan guards each producer invocation at its own site, so a missing producer is **not
invoked at all** and surfaces as a named marker instead of a bare interpreter error. The
identity gate — and the whole Phase 0 fence — is left unchanged.

> **Note on revision.** A first draft placed the check in a Phase 0 loop and instructed the
> agent in prose to skip the affected area. A seven-reviewer panel converged against it: the
> guard was unenforceable across fences, fired false markers for areas the run never touches,
> and separated the guard from its invocation contrary to ADR-179 decision 5. The per-site
> form below is simpler *and* stronger. The rejected design is retained in
> `## Alternative Approaches Considered` because the reasoning is the deliverable.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the issue cites was checked against live state; all hold.

| Cited | Checked with | Result |
| --- | --- | --- |
| Issue #7474 | `gh issue view 7474 --json state` | **OPEN** — not already resolved. Labels `type/bug`, `priority/p2-medium`, `domain/engineering` confirmed. |
| #7442 (parent report) | `gh issue view 7442` | CLOSED — "4 of 8 areas unrunnable on a customer repo". |
| #7443 (the anchoring fix) | `gh pr view 7443` | **MERGED**. |
| Merge commit `98ad03aa8` | `git log -1 98ad03aa8` | Exists; is the #7443 squash merge. |
| ADR-179 | direct read | Exists at `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`, status `accepted`. Its identity-not-shape reasoning is quoted correctly by the issue. |
| The Phase 0 gate | direct read of `plugins/soleur/commands/sync.md` | Reproduces byte-for-byte what the issue quotes, at the `SOLEUR_ROOT_OK=0` anchor. |
| The `bun` toolchain probe idiom | direct read | Present at the `SOLEUR_SYNC_TOOLCHAIN_MISSING tool=bun` anchor, with the rationale the issue quotes. |

**Mechanism-vs-ADR check.** The proposed mechanism (a *separate* probe rather than an
extended gate) is not in any ADR's rejected-alternatives table. ADR-179 §Considered Options
rejects `:-` and `:?` anchor forms, not freshness probing. The issue's non-goal is aligned
with ADR-179 rather than in tension with it.

### Property List (Phase 0.6b)

- **P1** — When a producer the run will invoke is absent from the verified plugin root, the
  run emits a named, greppable marker rather than only a bare interpreter ENOENT.
- **P2** — The operator is told what to do about it (reinstall the plugin, not only update
  the marketplace) instead of reading the failure as "the c4 area is broken".
- **P3** — The probe's producer list cannot silently drift out of sync with the real
  invocation inventory in `sync.md`.
- **P4** — *(from the issue's optional variant)* The operator learns the install is behind
  the marketplace generally, including for producers added later.

### Cut List (Phase 0.6b)

| Mechanism | Property it buys | Disposition |
| --- | --- | --- |
| Per-site producer guard + named marker | P1 | **KEEP.** Nothing on `main` covers it. Grepped the authority (`grep -rn 'SOLEUR_SYNC_'` repo-wide): the only sibling probes are `SOLEUR_SYNC_ROOT_UNRESOLVED` (identity) and `SOLEUR_SYNC_TOOLCHAIN_MISSING tool=bun` (the `bun` **binary**, not the producer **files**). |
| Verbatim operator message | P2 | **KEEP** — `sync.md` already sets a verbatim-copy precedent for the sibling refusal, so the string is specified rather than improvised (D3). |
| Parity assertion pinning guarded sites + `affects=` values to the invocation inventory | P3 | **KEEP.** The existing suite's P2 asserts residency of *extracted* operands in this repo at CI time; nothing pins which invocations are guarded, nor the `affects=` value each carries. |
| `installed_plugins.json` `gitCommitSha` vs marketplace HEAD divergence warning | P4 | **CUT — deferred.** Rationale and evidence below. |

**Why P4's mechanism is cut.** Four measured reasons, not asserted ones:

1. **The install is not a git checkout.** `git -C ~/.claude/plugins/cache/soleur/soleur/0.0.0-dev rev-parse HEAD` → `fatal: not a git repository`. The only SHA source is `installed_plugins.json`.
2. **The marketplace checkout path is not derivable from the marketplace name.** The install's key is `soleur@soleur`, but there is no `~/.claude/plugins/marketplaces/soleur` directory; what exists is `jikig-ai-soleur` and `soleur.bak`. A hardcoded path would silently no-op or warn against the wrong tree.
3. **Divergence is not a defect.** A deliberately pinned install would emit the warning on every single run — the opposite of the toolchain-probe idiom the issue cites, which fires only when something the run actually needs is missing.
4. **It reads undocumented harness internals.** ADR-179 §R3 already records that the substitution mechanism is "CORROBORATED, not proven"; adding two more internal path dependencies widens that exposure behind a P2 bug fix.

Deferral lands as an appended item on **#7452** (OPEN — the existing consolidated tracker for
#7442 follow-ups, which explicitly filed six items as one issue "per the net-issue-flow
gate") rather than as a new issue.

### Consolidated findings

**Producer inventory — exactly 3 producers across 6 invocation sites** in
`plugins/soleur/commands/sync.md`, all bare-anchored and payload-relative:

| Producer | Invoked at (content anchor) |
| --- | --- |
| `scripts/generate-c4-from-components.ts` | the C4 area's `bun "${CLAUDE_PLUGIN_ROOT}/scripts/generate-c4-from-components.ts"` |
| `scripts/write-kb-coverage.ts` | the Coverage Summary block, plain and `--degraded "<reason>"` forms |
| `scripts/domain-model-drift.sh` | the domain-model area's `drift`, `write-row`, and `init` subcommands |

This matches the issue's proposed list exactly. All three exist under
`plugins/soleur/scripts/` today.

**Marker vocabulary and the absence of a registry.** Repo-wide grep finds five markers:
`SOLEUR_SYNC_ROOT_UNRESOLVED`, `SOLEUR_SYNC_TOOLCHAIN_MISSING`, `SOLEUR_SYNC_AREA_UNAVAILABLE`
(emitted in `sync.md`; the last is consumed by `apps/web-platform/test/plugin-root-anchoring.test.ts`
and `tests/commands/test-sync-producer-reachability.sh`), plus `SOLEUR_KB_SYNC_PRODUCERS` and
`SOLEUR_KB_SYNC_ERROR` defined as constants in `plugins/soleur/lib/kb-coverage.ts`. **There is
no registry, allowlist, or validator of marker names.** A new marker is therefore inert
unless a test explicitly asserts it — which makes the test the delivery mechanism, not a
nicety.

**The house `reason=` convention states an observation, never a cause.** Both existing
`reason=` tokens do this: `reason=plugin-root-unverified` (what failed to verify) and
`reason=monorepo-only-maintenance-area` (a structural fact). `reason=stale-install` would be
the first token in the file to name a *causal hypothesis*. This is the plan's central
correction to the issue's literal proposal — see the hypothesis table below.

**A durable-artifact path already exists and is reusable.** `write-kb-coverage.ts` accepts a
repeatable `--degraded "<reason>"` and renders it into `knowledge-base/project/kb-coverage.md`.
`sync.md` already instructs: *"Add one `--degraded "<reason>"` for each producer that reported
`status=degraded` earlier in the run (the `reason=` token from its marker is the right
string)."* A well-formed `reason=` token therefore feeds an existing durable sink for free —
partially addressing the layer-7 durability gap ADR-179 §Consequences records as **not**
closed (tracked in #7452). Caveat: unavailable when `write-kb-coverage.ts` is itself the
missing producer.

**Applicable institutional learnings.**

- `knowledge-base/project/learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md`
  — every defect there was "an assertion that certifies a property adjacent to the one it
  names". Directly on point for `reason=stale-install`: the probe observes absence and names
  a cause. Prefer facts over diagnosis in the token.
- `knowledge-base/project/learnings/2026-07-29-a-per-producer-fix-left-seven-siblings-live-and-four-misread-signals.md`
  — "make the enumeration a test — a parity test that reads the class table and asserts
  set-equality, so shell table and code cannot drift apart silently." This is the shape of
  the P3 assertion.
- `knowledge-base/project/learnings/2026-04-29-bind-mount-seed-detection-needs-late-sentinel.md`
  — a manifest/identity check passes while the payload is partially present. The exact shape
  of #7474.
- `knowledge-base/project/learnings/2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md`
  and `.../2026-05-22-ac-self-grep-hazard-and-git-grep-pathspec-ordering.md` — an
  absence-grep AC false-fails when the searched scope legitimately documents the token. This
  plan's ACs assert **presence of the guardrail**, never absence of a token that `sync.md`
  and this plan both legitimately contain.
- `knowledge-base/project/learnings/2026-05-25-multi-agent-review-catches-stale-precedent-grep-and-unreachable-ux-toast.md`
  — plan-time enumerations decay; re-derive at review. Applied: the producer count is
  re-derived by the parity assertion at test time, never trusted from this document.
- `knowledge-base/project/learnings/2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md`
  — an issue's diagnosis and its proposed remedy are *independent* claims, and the second is
  the one nobody re-checks. Applied directly: this plan measured the issue's quoted symptom
  (see the measurement table above) instead of inheriting it, and that measurement is what
  produced the `reason=` correction.

**Artifact-path verification.** `knowledge-base/project/kb-coverage.md` is cited as the
durable sink. Confirmed from the producer itself, not from prose:
`plugins/soleur/scripts/write-kb-coverage.ts` sets `OUT_REL = "project/kb-coverage.md"` and
joins it to the KB root. The file is absent from the tree because it is generated output, not
a committed source.

**Prior art.** `knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md`
(the #7442/#7443 plan) established the mechanical, grep-based AC style this plan matches, and
made the reachability suite the "decisive cell". It did not anticipate the freshness axis.

**CLAUDE.md / AGENTS.md conventions in force.** `cq-test-fixtures-synthesized-only` (the
reachability suite synthesizes its fixtures), `cq-assert-anchor-not-bare-token`,
`cq-cite-content-anchor-not-line-number`, `hr-verify-repo-capability-claim-before-assert`,
and `wg-architecture-decision-is-a-plan-deliverable`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| *(issue)* A stale-but-authentic install passes the gate, then the first producer ENOENTs. | Reproduces as described **given** that the executing `sync.md` references a producer the root lacks. But `commands/` and `scripts/` ship in **one payload at one SHA** (measured: the install holds both and is not a git checkout), so a merely-old install runs its *own* old `sync.md`, whose producer list matches its own `scripts/`. | Keep the fix — it is correct and cheap under either reading — but do **not** encode `stale-install` as fact in the marker. Recorded as an open hypothesis below. |
| *(issue)* `reason=stale-install` is the right token. | Both existing `reason=` tokens in `sync.md` state an observation, not a cause. | Emit `reason=absent-from-plugin-root`. Move the stale-install hypothesis and the remedy into the agent's report prose, where a hypothesis belongs. |
| *(research agent)* "No existing test verifies referenced scripts exist on disk." | **Falsified by direct read.** `plugin-root-anchoring.test.ts` P2 already runs `existsSync(resolve(PAYLOAD_ROOT, rel))` on every anchored operand. | Do not build a residency guard — it exists. Build only the *parity* guard P2 cannot provide (next row). |
| P2 therefore already guards the probe's list. | **No.** P2 only sees operands `extractOperands` returns, and both `RUNNER_RE` and `DIRECT_EXEC_RE` require either a runner token (`bash\|bun\|node\|sh\|…`) or a `./` prefix in command position. A `[ -f "${CLAUDE_PLUGIN_ROOT}/$p" ]` line has neither. | The probe's list is invisible to the existing suite in **both** directions: it will not false-fail P2, and it gains no drift guard. A new parity assertion is required. |
| *(research agent)* "No `bunfig.toml` pathIgnorePatterns override relevant to sync." | **Falsified by direct read.** `apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]`, blocking all `bun test` discovery in that package (#1469). | Every AC touching `plugin-root-anchoring.test.ts` uses **vitest**, never `bun test`. |
| *(research agent)* the prior plan lives under `.worktrees/feat-one-shot-guard-contract-assembly/…`. | That is a *different* worktree. The file is present in this worktree at `knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md`. | Cite the in-worktree path only (`hr-when-in-a-worktree-never-read-from-bare`). |

### Hypotheses — what the probe actually catches

The issue's causal story is **not fully settled by repo evidence**, and this plan does not
pretend otherwise. The remedy is identical under every branch; only the marker's `reason=`
token depends on which is true, which is why the token states the observation.

| # | Hypothesis | Verdict | Basis |
| --- | --- | --- | --- |
| H1 | An **incomplete or corrupted payload** (interrupted install, packaging change dropping a file) leaves a producer absent from an otherwise-valid root. | **PLAUSIBLE** | Structurally possible for any copied payload; the identity gate cannot see it. This is the case the probe unambiguously converts from a bare ENOENT into a named marker. |
| H2 | A **split** between the instruction source and the payload root — the executing `sync.md` is fresher than `${CLAUDE_PLUGIN_ROOT}`. | **PLAUSIBLE, and consistent with the report** | The reporter observed `SOLEUR_ROOT_OK=1` — a gate that only exists post-#7443 — while `installed_plugins.json` recorded a pre-#7443 SHA. Multiple `sync.md` copies coexist on the reporting machine (the monorepo's own, `marketplaces/jikig-ai-soleur`, `marketplaces/soleur.bak`, and the install). |
| H3 | A **merely old install** (nothing else diverging) triggers it. | **UNKNOWN — probably cannot** | `commands/` and `scripts/` ship together at one SHA, so an old install's own `sync.md` should reference only producers it carries. Not refuted outright: the exact copy Claude Code loads a project-scoped command from was not established this session. |

**Cheap probe for `/work` to settle H3, if desired:** from a customer repo with a
deliberately-pinned older install, run `/soleur:sync` and compare the executing gate text
against `<installPath>/commands/sync.md`. This is diagnostic only — **no acceptance criterion
depends on it**, and the fix ships regardless.

### Measured: what a missing producer actually prints

The issue quotes the symptom as `bun: no such file or directory: .../scripts/generate-c4-from-components.ts`.
That string was **not reproduced**. Measured against `bun 1.3.11`:

| Case | Command | Actual output |
| --- | --- | --- |
| A — runner present, script absent | `bun /tmp/missing.ts` | `error: Module not found "/tmp/missing.ts"` |
| B — runner absent | `bun …` with `bun` off `PATH` | shell-level `command not found` (the axis the existing `bun` probe already covers) |
| C — bash runner, script absent | `bash /tmp/missing.sh` | `bash: /tmp/missing.sh: No such file or directory` |

Two consequences, both load-bearing:

1. **The quoted string most closely matches case C, not case A.** `<runner>: <path>: No such
   file or directory` is the *shell* runner's shape. `sync.md` invokes
   `domain-model-drift.sh` through `bash`, so the reported symptom is at least as consistent
   with the domain-model producer as with the c4 producer. The plan therefore does **not**
   treat "c4 was the failing producer" as established, and covers all three producers
   symmetrically.
2. **The defect the issue reports is real under both runners regardless.** Cases A and C
   both emit an unmarked, unattributed error. That — not the exact wording — is what the
   probe fixes, and it is confirmed by measurement rather than inherited from the report.

This is recorded because the plan's justification must rest on what was measured. Nothing
below depends on which producer the reporter actually hit.

## Deepening Verification

Run after the seven-reviewer panel, against the **redesigned** (per-site) form. Every claim below
was executed, not reasoned.

### The redesign's central claim, verified empirically

Ran the file's real `RUNNER_RE` and `DIRECT_EXEC_RE` against the guard form:

| Line of the guard | Operands extracted |
| --- | --- |
| `[ -f "${CLAUDE_PLUGIN_ROOT}/scripts/…ts" ] \` | none |
| `  && bun "${CLAUDE_PLUGIN_ROOT}/scripts/…ts" \` | **one** — `"${CLAUDE_PLUGIN_ROOT}/scripts/generate-c4-from-components.ts"` |
| `  \|\| echo "SOLEUR_SYNC_PRODUCER_MISSING …"` | none |

That single operand is **anchored** (P1 ✓), **quoted** (P1c ✓), payload-relative and resident
(P2 ✓ — P2's `existsSync` covers it for free), and the block contains no `:-`/`:?` (P1b ✓).

Two consequences worth stating:

1. **The existing suite covers the guard automatically.** The rejected Phase-0-probe form
   extracted *nothing* and would have introduced an anchored-operand class no assertion touched.
   The per-site form is the only one of the two that the guard suite can see.
2. **The extracted-operand count per site is unchanged** (one, exactly as today's bare `bun "…"`
   line), so P3's per-file invocation floor is unaffected by the edit.

### Gate results

| Gate | Result |
| --- | --- |
| 4.6 User-Brand Impact | PASS — section present, threshold `single-user incident`, worst-case enumerated |
| 4.7 Observability | PASS — all five fields non-placeholder; `discoverability_test.command` starts with `bash` (allowlisted) and contains no `ssh` |
| 4.8 PAT-shaped variable | PASS — no match |
| 4.5 Network-outage | Skipped — the two keyword hits are a learning *filename* and the phrase "unreachable past the gate's `exit 1`"; neither is a network symptom |
| 4.55 Downtime & cutover | Skipped — no reboot/replace, lock-taking DDL, or router change |
| 4.9 UI wireframe | Skipped — no UI-surface path in Files to Edit |
| 4.10 Encryption posture | Skipped — no persistent store or cross-component connection |
| 4.4 Precedent diff | The guard reuses the `bun`-probe marker idiom already in `sync.md`; ADR-179 decision 5 supplies the fail-closed-in-isolation precedent the per-site form satisfies |

### Citation sweep

All seven AGENTS rule IDs cited in this plan resolve to active `[id: …]` entries in `AGENTS.md`
(`cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`,
`cq-test-fixtures-synthesized-only`, `hr-verify-repo-capability-claim-before-assert`,
`hr-when-a-command-exits-non-zero-or-prints`, `hr-when-in-a-worktree-never-read-from-bare`,
`wg-architecture-decision-is-a-plan-deliverable`) — no retired or fabricated IDs. Every
`knowledge-base/` path cited resolves on disk. Every issue and PR number was checked live
(#7442 CLOSED, #7443 MERGED, #7450 OPEN, #7452 OPEN, #7474 OPEN). No new ADR ordinal is claimed.

**AC self-grep scope:** the one negative grep in the ACs is scoped to
`plugins/soleur/commands/sync.md`, not the repo — this plan and
`decision-challenges.md` both legitimately contain the rejected `reason=stale-install`
token, so a wider scope would self-fail.

## Design Decisions

A seven-reviewer panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO,
CTO) converged on a **simpler and stronger** design than this plan's first draft. The draft put
the check in a Phase 0 loop and then instructed the agent, in prose, to skip the affected area.
That is recorded here as rejected, because the reasoning is the deliverable.

### D1 — the guard is per-invocation-site, not a Phase 0 loop

**Each producer invocation guards itself, in its own subprocess:**

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/scripts/generate-c4-from-components.ts" ] \
  && bun "${CLAUDE_PLUGIN_ROOT}/scripts/generate-c4-from-components.ts" \
  || echo "SOLEUR_SYNC_PRODUCER_MISSING producer=scripts/generate-c4-from-components.ts affects=c4 reason=absent-from-verified-root"
```

This is **enforcement, not instruction-following**: the guard and the invocation share a
subprocess, so a missing producer cannot be invoked. The rejected Phase-0-loop design could only
*ask* the agent, three phases later, not to invoke it — and the plan had to concede that a
marker above a bare death is still a bare death.

It also aligns with **ADR-179 decision 5**, which the first draft never cited and which is
directly on point: *"the gated invocation must be fail-closed in isolation … if the invocation
line is ever separated from its gate … the variable is unset."* A guard sitting ~700 lines and
several phases upstream of its invocation, with an LLM as the structure-preserving consumer, is
exactly the separation decision 5 rejects.

Five further problems dissolve rather than needing fixes:

| Dissolved | Why |
| --- | --- |
| False markers on an unrelated area | The Phase 0 loop ran *before* area dispatch, so `/soleur:sync conventions` — which invokes no producer — would emit up to three alarming lines and then succeed. A per-site guard only runs when the site is reached. |
| The unenforceable skip contract | Nothing to instruct; the guard *is* the skip. |
| An unguarded operand class inside the guarded file | `[ -f … ]` alone is invisible to both extractors. `&& bun "…"` is runner-prefixed, so the existing P1 / P1b / P1c / P2 assertions cover the operand automatically. |
| `exit 0` + the STOP-prose retarget | No Phase 0 fence edit at all, so the ADR-179 refusal instruction and both of its stop signals stay untouched. |
| A new whole-fence test extractor | `T0c` already extracts and executes every invocation with the root unset. |

### D2 — the marker states the observation, never the cause

```text
SOLEUR_SYNC_PRODUCER_MISSING producer=<payload-relative-path> affects=<area> reason=absent-from-verified-root
```

`reason=stale-install` is rejected. The guard observes only that a path is absent under a root
the identity gate already verified; staleness is an inference, and per H3 it is the *least*
reachable of the three generators. `producer=` and `affects=` mirror the sibling
`SOLEUR_SYNC_TOOLCHAIN_MISSING tool=bun affects=c4,coverage`. `reason=` matches the two other
markers in the file, both of which name observations.

**Grammar:** `affects=` is a comma-joined list (the sibling already emits `affects=c4,coverage`),
single-valued for all three producers today. Values are drawn from the closed set
`{c4, coverage, domain-model}`.

**Capability claim withdrawn.** The first draft justified this token partly by "the marker is
parsed by an agent that files GitHub issues." Grepped per `hr-verify-repo-capability-claim-before-assert`:
**no such consumer exists.** `SOLEUR_SYNC_` appears only in `sync.md`, the two test suites,
ADR-179, and this plan. The token discipline stands on its own merit — an operator reads these
lines — but the auto-filing rationale is dropped as unverified.

### D3 — the operator-facing message states the observation, offers a remedy, and names a fallback

The first draft applied de-causalization rigor to the machine token and left the human sentence
asserting the same unproven cause as its sole instruction. Under H1 (torn payload) reinstalling
reproduces the same payload, the remedy fails, and a founder who followed Soleur's own
instruction learns its diagnostics lie — worse than a bare error, which merely puzzles.

`sync.md` sets a precedent of **verbatim** operator copy for the sibling refusal, so this plan
specifies the string rather than leaving it to improvisation:

> Soleur couldn't find one of its own files (`<producer>`), so the `<area>` step didn't run.
> This is a problem with the Soleur installation, not with your project. The most likely fix is
> to reinstall the Soleur plugin — updating the marketplace alone does not update an installed
> plugin. If that doesn't clear it, this is a bug in Soleur: please report it with this line.
> Everything else in this run completed normally.

Four required properties: observation before cause; a concrete remedy; an explicit fallback when
the remedy does not work; and what still succeeded. No internal vocabulary ("producers"), and no
unproven "predates" as the sole instruction. Per the brand guide's tone rows for error messages
and non-technical founders.

**Headless variant.** `apps/web-platform/server/auto-sync-trigger.ts` fires
`/soleur:sync --headless` as the post-clone auto-sync for web-platform users, who have **no
plugin installed** — "reinstall the plugin" is actively misdirecting there. The headless arm
reports the missing file as a Soleur-side defect with no operator action.

### D4 — the stronger SHA-divergence variant is deferred; the user pain is filed separately

Deferring the *mechanism* is right (four measured reasons in the Cut List, plus: it reads two
paths **outside** the verified root, the hand-resolution class ADR-179 exists to forbid).

But the mechanism and the pain are different things. "Updating the marketplace does not update
an installed plugin, and nothing says so" is a defect in the **update path**, unaffected by this
guard. Filing it onto #7452 (milestone *Post-MVP / Later*, 1027 open issues) is indistinguishable
from not filing it. So: the mechanism stays deferred on #7452; the update-path UX defect is filed
as its own issue in the **Phase 4: Validate + Scale** milestone.

### D5 — the `--degraded` carry-forward is reuse, not a deliverable

`sync.md` already instructs one `--degraded "<reason>"` per producer reporting `status=degraded`,
and already says the marker's `reason=` token is the right string. A well-formed `reason=`
therefore reaches `knowledge-base/project/kb-coverage.md` for free. One sentence, no new
mechanism. Two limits recorded once, not six times: it is unavailable when
`write-kb-coverage.ts` is itself the missing producer, and for any standalone invocation
(standalone areas do not write coverage). A prior `kb-coverage.md` also survives on disk and will
still satisfy the existing `SOLEUR_KB_SYNC_PRODUCERS` grep, so that grep certifies the previous
run — stated so a reader does not mistake it for current health.

## User-Brand Impact

**If this lands broken, the user experiences** one of three things, worst first:

1. **A confidently wrong remedy.** The marker fires and the message names a cause that is not
   theirs, so the fix fails and trust burns. This is worse than today's bare error, and it is why
   D2 and D3 both refuse to assert an unmeasured cause.
2. **A silently skipped area.** A typo'd or omitted `affects=` value names an area no prose knows
   about, or a mis-scoped guard suppresses a step that would have worked.
3. **A false marker against a healthy install** — the failure mode the rejected Phase-0-loop
   design would have produced on every `/soleur:sync conventions` run.

**If this leaks, the user's data is exposed via:** no new exposure. The guard reads only file
*existence* under a root the identity gate already verified, and emits payload-relative paths
that are public plugin content. No new file read, network call, or secret handling.

**Threat-model scope.** The first draft claimed "the threat model is untouched" while also
retargeting ADR-179's STOP prose. That retarget is now cut (D1), the Phase 0 fence is not edited
at all, and both stop signals survive — so the claim is now true as stated rather than
under-scoped.

**Brand-survival threshold:** `single-user incident`. `/soleur:sync` is the first-run experience
of the only surface with a live user, while Phase 4 recruits nine more founders. A non-technical
founder who hits an unattributed error does not file a bug — they churn silently.

`requires_cpo_signoff: true`. CPO returned **APPROVE WITH CHANGES**; every required change is
folded above (D3's message, D4's split filing, the User-Brand enumeration, the withdrawn
threat-model claim) or into the ACs below.

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review`-labelled issues (`gh issue list --label code-review
--state open --json number,title,body --limit 200`), then `jq --arg path … | contains($path)` for
each planned file. Zero matches.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

1. Re-derive the producer inventory at HEAD:
   `grep -nE '(bash|bun) "\$\{CLAUDE_PLUGIN_ROOT\}/' plugins/soleur/commands/sync.md`.
   Expect 3 distinct paths across 6 sites; a fourth changes the work-list.
2. Read **both** hand-ratcheted anti-vacuity floors — this is the single most certain
   work-phase pivot if missed:
   - `apps/web-platform/test/plugin-root-anchoring.test.ts` → `expect(assertions).toBe(8)` (8 `seen()` calls).
   - `tests/commands/test-sync-producer-reachability.sh` → `EXPECTED_CASES=9`, enforced twice.
3. Confirm both suites green before editing:
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
   and `bash tests/commands/test-sync-producer-reachability.sh`.

### Phase 1 — RED

1. Add the marker-emission case to `tests/commands/test-sync-producer-reachability.sh`: a
   synthesized root that is identity-valid but missing one producer, asserting the exact marker.
   **Fixture precondition:** the root must still contain an (empty) `scripts/` directory, or the
   identity gate refuses first and the case tests nothing.
2. Bump `EXPECTED_CASES` by exactly the number of cases added.
3. Add the **P6** parity assertion to `apps/web-platform/test/plugin-root-anchoring.test.ts`:
   - **Insert the `it()` block ABOVE the P5 block.** `assertions` increments inside each
     callback in registration order, so appending after P5 leaves P5 reading the pre-increment
     value and failing while P6 passes.
   - **Scope the expected set to `sync.md`'s entry only** — `parse()` walks all of
     `plugins/soleur/commands/`, and `go.md` contributes two anchored `.sh` operands that would
     otherwise be demanded of `sync.md`'s guard list.
   - Restrict to operands invoked by `bash`/`bun` in command position, not to any `.ts`/`.sh`
     suffix — `source` is in `RUNNERS`, so a future `source "…/lib/x.sh"` would false-fail.
   - Assert every guarded invocation's `affects=` value is in the closed set
     `{c4, coverage, domain-model}`.
   - **Non-vacuity:** assert both derived sets are non-empty (`>= 3`) before comparing; `∅ == ∅`
     is otherwise green if the parser stops matching.
   - **Remedy-bearing failures**, matching the file's house idiom (`expect(violations).toEqual([])`
     with self-describing elements): `PRODUCER NOT GUARDED: scripts/x.ts — wrap its invocation in
     the [ -f ] guard in plugins/soleur/commands/sync.md`.
   - Scope the parser to fence bodies. `sync.md`'s Phase 0 prose contains ADR-179's worked
     examples (`"${CLAUDE_PLUGIN_ROOT}/scripts/foo.ts"`); a section-scoped parser ingests them,
     goes red, and the shortest fix under pressure is deleting the ADR documentation.
4. Bump `expect(assertions).toBe(8)` → `toBe(9)`.
5. Confirm both suites RED for the right reason.

### Phase 2 — GREEN

1. Wrap each of the 6 producer invocations in `plugins/soleur/commands/sync.md` in the D1 guard
   form, with its `affects=` value.
2. Add the D3 verbatim operator message and its headless variant.
3. Add the D5 one-sentence `--degraded` note with its two limits.
4. Add a pointer comment above the first guarded invocation naming both test suites, so the next
   maintainer learns what goes red. (`sync.md` already links a test file in the domain-model
   section — established idiom.)
5. Keep `domain-model`'s two contracts distinct in the report: standalone is terminal, under
   `all` it feeds the coverage summary.

### Phase 3 — ADR amendment

One line added to ADR-179's `## Consequences` marker enumeration, plus a short note on whether
decision 5's fail-closed-in-isolation principle binds the freshness axis — it does, and D1 is
the reason the guard is per-site. Without that note ADR-179 reads as silently self-contradicting.

### Phase 4 — Deferral, filing, exit gate

1. Append the D4 mechanism deferral to #7452 with re-evaluation criteria.
2. File the update-path UX defect as its own issue in the **Phase 4: Validate + Scale** milestone.
3. Assign #7474 to the Phase 4 milestone (currently unset).
4. `bash scripts/test-all.sh`.

## Files to Edit

| File | Change |
| --- | --- |
| `plugins/soleur/commands/sync.md` | Wrap 6 producer invocations in the per-site guard; add the verbatim operator message + headless variant; the `--degraded` note; the test-suite pointer comment. **The Phase 0 identity-gate fence is not edited.** |
| `apps/web-platform/test/plugin-root-anchoring.test.ts` | Add P6 (scoped, non-vacuous, remedy-bearing, `affects=` closed-set) **above** P5; bump the floor 8 → 9. |
| `tests/commands/test-sync-producer-reachability.sh` | Add the marker-emission case; bump `EXPECTED_CASES` by the number added. |
| `knowledge-base/engineering/architecture/decisions/ADR-179-…md` | One-line marker-enumeration addition + the decision-5 scope note. |

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — the guard prevents invocation and emits the marker.** The new reachability case is
   green, and goes RED when the guard is removed from a site. Verified by running the suite, not
   by grepping prose.
2. **AC2 — the marker's shape is exact.** The emitted string carries `producer=`, `affects=`, and
   `reason=absent-from-verified-root`, asserted against the emitted output. Includes
   `! grep -Fq 'reason=stale-install' plugins/soleur/commands/sync.md` — the runnable negative
   form, since `grep -c` prints `0` but **exits 1**, which reads as a failed AC under
   `hr-when-a-command-exits-non-zero-or-prints`.
3. **AC3 — parity holds and cannot be vacuous.** P6 is green; both derived sets are non-empty;
   every `affects=` value is in the closed set. Shown RED under two mutations: a guarded
   invocation whose `affects=` is typo'd, and a new producer invocation left unguarded.
4. **AC4 — both anti-vacuity floors were bumped.** `expect(assertions).toBe(9)` and
   `EXPECTED_CASES` raised by the number of cases added; both suites green.
   **vitest, never `bun test`** (`apps/web-platform/bunfig.toml` sets `pathIgnorePatterns = ["**"]`).
5. **AC5 — the operator message is present and carries all four properties.** Asserted as
   presence of content anchors for: the missing filename, "not with your project", the reinstall
   remedy, and the report-it fallback. Never as absence of a token.
6. **AC6 — the pre-existing anchoring assertions still hold and the extractors are untouched.**
   `git diff main...HEAD -- apps/web-platform/test/plugin-root-anchoring.test.ts | grep -E '^[+-][^+-]' | grep -E 'RUNNERS|RUNNER_RE|DIRECT_EXEC_RE'`
   returns nothing. (`git diff` with no range shows only the working tree and is vacuously green
   after a commit.)
7. **AC7 — full suite green.** `bash scripts/test-all.sh`.
8. **AC8 — tracking is real.** #7452 carries the deferred mechanism; the update-path UX defect is
   filed in the Phase 4 milestone; #7474 is assigned to Phase 4. All linked from the PR body,
   which uses `Closes #7474`.

### Post-merge (operator)

None. Every step is automatable in-session.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_SYNC_PRODUCER_MISSING on /soleur:sync stdout when a producer is absent from the verified plugin root"
  cadence: per /soleur:sync invocation (operator-initiated; no schedule)
  alert_target: none — operator-facing stdout, plus a durable degraded row in knowledge-base/project/kb-coverage.md via the existing write-kb-coverage.ts --degraded path
  configured_in: plugins/soleur/commands/sync.md (per-invocation guards)
error_reporting:
  destination: run stdout, read by the invoking agent and rendered as the D3 operator message; durably, the kb-coverage.md degraded row
  fail_loud: true — the guard emits on every absent producer and structurally prevents the invocation
failure_modes:
  - mode: a producer is absent from an otherwise-valid plugin root
    detection: the per-site guard emits SOLEUR_SYNC_PRODUCER_MISSING and skips the invocation
    alert_route: D3 operator message in-session; kb-coverage.md degraded row when the coverage producer is present
  - mode: write-kb-coverage.ts is itself the missing producer, or the run is a standalone area
    detection: same marker, affects=coverage
    alert_route: stdout only — no durable channel by construction; a prior kb-coverage.md persists and still satisfies the existing SOLEUR_KB_SYNC_PRODUCERS grep, so that grep certifies the previous run
  - mode: the plugin root does not verify at all
    detection: pre-existing SOLEUR_SYNC_ROOT_UNRESOLVED; guards are unreachable past the gate's exit 1
    alert_route: pre-existing fatal path, unchanged — the Phase 0 fence is not edited
  - mode: a guard list or affects= value drifts from the real invocation inventory
    detection: P6 parity assertion (scoped, non-vacuous, closed-set)
    alert_route: CI red on the vitest suite, with a remedy-bearing failure string
logs:
  where: session stdout (observability layer 7, cli-stdout-artifact, per ADR-171); knowledge-base/project/kb-coverage.md for the durable half
  retention: session-scoped for stdout; git history for kb-coverage.md
discoverability_test:
  command: 'bash tests/commands/test-sync-producer-reachability.sh'
  expected_output: "all cases PASS, including the new producer-missing marker-emission case"
```

**Layer citation.** Observability **layer 7 (`cli-stdout-artifact`)** per ADR-171 — plugin code
on a customer's self-hosted CLI, where the durable artifact is the queryable surface. The layer-7
durability gap is pre-existing (ADR-179 §Consequences, tracked in #7452);
`observability-coverage-reviewer` is requested on the PR.

## Architecture Decision (ADR/C4)

**Amend ADR-179; do not open a new ordinal.** Its `## Consequences` enumerates the marker set by
name, so a reader would otherwise not learn the third marker exists. The amendment adds that line
and records that decision 5 (fail-closed in isolation) **binds** the freshness axis — which is
precisely why the guard is per-invocation-site rather than a Phase 0 loop.

**C4: no impact.** Verified against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` on the four
required enumerations: no external human actor is added or changed (the existing operator actor
reads a different string); no external system or vendor (the guard is a local `[ -f ]`); no
container or data store (`kb-coverage.md` is an existing artifact of an already-modelled
producer); no actor↔surface access relationship moves.

## Domain Review

**Domains relevant:** Engineering, Product.

Semantic sweep of all eight domains: a plugin-internal diagnostic on a developer-tooling command.
No pricing, contract, expense, pipeline, or regulated-data surface. The mechanical UI-surface
override did not fire — no path in Files to Edit matches any UI-surface term or glob — so
`ux-design-lead` was not activated.

### Engineering

**Status:** reviewed. CTO (devex lens) surfaced both hand-ratcheted floors, the remedy-bearing
failure-string idiom, the missing test-suite pointer, and the `affects=` grammar split; all are
folded into Phases 0-2. Architecture-strategist returned **do not ship as planned** against the
first draft, and its P0-1 (ADR-179 decision 5 → per-site guards) is the redesign in D1.

### Product/UX Gate

**Tier:** advisory (no new user-facing surface; operator-facing copy only)
**Decision:** reviewed
**Agents invoked:** cpo, spec-flow-analyzer
**Skipped specialists:** ux-design-lead (no UI surface in Files to Edit), cmo (no GTM, brand-copy
or market surface), copywriter (not recommended by any domain leader)
**Pencil available:** N/A (no UI surface)

#### Findings

CPO signed off **APPROVE WITH CHANGES**, all folded: the remedy message rewritten to four
properties (D3), the deferral split so the update-path pain is filed in Phase 4 rather than
buried in a Post-MVP tracker (D4), `## User-Brand Impact` enumerated worst-first, the
threat-model claim narrowed, and #7474 assigned a milestone. spec-flow found the unscoped-probe
false-alarm and the unwalked headless journey; both are resolved by D1 and D3 respectively.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| The marker ships inert — no registry validates marker names. | AC1 mutation-checks emission; AC3 mutation-checks parity. |
| Either hand-ratcheted floor is missed, producing a misleading CI failure (`ran 10 of 9 cases — a case was deleted`). | Phase 0 step 2 reads both; AC4 asserts both. |
| P6 passes vacuously if its parser stops matching. | Non-empty assertion on both derived sets before comparison (AC3). |
| P6 goes red on ADR-179's worked examples in Phase 0 prose. | Parser scoped to fence bodies; noted in Phase 1. |
| The agent ignores the STOP after an unverified root, reaching guarded sites anyway. | The guards then correctly emit and skip rather than executing anything — a strict improvement on today, where the invocation would run. ADR-179 R2 is unchanged by this plan. |
| A fourth producer serving two areas breaks the `affects=` map. | Grammar declared comma-joined (D2), matching the existing sibling. |
| The fix cannot help the install that reported it — a payload carrying these guards carries these producers. | Accepted and stated plainly: **closing #7474 does not resolve the reported incident.** The item that addresses the reported pain is the Phase 4 update-path issue filed in D4. Value here is H1/H2 plus enforcement for every future producer. |
| Plan-time producer count drifts before merge. | Phase 0 re-derives at HEAD; P6 re-derives at test time. No AC trusts this document's number. |

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Extend the identity gate with path predicates. | The issue's explicit non-goal, and correct: `test -d "$X/scripts"` is satisfiable by any directory — exactly what ADR-179 refuses. |
| A Phase 0 presence loop plus prose instructing the agent to skip affected areas. | **The first draft; rejected.** Unenforceable across fences, fires false markers for areas the run never touches, and separates the guard from its invocation against ADR-179 decision 5. |
| `exit 0` at the fence close + retargeting the STOP prose to the marker. | Rejected. `exit 0` permanently zeroes the fence's exit status, destroying the signal the STOP prose keys on, and the retarget then repairs self-inflicted damage — trading a real stop signal for a hypothetical refactor. Cut entirely with the Phase 0 loop. |
| `installed_plugins.json` SHA vs marketplace HEAD divergence warning. | Deferred to #7452 (four measured reasons; reads outside the verified root). The *user pain* is filed separately in Phase 4. |
| Deriving the guard list at runtime from the installed `sync.md`. | Rejected: under H2 the installed copy is precisely the stale one, so the derivation would erase the very producer it exists to flag. `affects=` is not derivable from an invocation under any scheme. |
| A version stamp in `sync.md` compared against installed `plugin.json`. | Rejected: version bumps are CI-owned, so the stamp needs CI tooling to stay true and a stale stamp false-alarms forever. |
| Widening `RUNNER_RE` so existing assertions cover a bare `[ -f ]` probe. | Moot under D1 (the guard is runner-prefixed and already covered), and it would have changed P1/P1c/P2 semantics. |

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | All producers present. | No marker; every area runs as today. |
| T2 | c4 producer absent, `/soleur:sync all`. | One marker `affects=c4`; the c4 invocation **does not execute**; coverage and domain-model still run; the D3 message names the file and what still worked. |
| T3 | All three absent (identity-valid root, empty `scripts/`). | Three markers, one per producer, each with its own `affects=`. |
| T4 | `write-kb-coverage.ts` absent. | Marker `affects=coverage`; the report states no durable row was written for this run. |
| T5 | `/soleur:sync conventions` with a producer absent. | **Zero markers** — no guarded site is reached. This is the regression the rejected design would have shipped. |
| T6 | `CLAUDE_PLUGIN_ROOT` unset. | `SOLEUR_SYNC_ROOT_UNRESOLVED` and refusal at the gate; no guarded site reached. T0c stays green — no decoy executes. |
| T7 | Mutation: remove a guard from one invocation. | P6 RED with a remedy-bearing string. |
| T8 | Mutation: typo an `affects=` value. | P6 RED on the closed-set assertion. |
