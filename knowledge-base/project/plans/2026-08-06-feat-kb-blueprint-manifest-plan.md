---
title: "feat: KB producers for alpha onboarding (PR 1) + blueprint manifest (PR 2, deferred)"
date: 2026-08-06
branch: feat-kb-blueprint-manifest
issue: "#7332"
pr: 7336
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: revised-post-review
brainstorm: knowledge-base/project/brainstorms/2026-08-06-kb-blueprint-manifest-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-blueprint-manifest/spec.md
design:
  - knowledge-base/product/design/dashboard/blueprint-cards-variant-a-two-zones.pen
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: PR 1 provisions NO infrastructure — no server, systemd unit,
  cron, vendor account, DNS record, cert, firewall rule, or Terraform resource.
  PR 2's `c4-visualizer` flip is an EXISTING Flagsmith runtime flag changed via
  the `/soleur:flag-set-role` skill, not provisioning. No Terraform root touched.
-->

# KB producers (PR 1) + blueprint manifest (PR 2, deferred)

## Revision note — restructured after 8-agent plan review

The original plan was a single seven-phase PR built on a manifest. Plan review
(DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO, CTO,
ux-design-lead) surfaced one fact that reorders everything, and the operator chose
to split on it:

**The alpha tester is on the self-hosted CLI plugin. The hosted web platform is
deferred** — `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md:41`:
*"Test surface: Self-hosted Soleur CLI plugin. The hosted web platform is deferred
until it is serving reliably again."*

Everything dashboard-shaped therefore reaches nobody today. The split is at the
CLI/hosted line, which is also the tester/no-tester line.

Operator decisions taken at the review gate:
- **Split at the CLI/hosted line.** PR 1 = producers (reaches the tester now).
  PR 2 = manifest + dashboard (when the platform is serving again).
- **Stub READMEs for all 10 domains: dropped.** Reverses the earlier decision, on
  the CPO's and code-simplicity's converging argument that ten empty domain
  directories are the inventory-of-absence framing relocated from cards into files.

Deferring the manifest to PR 2 dissolves the majority of the review's findings —
`blueprint-status.json`, the `when` predicates, the `card`/`tier`/`owner` fields,
the mirror, the CI drift gate, and every trust-boundary question about parsing
customer JSON on a server render path all belong to PR 2 and are not built here.

## Overview

**PR 1 — what the tester actually receives.** `/soleur:sync` gains two producers
and a coverage summary, so a connected repo's knowledge base stops being
`project/`-only. All output lands as files in the tester's own repository.

**PR 2 — deferred.** The blueprint manifest and the approved Variant A two-zone
dashboard, scoped in this document so the contract is designed once, built when
its surface exists.

Measured baseline on `2my8r9ry2t-wq/Skouer`: **23 KB entries, 100% under
`project/`** — no C4 model, no domain-model register. That is exactly sync's
declared output surface, so the gap is a missing-producer gap.

## Research Reconciliation — claims vs. codebase

| Claim | Reality | Response |
|---|---|---|
| "Four declarations that disagree" | The two path sets are **disjoint** — 0 of 10 card paths sit under `project/`, where sync writes exclusively. They answer different questions (what Soleur produces vs. what it asks the founder for). Only the intra-app duplication is real. | Framing corrected. PR 1 is a producer feature, not a de-duplication feature. |
| ADR-067 preserved | **ADR-067 is `adopt-swr-client-cache`.** The targeted-stat design lives in `knowledge-base/project/plans/2026-07-07-perf-dashboard-load-and-conversation-list-plan.md`. | Both constraints real and distinct. PR 2 concern only. `page.tsx:58-63` still carries the mis-citation **in source** — fix in PR 2's edit. |
| `MAX_CONCURRENT_STAT` bounds fan-out | `= 50`, passed to `mapWithConcurrency` — a **concurrency** bound, not an entry cap. | Claim withdrawn. Cardinality bounds are PR 2's problem. |
| Card schema is `{title, description, cta}` | Actual shape carries **`leaderId: DomainLeaderId`** (`page.tsx:44`), load-bearing for routing a click to the right domain leader. `description` has no source string today. | PR 2 schema must carry `leaderId`. |
| No precedent for server↔plugin data sharing | Two mechanisms exist, for different times: **runtime** read via `getPluginPath()` (`server/plugin-path.ts:42`, used at `agent-runner.ts:1116`), and **build-time** static JSON import — `app/internal/github-app-init/page.tsx:3` imports `@/infra/github-app-manifest.json` with `resolveJsonModule`, a parity test, and a drift-guard cron. | PR 2 uses the `github-app-manifest.json` pattern. The generated-TS mirror is dropped: a generated type regenerates to match a renamed field, so `tsc` can never catch the drift it exists to catch. |
| A cross-boundary import is merely unprecedented | It **breaks the production image build**. `apps/web-platform/Dockerfile:10` is `COPY . .` with build context `apps/web-platform` (`web-platform-release.yml:88`); `plugins/` is outside it. Such an import passes `tsc`, passes vitest, and fails only at release build. | This is the hard reason, recorded in ADR-171 instead of "no precedent". |
| Mirror `c4-render.ts` for diagnostic gating | **`c4-render.ts:192-195` explicitly rejects this**: *"gate on element count, never on stderr substring (wording can drift across likec4 patch versions)."* The `DIAG_RE` regex lives at `scripts/regenerate-c4-model.sh:94`. | Second mis-citation of the same class as ADR-067. Cite `regenerate-c4-model.sh:85-97`. See Phase 1 for why both gates are used. |
| Component docs carry a parseable dependency graph | True for Skouer (**6 of 7** — `ci-guards.md` has no `**Internal**` line at all). **False in general: 4 of 4 of Soleur's own component docs have zero parseable links** (`agents.md` "None (agents are standalone)", `commands.md` "Skills (workflow stages), Agents…", `knowledge-base.md` "All workflow commands read/write here", `skills.md` no line). | The convention is emergent LLM behavior, **not a specified contract**. Phase 1 must both specify it upstream and gate on relationship count. |
| The viewer can see sync-generated C4 | It reads from the **GitHub source of truth, not the on-disk clone** (`api/kb/c4/project/route.ts:73-81`), because a clone holding un-pushed commits goes permanently stale. Headless sync commits **locally only** (`sync.md` Headless Contract §1). | A generated diagram is invisible until its PR is pushed **and merged**. Stated as a delivery precondition, not assumed. |

---

# PR 1 — Producers (ships now)

## Phase 1 — C4 producer

Generate `spec.c4` / `model.c4` / `views.c4` from the component docs sync already
writes, then render and validate.

**The input contract does not exist yet, and that is the phase's main risk.** The
only place the dependency convention is written down is
`plugins/soleur/skills/spec-templates/SKILL.md:133` — `- **Internal**: [other
components it uses]` — which is a *prose placeholder*, not a link specification.
Nothing has ever told the producing side to emit `[name](name.md)`. Skouer's docs
happen to; Soleur's own do not, 4 times out of 4.

Three changes, in dependency order:

**1.1 Specify the contract upstream.** Edit `spec-templates/SKILL.md:133` and
sync.md's Project Analysis section to emit machine-readable frontmatter
(`dependencies: [web-server, database]`) alongside the human-readable prose. The
parser reads the field; the markdown link stays as human context. This is the
`heartbeat-manifest.ts` / ADR-117 lesson already codified in this repo — *"a
comment cannot fail CI, so `feeder` is EXECUTABLE."* A markdown-link convention is
comment-grade evidence.

**1.2 Parse with a fallback.** Read `dependencies:` frontmatter when present; fall
back to `**Internal**: [name](name.md)` link extraction for docs written before
1.1. Both paths feed one edge set.

**1.3 Validate on three gates, not two.**

- Diagnostic stream: `grep -qE '^Invalid |Could not resolve|^[[:space:]]+Line [0-9]+:'`
  per `regenerate-c4-model.sh:94`.
- `.elements | length > 0`.
- **Relationship count > 0** — the gate that catches the real failure. With docs
  present, elements non-zero, and syntactically valid output, a link-free corpus
  yields a valid diagram of disconnected boxes reported as success. This one line
  closes it.

Report **degraded**, not failure, when edges are zero — the docs are the defect,
not the run.

Note the two in-repo gating precedents deliberately disagree: `c4-render.ts` (the
runtime save path) gates on element count only, reasoning that stderr wording
drifts across patch versions; `regenerate-c4-model.sh` gates on both. Since the
producer pins `likec4@1.50.0`, the wording is fixed for that pin, so both-gates is
safe **as long as the pin holds** — an AC asserts the pin.

**1.4 Never overwrite hand edits.** `/soleur:architecture` writes those same three
filenames cwd-relative (`SKILL.md:51-52`), and the agent sandbox pins
`cwd = workspacePath`. Two writers, one path. A tester who hand-corrects a wrong
edge must not have it silently reverted by the next sync.

Emit into a **distinct composing file**, `generated-components.c4`, rather than
replacing the canonical three. Every generated file carries a
`// GENERATED by /soleur:sync c4 — hand edits will be overwritten` header, and the
producer **refuses to overwrite a file lacking that header**. This mirrors the
non-destructive contract Phase 2's `domain-model` already has.

**1.5 Filter deprecated components.** `sync.md:151` — *"Removed components: Add
`status: deprecated` to frontmatter (do not delete)"*. Without a frontmatter
filter, the element set accretes deleted components forever and a deprecated doc's
`## Dependencies` links create dangling edges. Skip `status: deprecated` docs.

**1.6 Emit the full artifact set the viewer needs.** Three `.c4` files are not
enough. `api/kb/c4/project/route.ts:174` returns `MODEL_NOT_BUILT` without a
committed layouted `model.likec4.json`, and the KB viewer renders a diagram only
for a markdown page carrying a ` ```likec4-view ` fence (Soleur's own is
`c4-model.md`). The deliverable set is
`{generated-components.c4, model.likec4.json, c4-model.md}`.

**1.7 Delivery.** Headless sync commits locally and opens a PR; the viewer reads
GitHub. The generated model is visible only after that PR merges. State it; do not
write an AC that assumes otherwise.

**1.8 Budget.** The headless run is capped at `maxTurns: 50` / `maxBudgetUsd: 5.0`
(`agent-runner.ts:2093-2094`) and already truncates findings at 20. New producers
run last, so budget exhaustion is a silent partial. Emit produced-vs-expected
counts in the liveness marker so a truncated run is distinguishable from a clean
one.

Files: `plugins/soleur/lib/c4-from-components.ts` (new),
`plugins/soleur/skills/spec-templates/SKILL.md`, `plugins/soleur/commands/sync.md`
(new `c4` area), `plugins/soleur/test/fixtures/` (synthesized component-doc
fixture), `plugins/soleur/test/c4-from-components.test.sh`.

## Phase 2 — domain-model promotion ⚠️ BLOCKED — needs an operator decision

"Remove `domain-model` from the `all`-dispatch exclusion list" is a one-line edit
that **cannot work**. Three independent blockers, all verified:

1. **It dies on a fresh repo.** `scripts/domain-model-drift.sh:161` (and `:240`):
   `realpath -e -- "$reg" || die "--register does not resolve to an existing file"`.
   A new customer has no `knowledge-base/engineering/architecture/domain-model.md`.
   Nothing bootstraps it.
2. **It writes nothing headless.** The write step is per-row `AskUserQuestion`-gated
   (`sync.md:196-207`), and the Headless Contract §4 auto-skips interactive gates.
   Even with a bootstrap, run 1 writes **zero rows**.
3. **The area is terminal by construction.** `sync.md:212`: *"Skip Phase 2 through
   Phase 4 when the area is `domain-model` — the drift report + approval-gated
   write ARE the output."* Folding it into `all` contradicts its own contract.

FR7's "safety properties preserved **unchanged**" is precisely the problem —
unchanged means it requires a pre-existing register and an operator at a keyboard.

**Two viable paths, operator's call:**

- **(a) Build it properly.** Add a register-bootstrap step (seed an empty register
  with the canonical headings) plus a headless-safe non-interactive write mode that
  appends to `## Auto-inferred (unreviewed)` without per-row approval — preserving
  the fail-closed secret scan, anchor dedup, atomic write, and never minting a
  `BR-*` id. Materially larger than a dispatch change; needs its own ACs.
- **(b) Drop from PR 1.** Ship the C4 producer as the sole new artifact. The
  tester's KB still gains a C4 model plus the coverage summary; domain-model
  follows once (a) is scoped on its own.

Files (path (a) only): `scripts/domain-model-drift.sh`,
`plugins/soleur/commands/sync.md`, plus tests.

## Phase 3 — Coverage summary

Print a coverage summary at the end of every sync and write
`knowledge-base/project/kb-coverage.md`.

**Wording is a hard constraint.** The report states what Soleur expects versus
what is present; it never asserts what the business lacks. "no `privacy-policy.md`
present in this knowledge base", never "missing: privacy policy". A committed,
timestamped, git-blamed record that a customer lacks a privacy policy is
discoverable and reads as knowledge of non-compliance.

**Determinism is required.** No embedded timestamp, stable ordering — an unchanged
KB must produce a byte-identical file. Otherwise every sync emits a one-field diff
forever. `knowledge-base/INDEX.md` is the in-repo warning: a committed generated
artifact with no freshness gate, whose regen once produced a +993-line unrelated
diff. `kb-coverage.md` is that shape, in a repo where we cannot add a CI gate.

In PR 1 the expected-set is a static list in `kb-coverage.ts`. PR 2 replaces that
list with the manifest — the only coupling between the two PRs.

Files: `plugins/soleur/lib/kb-coverage.ts` (new), `plugins/soleur/commands/sync.md`.

## Phase 4 — ADR-171 + Soleur's own C4 model

**ADR-171 — KB composition is declared by a plugin-owned manifest.** Authored now,
`status: adopting`, because PR 1 builds the producers the contract describes and
PR 2 builds the manifest itself. Records the Docker-build-context fact as the
reason a cross-boundary import is impossible, the two-writer precedence rule from
Phase 1.4, and the runtime-read-vs-build-time-import distinction.

Ordinal is **provisional** (highest existing: ADR-170). `/ship` re-verifies against
freshly-fetched `origin/main`; if it moves, sweep `plans/`, `specs/`, and every AC
naming it in the same edit.

C4 edits to Soleur's own model — all three `.c4` files were read, not grepped:

1. `model.c4` — add `connectedRepoKb` as an `#external` database, carrying the
   same trust-boundary description style as `connectedRepoPlugin` (`:320`).
2. `model.c4` — add `sync -> connectedRepoKb`. **`sync` currently has no
   relationship edge anywhere**, while every sibling skill has one
   (`brainstorm -> kb` `:625` … `architecture -> kb` `:629`).
3. `model.c4` — add `architecture -> connectedRepoKb` (the skill runs cwd-pinned
   to the workspace; this is Phase 1.4's collision, in diagram form).
4. `model.c4:87` — update the `kb` description; it omits diagrams and the
   domain-model register.
5. `views.c4` — add `connectedRepoKb` to the `containers` include list (`:26-37`)
   or it will not render.
6. Regenerate `model.likec4.json` via `bash scripts/regenerate-c4-model.sh` and
   commit — it is a lockfile, and `c4-model-freshness.test.sh` is an **orphan
   suite** only reached by full-suite `scripts/test-all.sh`.

The `blueprint` component and `dashboard ->` edges belong to PR 2 — a model
documenting them now would be a diagram of intentions.

## Observability (PR 1)

```yaml
liveness_signal:
  what: SOLEUR_KB_SYNC_PRODUCERS marker on stdout at end of every sync run,
        carrying {c4_elements, c4_relationships, domain_model_rows, coverage_present,
        coverage_expected}
  cadence: per sync invocation
  alert_target: Better Stack (SOLEUR_* marker stream)
  configured_in: plugins/soleur/lib/kb-coverage.ts
error_reporting:
  destination: SOLEUR_KB_SYNC_ERROR stdout marker on the same stream
  fail_loud: true
  note: NOT reportSilentFallback — that lives in apps/web-platform/server/observability.ts
        and nothing under plugins/ imports Sentry. A plugins/-side Sentry import is the
        exact cross-boundary coupling ADR-171 records as impossible.
failure_modes:
  - mode: C4 renders elements but ZERO relationships (link-free component docs)
    detection: relationship-count gate in the producer (Phase 1.3)
    alert_route: run reports degraded; c4_relationships=0 in the liveness marker
  - mode: likec4 emits a partial model on broken sources (exits 0)
    detection: DIAG_RE grep per regenerate-c4-model.sh:94 AND element count
    alert_route: run reports degraded; marker carries the diagnostic
  - mode: producer refuses to overwrite a hand-edited .c4 file
    detection: missing GENERATED header
    alert_route: skipped-with-reason in the marker; not an error
  - mode: headless PR push rejected by branch protection
    detection: existing headless contract §3 degraded path
    alert_route: SOLEUR_KB_SYNC_ERROR with the rejection reason — the artifacts are
                 committed locally and will not reach the viewer
logs:
  where: sync stdout; Better Stack via the SOLEUR_* marker stream
  retention: per existing Better Stack retention
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_KB_SYNC_PRODUCERS
  expected_output: one line per sync run carrying the five counts
```

The invocation form is load-bearing: `betterstack-query.sh` does not read Doppler
itself, a bare positional arg is treated as raw SQL, and the substring form is
`--grep`. No SSH anywhere in the diagnostic path.

**Open, must resolve before Phase 1 lands:** headless sync runs as an Agent SDK
conversation, not a journald unit, and the Better Stack source is
`soleur-inngest-vector-prd`. Verify a sandbox stdout line actually reaches that
source and cite the layer (`hr-observability-layer-citation`); if no path exists,
route the marker through a surface known to be ingested. Until verified, treat the
liveness signal as unproven.

## Encryption Posture

Not applicable — no persistent store, no new cross-component connection.

Correction to the prior draft, which claimed these are "committed files in the
customer's own git repository." Per `sync.md` Headless Contract §1 they are
**local commits in an ephemeral server-side workspace** until a PR merges, and
`syncWorkspace` branches un-pushed commits aside on non-fast-forward while repo
re-provisioning wipes and reclones. Durability is not assumed anywhere in PR 1.

## User-Brand Impact

**If this lands broken, the user experiences:** a C4 diagram in their own
repository whose edges misrepresent their architecture — or, in the failure mode
this plan exists to close, a diagram of disconnected boxes presented as a
successful result. For the alpha tester this is the first substantive artifact
Soleur produces for them.

**If this leaks, the user's data is exposed via:** sync writes generated content
into a private customer repository on a fire-and-forget trigger at connect time
(`auto-sync-trigger.ts:106`). A producer that overwrites a hand-corrected file, or
a coverage report recording the customer's compliance gaps in their own git
history, is committed and permanent — git history is not erasable.

**Brand-survival threshold:** `single-user incident`. CPO sign-off carried forward
from brainstorm Domain Assessments; `user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Product, Engineering, Legal — carried forward from the
brainstorm's `## Domain Assessments`, then re-reviewed by an 8-agent plan-review
panel whose findings are folded in above.

**Product:** the taxonomy rule (a card is a request for founder input; agent-
completable work is not a card) is deferred to PR 2 with the dashboard. CPO
withheld sign-off on the pre-revision plan on two grounds — the evidence zone had
no data path, and Phases 5/7 reached a surface the tester is not on. The split
resolves both; PR 2 must carry the `render`/`metric` schema work before Variant A
can be built.

**Engineering:** the manifest's cross-boundary mechanism changed twice under
review — build-time import (impossible: Docker context), generated TS mirror
(useless: generated types cannot catch their own drift), and finally the
`github-app-manifest.json` pattern for PR 2. PR 1 needs none of it.

**Legal:** no threshold row in `recommended-tools.md` fires; founder-grade
compliance helping. The coverage-report wording control (Phase 3) is adopted. The
stub-README disclaimer control is moot — the stubs are dropped. ADR-mining remains
cut; its four-control set is recorded in the brainstorm should it ever revive.

## Open Code-Review Overlap

Scanned 64 open `code-review` issues against PR 1's file list. **No matches.**
(#2590 touches `dashboard/page.tsx`, which PR 1 no longer edits — it moves to PR 2,
where the disposition is *acknowledge*: different lines, and the rewire removes
~60 lines from that file.)

## Acceptance Criteria — PR 1

### Pre-merge

1. `plugins/soleur/lib/c4-from-components.ts` parses BOTH `dependencies:`
   frontmatter and `**Internal**: [name](name.md)` links; a synthesized fixture
   exercises each path.
2. **The relationship-count gate fails by construction.** Run the producer against
   a synthesized fixture whose component docs carry Soleur's own prose form
   (`**Internal**: None (agents are standalone)`) and confirm it reports degraded
   with `c4_relationships=0` — not success. A gate that has never been seen red is
   not a gate.
3. The producer refuses to overwrite a `.c4` file lacking the `GENERATED` header;
   asserted with a fixture containing a hand-edited file.
4. `likec4@1.50.0` pin asserted in the producer, matching
   `regenerate-c4-model.sh` and `c4-render.ts`.
5. Diagnostic gating cites `regenerate-c4-model.sh:85-97`; the plan and code
   contain no instruction to mirror `c4-render.ts`'s stderr handling.
6. `domain-model` no longer appears in sync.md's `all`-dispatch exclusion list;
   `domain-model-drift.sh` is unmodified (`git diff --exit-code scripts/domain-model-drift.sh`).
7. `kb-coverage.md` is byte-identical across two consecutive runs on an unchanged
   KB.
8. `kb-coverage.md` contains no line matching an anchored deficiency pattern
   (`^[-*] *[Mm]issing:`) AND contains the expectation-vs-presence phrasing.
   Both assertions, generated from a fixture — presence of good phrasing is not
   absence of bad phrasing.
9. `npx tsc --noEmit` clean from `apps/web-platform` (repo convention per
   `ci.yml`; `apps/web-platform/node_modules/.bin/tsc` is not installed in a
   worktree).
10. `bash scripts/test-all.sh` green — required, not optional:
    `c4-model-freshness.test.sh` is an orphan suite the touched-file loop misses.
11. `model.likec4.json` byte-identical to a fresh render of the edited `.c4`
    sources; `views.c4` includes every element added to `model.c4`.
12. `ADR-171-*.md` exists, `status: adopting`, ordinal free on freshly-fetched
    `origin/main`.
13. PR body carries a `## Changelog` section and a `semver:minor` label
    (`plugins/soleur/AGENTS.md` pre-commit checklist — new plugin content).

### Post-merge (operator)

14. Re-sync `2my8r9ry2t-wq/Skouer`. Confirm the generated model's elements match
    its component-doc set and its relationships match their declared dependencies.
    **Do not assert a literal count** — `ci-guards.md` has no `**Internal**` line,
    so 7 docs do not imply 7 connected elements.
    *Automation: agent-run via `gh api` against the merged PR's tree.*
15. Confirm the generated `.c4` reached GitHub (the viewer's source of truth), not
    just the local clone.
    *Automation: `gh api repos/.../contents/knowledge-base/engineering/architecture/diagrams`.*

## Risks & Mitigations — PR 1

| Risk | Mitigation |
|---|---|
| The dependency convention is emergent, not specified — 4/4 of Soleur's own component docs have zero parseable links | Phase 1.1 specifies it upstream with machine-readable frontmatter; 1.3's relationship-count gate catches the link-free case; AC2 proves the gate goes red. |
| `likec4` unavailable in the customer sandbox | Render failure is a clean degrade (skipped-with-reason in the marker), never a hard error. Establish availability before Phase 1 lands. |
| Sync overwrites a tester's hand-corrected diagram | Distinct composing file + `GENERATED` header + refuse-if-absent (Phase 1.4), mirroring `domain-model`'s non-destructive contract. AC3. |
| Generated C4 never reaches the viewer | It cannot until its PR merges — the viewer reads GitHub, sync commits locally. Stated as a precondition; AC15 verifies delivery rather than assuming it. |
| Liveness marker may not reach Better Stack | Flagged as unproven in the Observability block; must be verified and cited before Phase 1 lands, per `hr-observability-layer-citation`. |
| Learning `2026-03-02-...auto-push-vs-pr` recommends direct push | **Does not apply.** `sync.md` Headless Contract §2 forbids pushing the protected default and mandates worktree→PR. The contract is more specific and wins. Recorded so it is not re-litigated. |

---

# PR 2 — Blueprint manifest + dashboard (deferred)

Ships when the hosted platform is serving reliably again — which is also when
Variant A can be validated against a real user.

**Scope:** the manifest at `plugins/soleur/kb-blueprint.json`, copied byte-identical
to `apps/web-platform/lib/kb-blueprint.json` and consumed through a hand-authored
typed module using `satisfies` (the `app/internal/github-app-init/page.tsx:3` +
`infra/github-app-manifest.json` pattern, which already ships with a parity test
and a drift-guard cron). Plus the Variant A two-zone dashboard.

**Design constraints already established by review — carry these forward:**

- **Docker build context.** `plugins/` is unreachable at build time. The copied
  JSON is the mechanism; a generated `.ts` is not, because a generated type
  regenerates to match a renamed field and `tsc` can never catch the drift.
- **Card schema must carry `leaderId: DomainLeaderId`**, not just
  `{title, description, cta}`. `overview.vision` ships `promptText: ""`; the
  validator must accept empty strings — dropping that entry removes
  `overview/vision.md` from the stat set, permanently falsifies `visionExists`
  (`page.tsx:261`), and pins every user into the first-run composer.
- **The stat set is cards ∪ `{overview/vision.md}`**, derived by a different rule
  than the card set. `test/api/dashboard-foundation-status.test.ts:98` is the
  sentinel's only guard today and `vision-helpers.ts:60-73` independently
  hardcodes the path — a fifth declaration.
- **The evidence zone must be decoupled from `visionExists`.** The section is gated
  at `page.tsx:580`, `:582`, `:653` on `visionExists && !allTasksComplete`; Skouer
  has no `vision.md`, so the feature would render nowhere. Evidence is a receipt,
  not a request — only the input-request zone stays contingent.
- **The evidence zone needs a data contract.** Variant A's tiles carry computed
  metrics ("11 entities across 6 domains") and per-artifact timestamps that neither
  `{exists, size}` nor an `{id, applicable}` status file can supply.
- **Applicability may only suppress non-card entries.** Card entries always render;
  absent/invalid/empty status ⇒ manifest defaults, never empty. `allTasksComplete`
  is `.every()` over the card array and is **vacuously true when empty** — an
  all-false status would congratulate a founder who has done nothing.
- **A layout AC is mandatory.** No current AC would fail if the rewire shipped with
  today's single grid. Assert zone order, evidence-tile presence, the computed
  disclosure label, and the coverage entry point's parentage — with a
  fail-by-construction check against the pre-change component.
- **Register the drift gate in `scripts/required-checks.txt`** with `merge_group`
  coverage, or it is advisory. `lockfile-sync` — the cited precedent — is
  registered in all three places; citing its shape is not citing what makes it
  binding.
- **Fix `page.tsx:58-63`'s ADR-067 mis-citation** in the same edit that rewrites
  the block.
