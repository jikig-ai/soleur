---
title: "chore(git-data): assert the three authorized_keys pubkeys are distinct, and disclose what a green boot does not mean"
date: 2026-09-10
slug: chore-git-data-three-distinct-pubkey-gate
branch: feat-one-shot-8009-three-distinct-pubkey-gate
issue: 8009
closes: 8009
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-10
**Reviewers reported and incorporated:** CTO, CLO, correctness, simplicity, spec-flow, architecture,
test-design, security — all eight
**Halt gates passed:** User-Brand Impact (4.6), Observability (4.7), PAT-shaped variable (4.8),
UI-wireframe (4.9, skipped — no UI surface), Encryption Posture (4.10, skipped — no new store),
Guard Contract (4.11, lint green)

### Key improvements over the first draft

1. **The assembly grew from four links to five.** The private-half `doppler_secret` distribution — the
   half the application actually holds — was absent. A one-line edit there inverts the authorization
   map while every enumerated link stays byte-canonical and green. The first draft would have shipped
   a guard certifying something other than what its own HOLD message claims: the exact defect class
   #8009 exists to fix, reproduced inside the fix for #8009.
2. **The unit changed from one file to the Terraform root directory.** `locals`, `resource` and
   `module` blocks merge across every `.tf` in a root, so a single-file gate is defeated by adding a
   sibling file. Two further structural bypasses were added to the matrix: `*override.tf` merging, and
   a second module instantiation.
3. **Cardinality became exact.** Every mutation in the first draft was a substitution; none was a
   deletion. Deleting one `command=` line leaves two slots holding two distinct keys — a
   distinctness-only guard goes green on a host that lost a forced-command boundary.
4. **The disclosure moved out of the gated job.** An environment-gated job is held before its first
   step runs, so the in-job step executed *after* the approval click. It now runs in a preceding
   un-gated job, so it renders on the run page while the gated job waits.
5. **The gate gained the `git-data-host-replace` path.** After birth, a replace is the *only* route by
   which a re-rendered `authorized_keys` block reaches the host — and that job has no human approver.
6. **A blanket `//` / `/*` ABORT would have shipped a gate born red.** Measured: 81 `//` occurrences
   across 19 of the 48 root `.tf` files, none of them HCL comments, one inside `git-data.tf` itself.
   Because `ci.yml` runs the suite unfiltered on every PR, that would have reddened **every pull
   request in the repository** until someone deleted the arm. The rule is now quote-aware. This was
   the plan's own warned-about failure one level up: a premise measured under the three-file framing
   and carried forward unchanged after D2 widened the unit to 48.
7. **The matrix could not tell an identity map from a cardinality check.** M12/M13 are both
   double-use collapses, which a cardinality predicate reds on — so the battery would have passed an
   implementation the plan explicitly rejects. Predicate 4 is now an *ordered* per-authority
   composition, anchored to a third artifact, with 2-swap and 3-cycle rows (M16–M18) that are
   perfectly bijective and must still red.
8. **A fourth `authorized_keys` line with no `command=` was invisible** (M26): it contributes no slot,
   so the count still reads 3 and the gate releases, while that key falls through to the raw
   `git-shell` path the transport wrapper exists to replace.
9. **D9 shipped with a caveat instead of an overclaim.** `git_data_host_replace` has no
   `environment:`, hence no branch policy — so the gate it sources is supplied by the branch it
   polices. Phase 4.2 now adds the environment; the plan states plainly that the interlock alone
   protects against accident, not against a deliberate actor with repo write.
10. **~40% of the assembly was cut as ceremony.** Five independent per-link assertions collapsed to one
   resolution walk; a rehearsal counter-assertion was cut entirely, taking a second suite, a second
   anti-vacuity convention, two ACs and a sharp edge with it.

### Claims the review falsified, corrected in place rather than quietly patched

- The justification phrase appears at **one** site in the gate library, not two — and its most
  explicit copy lives in a **hash-bound** file that must not be touched (tracked as F6).
- The suite's existing `_a_tree` / `_a_abort` fixture has none of links 3–5 and is hardwired to a
  different gate function; a new fixture and helper pair are required, and that is the real cost of
  Phase 1.
- `c4-count-parity.test.sh` lives under `plugins/soleur/test/`, not `apps/web-platform/test/` — which
  also falsified a premise row claiming all cited paths had been checked. The row is now
  scope-narrowed and the correction recorded.
- **The repository is PUBLIC**, so the Legal advisory's stated reason for keeping
  `disclosed_as: "not-publicly-claimed"` ("a job log and an internal runbook are not public surfaces")
  is false. The *conclusion* survives on measured grounds — every one of C2's three statements is
  already public, and (b) is returned by an unauthenticated API call — but the premise is corrected
  rather than carried.
- **C2(b) was understating its own finding.** `can_admins_bypass: true` on all five gated
  environments means the control is not merely self-approvable: the same account can bypass the
  reviewer *and* the main-branch pin with no approval event at all.

## Overview

Two conditions gate the git-data host birth dispatch, and both must land in one PR.

The first (#8009) is a missing static assertion. The git-data cloud-init template writes three
`authorized_keys` entries, each pinning a different forced command to a different pubkey variable —
transport, provision, and erase. Nothing in the birth gate checks that those three entries resolve to
three distinct keys. The paid rung-2 rehearsal cannot catch a collapse either, because the rehearsal
root already wires all three slots to one key, so a production edit that collapses them reads as a
clean boot. The plan adds a static assertion to the gate library and a mutation arm to the gate's own
suite that must go red when the three slots collapse to one variable.

The second condition (C2) is a disclosure gap on the dispatch surface. The operator approving the
birth sees a runbook banner and an approval button that carry none of the residual risk: repositories
are not encrypted at rest before cutover, the environment approval is not two-party, and the rung-2
evidence attests that a final stage was reached rather than that four invariants were measured. The
plan puts those three statements in plain language on the workflow's own pre-apply output and in the
runbook's pre-dispatch section.

The rung-2 evidence binding hash must not move. Every design choice here is constrained to the gate
library and its suite for that reason.

No spec exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed). The default
is also substantively right here: the domain sweep found Engineering, Legal and Product all relevant.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the brief cites was re-verified against `origin/main` at `a8b7aabf` this session, and
all of them hold.

| Reference | Checked by | Result |
|---|---|---|
| #8009 (work target) | `gh issue view` | OPEN, `type/chore`; title matches the collapse-is-a-no-op framing |
| #8010 (out of scope) | `gh issue view` | OPEN — rung-2 gate checks assertion SHAPE, not that a rehearsal passed |
| #6286 (out of scope) | `gh issue view` | OPEN — unrelated inngest cloud-init pin drift |
| #7025 (owns the banner) | `gh issue view` | OPEN, carries `follow-through` |
| #8002 / #8012 | `gh issue view` | Both MERGED — the evidence commit and the banner correction |
| Binding hash `3a2392fb…c1725` | `git_data_rung2_user_data_sha256` re-run | Recomputes and matches `RUNG2_TEMPLATE_SHA256` |
| `prevent_self_review: false` | GitHub environments API, live | Still false; single reviewer. Unchanged — C2(b) stands as written |
| Cited file paths from the brief | `ls` | All present |

No premise from the brief was stale. Nothing re-scoped on their account.

**One row of this table was initially wrong, and the correction is recorded rather than quietly
patched.** An earlier draft claimed *all* cited paths were verified present; review found
`apps/web-platform/test/c4-count-parity.test.sh` did not exist (the real path is
`plugins/soleur/test/c4-count-parity.test.sh`). That path was introduced by the plan itself, not by
the brief, and it had not been `ls`-checked — so the row's scope is now narrowed to the brief's
citations, which *were* checked, and every path the plan introduces is verified separately at
Phase 8.4. The lesson is the one the plan cites elsewhere: a verification row that overstates its own
scope is worse than no row, because it spends credibility it did not earn.

### The hash-bound file set — measured, and it decides the whole design

`git_data_rung2_user_data_sha256` binds **13 files**: the cloud-init template, all three
`modules/git-data-userdata/*.tf` files (`main.tf`, `outputs.tf`, `variables.tf`), and the nine
`file("${path.module}/…")`-bound payloads (`git-data-bootstrap.sh`, `git-data-provision.sh`,
`git-data-remove.sh`, `git-data-transport-wrapper.sh`, `git-data-pre-receive-placeholder.sh`,
`git-data-gc.sh`, `git-data-gc.service`, `git-data-gc-failure.service`, `git-data-gc.timer`).

**None of the four files this plan edits is in that set**, so the hash cannot move:

| File this plan edits | Hash-bound? |
|---|---|
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | No — the gate does not hash itself |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | No |
| `.github/workflows/apply-web-platform-infra.yml` | No |
| `knowledge-base/engineering/operations/runbooks/git-data-birth.md` | No |

The corollary is the binding constraint on C1: the template and the render module are **read-only**
here. An assertion written *into* the template would void the evidence and buy a fresh paid rehearsal.
`apps/web-platform/infra/git-data.tf` is **not** hash-bound, so the terraform-side arm may read it
freely. `git-data-bootstrap.sh` **is** hash-bound, which is why C2(a) quotes its AC30 wording rather
than editing it.

### The collapse surface is a five-link chain

Measured end to end. A collapse can be introduced at any one of these links, and each is a one-line
edit:

1. `cloud-init-git-data.yml` — the three `command=` lines, anchored on
   `command="/usr/local/bin/git-data-transport-wrapper.sh"`, each carrying a distinct `${…}` name.
2. `modules/git-data-userdata/main.tf` — `git_transport_pubkey = var.git_transport_pubkey` and its two
   siblings, a 1:1 identity map into the template's variable set.
3. `git-data.tf` module call — passes `local.git_transport_pubkey` / `local.git_provision_pubkey` /
   `local.git_remove_pubkey`.
4. `git-data.tf` locals — each local is `trimspace(tls_private_key.<name>.public_key_openssh)` over
   three distinct resources: `git_transport`, `git_provision`, `git_remove`.

Links 1 and 2 are hash-bound; links 3 and 4 are not. Both roots render through the same module, which
is what makes the rehearsal's collapse invisible: `rung2-rehearsal/rehearsal.tf` passes
`trimspace(tls_private_key.rehearsal.public_key_openssh)` to all three module arguments.

### The gate library's existing shape

- `git_data_birth_readiness_gate(cloud_init)` — a **single** binary assertion on a `${sentry_dsn}`
  sentinel, early-returning, closing with a long hardcoded RELEASED message that enumerates what it
  does *not* prove. It also carries operator decision DC-2 (2026-07-27) mandating its eventual
  replacement by a direct assertion on the emitter resource.
- `git_data_rung2_rehearsal_gate(cloud_init, [evidence])` — a **chain** of independent early-return
  assertions; derives its optional second argument from `dirname` of the first. This is the sibling
  convention a new function should mirror.
- Both are fail-closed on a missing argument: a bare call prints `ABORT` and returns non-zero. That is
  the instrument refusing, not a gate failing — always pass the path.
- `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` is a space-separated string of eight bare tokens, consumed at
  exactly two sites: a membership loop and the HOLD message that prints it. The phrase
  `identity-shaped render var` appears at **exactly one** site — the HOLD message. The comment block
  above the constant lists the pubkeys among the templatefile *arguments* but makes **no** claim that
  they are identity-shaped; there is no wrong claim there to correct. (An earlier draft of this plan
  asserted two sites. Corrected — see D4.)
- The suite runs **80 arms**, with an anti-vacuity floor (`>= 80`), a ledger reconciliation
  (`${#FAILURES[@]} == $fails`), and an explicit `exit $(( ${#FAILURES[@]} > 0 ))`. The floor is
  raised in itemised blocks, each recording which arms were added and why.
- The suite already asserts against the **live** tree in one place — it calls
  `git_data_birth_readiness_gate` on the real `cloud-init-git-data.yml`, and arm A1 makes a missing
  live file a **loud failure** rather than a skipped arm. That is the precedent the new live-tree arm
  follows, and the narrowing to the suite header's "synthesized fixtures only" rule must be written
  down the way A1's was.
- **The `_a_tree` / `_a_abort` pattern does NOT fit this work**, contrary to an earlier draft. See the
  Guard Contract's "Fixture reality" note: the R2 fixture has no `git-data.tf` at all, and `_a_abort`
  is hardwired to a different gate function. The applicable precedent is `git-data-luks.test.sh`'s
  `assert_holds` / `assert_mutation`.
- **CI reach, measured:** `ci.yml` runs `bash scripts/test-all.sh scripts` on `pull_request` with no
  `paths:` filter and no `if:` gate, and `scripts/test-all.sh` registers this suite via `run_suite`.
  So every arm added here already runs on every PR — which is why the PR-time coverage is bought with
  a live-tree **arm**, not with a new workflow step (D8).

### The C2 surfaces as they stand today

- The `git_data_host_create` job has **no `name:` key**; it is identified by its job id. Its
  `environment:` is `web-platform-infra-apply`, and its own header comment already concedes that the
  approver "approves BEFORE any step runs, so they cannot verify a plan."
- The job prints **nothing** in plain language before `terraform apply`. Every pre-apply echo is either
  a fatal `::error::` or a terse mechanical confirmation. All residual-risk prose today lives in the
  `Dispatch summary` step, which runs `if: always()` — i.e. **after** apply, under the heading
  `### What a green run gives you — and what it does not`. That is too late to inform an approval.
- The `BIRTH-GIT-DATA` check already states its own status in its error text: it is a typo-guard, and
  the environment reviewer is the authorization.
- The runbook's pre-dispatch section is `## Before you dispatch`, a six-row `| Check | How |` table.
  It carries **no** residual-risk statement.
- **The C2(b) statement already exists — but only inside the DO-NOT-DISPATCH banner**, which #7025
  deletes. This is the single most consequential finding for C2's placement, and it is recorded as a
  decision below.
- `## What the job does, in order` has pre-existing drift: it lists eight items and omits the rung-2
  rehearsal interlock entirely.

### C2's three statements, verified at source

(a) `git-data-bootstrap.sh` pins the wording under AC30, anchored on `WORDING PINNED (AC30)`:
`luks_mounted` is about the DEVICE and says nothing about repositories being encrypted at rest — they
are not, and the same comment names duplicating that false claim into telemetry as "the Art. 30 defect
in a second artifact."

(b) Re-measured live: `prevent_self_review: false`, one reviewer. Unchanged from the brief.

(c) The emit call carries `"luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes"` as
**hardcoded literals**, with only `nft_metadata_drop=${_nft_drop}` measured — computed by grepping
`nft list chain inet soleur_git_data output` for the metadata address. Each of the four literals does
have a named upstream `FATAL: …; exit 1` gate (LUKS mountedness *and* a separate mapper-identity
assert; `repo_root` resolution; `core.hooksPath`; provision-script executability), and every `FATAL:`
string is routed off-host by the `log()` wrapper — so reaching the emit is not free. Confirmed:
`nft_metadata_drop` appears in **neither** committed artifact — the evidence file's five keys are
`RUNG2_SENTRY_CROSSCHECK`, `RUNG2_BOOT_REHEARSAL`, `RUNG2_EVIDENCE_URL`, `RUNG2_TEMPLATE_SHA256`,
`RUNG2_VAR_DIVERGENCE`, and its embedded host-rows query selects only the four literal booleans.

### Property List (Phase 0.6b)

1. A collapse of the three forced-command slots onto fewer than three distinct keys is caught before
   the birth dispatch, without a live host and without a paid rehearsal.
2. The gate's own message states which of the two things it proves — template-side variable
   distinctness, or terraform-side resource distinctness — rather than letting a reader infer the
   stronger claim.
3. The allowlist's justification for the three pubkey tokens describes them correctly as a capability
   divergence rather than an identity one.
4. The human approving the birth sees, at the moment of approval, that repositories are not encrypted
   at rest, that the approval is not two-party, and what the rung-2 evidence does and does not attest.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why cut |
|---|---|---|
| Assert on the *rendered* `authorized_keys` values | 1, strongest form | Requires rendering, which requires terraform init/plan against real `tls_private_key` resources. Not static, and the template ships variables rather than keys. Superseded by the two-arm design. |
| Fix `rung2-rehearsal/rehearsal.tf` to use three keys | 1, via the rehearsal | Only meaningful with a fresh **paid** rehearsal, which the brief rules out. The static gate covers what the rehearsal structurally cannot. |
| A new standalone gate script outside the library | 1 | The library already holds the sibling interlocks and is already sourced by the dispatch job; a second file would need its own wiring and its own suite. |
| Widening `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` | 3 | The allowlist shape is correct as-is — the three tokens genuinely may differ in VALUE between rehearsal and production. Only the justification is wrong. No widening, so `hr-type-widening-cross-consumer-grep` does not fire. |
| A new ADR | — | The three-key separation is already decided (ADR-068, quoted in the template). This plan enforces an existing decision rather than making a new one. |

### Institutional learnings that bear on this work

- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md` —
  guards that cannot fail are indistinguishable from passing. Directly on point: the mutation arm is
  the deliverable, not the assertion.
- `knowledge-base/project/learnings/2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`
  — a guard asserts over a set S; S must be derived from something other than the artifact under test,
  or the assertion becomes a tautology. This is why the expected token set is hardcoded, never parsed
  back out of the template being checked.
- `knowledge-base/project/learnings/2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md`
  — same route, four vacuity shapes. Cardinality is not discrimination.
- `knowledge-base/project/learnings/2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md`
  — extracting a value from a file proves the value, never its application. The reason the gate message
  must state plainly which of the two arms proved what.
- `knowledge-base/project/learnings/2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`
  — the mutation battery does not catch a fixture that is wrong but self-consistent; review does.
- `knowledge-base/project/learnings/2026-09-08-my-guard-could-not-fire-and-the-sweep-stopped-at-the-gate.md`
  — two lessons at once: GitHub Actions runs bare `run:` under `bash -e`, so `VAR=$(grep …)` kills the
  step on a legitimate zero count; and a correction sweep that stops at the executable line leaves the
  prose carrying the old claim. Both apply to the C2 workflow step.
- `knowledge-base/project/learnings/best-practices/2026-06-03-grep-over-markdown-marker-tests-line-wrap-and-vacuous-alternation.md`
  — grep matches per physical line; a marker assertion over wrapped prose silently fails. Applies to
  every C2 disclosure assertion.
- `knowledge-base/project/learnings/2026-09-09-the-ac-prescribed-a-read-the-artifact-could-not-answer.md`
  — the immediate predecessor: `nft_metadata_drop` is in neither committed artifact. C2(c) is the
  disclosure half of that same finding.

### Conventions carried in from AGENTS.rules.md

`cq-write-failing-tests-before` (the mutation arm lands red first), `cq-assert-anchor-not-bare-token`
and `cq-cite-content-anchor-not-line-number` (every assertion and citation anchors on content),
`hr-verify-repo-capability-claim-before-assert` (the environment measurement above),
`hr-no-dashboard-eyeball-pull-data-yourself` (all telemetry self-pulled),
`hr-type-widening-cross-consumer-grep` and `hr-write-boundary-sentinel-sweep-all-write-sites` (cited in
the allowlist decision below, which deliberately does not widen the shape).

### Open Code-Review Overlap

None. All 65 open `code-review` issues were queried for each of the four planned file paths; zero
matched.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| The hash binds 13 files | Holds. Measured: template + 3 module `.tf` + 9 payloads | Carried forward as the binding constraint |
| Both gates release at rc=0, fail-closed on a missing arg | Holds, verbatim in the library | Every prescribed invocation passes the path |
| Hash recomputes to `3a2392fb…c1725` | Holds; re-run this session | AC re-runs it before push |
| `prevent_self_review=false`, single reviewer | Holds; re-measured live | C2(b) stands unchanged |
| The three template vars are three distinct names | Holds | Template-side arm |
| Production backs them with three distinct `tls_private_key` | Holds — `git_transport`, `git_provision`, `git_remove` | Terraform-side arm |
| Rehearsal sets all three to one key | Holds — `rehearsal.tf` passes `tls_private_key.rehearsal` three times | Gate scoped to the production root, fail-closed |
| The allowlist comment calls them "identity-shaped render vars" | **PARTLY FALSE.** The phrase appears at exactly **one** site — the HOLD message. The comment block above the constant makes no identity claim about the pubkeys at all | D4 revised: add the capability sentence to the comment block, minimally generalise the HOLD message, and do **not** delete a phrase that is accurate for five of the eight tokens |
| C2(b) is absent from the dispatch surface | **PARTLY FALSE.** It is already present — but only inside the DO-NOT-DISPATCH banner, which #7025 deletes | Disclosure goes in `## Before you dispatch`, which survives. Recorded as decision D5 |
| `nft_metadata_drop` is in neither committed artifact | Holds | C2(c) states it |
| The dispatch surface carries no residual risk pre-approval | Holds — all such prose is in the post-apply `Dispatch summary` step | New pre-apply step |

Two further findings the brief did not mention, both surfaced by direct reading:

- **The collapse surface is FIVE links, not one — and the fifth is the one that matters most.** The
  brief frames C1 as template-side plus terraform-side. Measured, there are five distinct places a
  collapse can be introduced. Four concern the **public** halves. The fifth is the **private-half
  distribution**: `git-data.tf` binds `tls_private_key.<name>.private_key_openssh` into three
  `doppler_secret` blocks named `GIT_{TRANSPORT,PROVISION,REMOVE}_SSH_PRIVATE_KEY`, and those are
  what the application actually holds. Re-pointing one line there — `doppler_secret
  .git_transport_ssh_private_key.value` at `tls_private_key.git_remove` — makes every ordinary push
  execute `git-data-remove.sh`, **while all four public-half links stay byte-canonical and green**.
  It is also the only edge in the entire map with zero existing coverage: the app-side tests
  `vi.stubEnv` the env *names*, which cannot see which Terraform resource fills them. An earlier draft
  of this plan enumerated only four links and would have shipped a guard certifying something other
  than what its own HOLD message claims — the exact defect class #8009 is about, reproduced inside the
  fix for #8009. Recorded as decision D2 and mutation rows M12/M13.

- **Two further bypasses the four-link framing missed**, both now in the matrix: Terraform merges
  `*override.tf` over the primary configuration, so a one-file addition re-points a local at apply
  time while `git-data.tf` stays canonical (M14); and nothing asserts that the `module` block the gate
  reads is the one `hcloud_server.git_data.user_data` actually consumes, so a second module
  instantiation slips past (M15).
- **`## What the job does, in order` in the runbook already drifts** — it lists eight items and omits
  the rung-2 rehearsal interlock. Adding a third gate makes that list wrong in a second way. Folded
  in, since this plan is the reason it would get worse.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing immediately — this PR ships no runtime code.
The failure mode is deferred and total: a later one-line edit collapses the three forced-command slots
onto one key, no gate refuses, and the git-data host is born with the transport identity — the key the
web application holds for ordinary push and fetch — authorized to run `git-data-remove.sh`. The user
experiences that as their repositories disappearing, on a host that holds every connected user's
source code, with no error anywhere in the chain because sshd matched the first key and did exactly
what it was told.

**If this leaks, the user's data is exposed via:** the erasure path itself. This is not a
confidentiality leak but an integrity and availability one — Art. 17 machinery reachable from an
identity that should only be able to push and fetch. The blast radius is every connected user's
repositories, and the operation is `rm -rf`, which has no undo.

- **Brand-survival threshold:** `single-user incident`

One user losing their source code to a transport key that was never supposed to hold erasure authority
is a brand-ending event on its own. It does not need to aggregate.

Consequently `requires_cpo_signoff: true` is set in frontmatter. The CPO sign-off already exists in
substance — this work IS CPO condition C, and C2 is the unfiled half of it — so the plan-time
requirement is satisfied by that standing sign-off rather than by a fresh ask. `user-impact-reviewer`
is invoked at review time.

## Guard Contract

### Guard 1 — the authorization-map gate

**Property.** On the production render path, the three SSH forced-command slots on the git-data host
— transport, provision, erase — are held by three pairwise-distinct public keys, **and the private
half of each is published under the Doppler name whose consumer holds exactly that authority.**

The second clause is not decoration, and its absence was a real defect in an earlier draft of this
plan. Distinctness of the *public* halves is satisfiable while the map is fully inverted: three
distinct keys can render into the template while the app's transport secret carries the erase key.
The property must name both halves or the guard certifies something other than what its own HOLD
message claims.

**Assembly.** Not an enumerated member list — a chokepoint set. The property quantifies over the
**five links of the production authorization map**:

| # | Link | File | Hash-bound |
|---|---|---|---|
| 1 | The `authorized_keys` slots — every entry anchored on `command="/usr/local/bin/git-data-` and its terminating `${…}` | `cloud-init-git-data.yml` | **Yes — read only** |
| 2 | The `templatefile()` argument map binding each template variable to a module variable | `modules/git-data-userdata/main.tf` | **Yes — read only** |
| 3 | The `module "git_data_userdata"` call's three pubkey arguments | `git-data.tf` | No |
| 4 | The `locals` resolving each argument to `trimspace(tls_private_key.<name>.public_key_openssh)` | `git-data.tf` | No |
| 5 | **The private-half distribution** — the three `doppler_secret` blocks binding `tls_private_key.<name>.private_key_openssh` to `GIT_{TRANSPORT,PROVISION,REMOVE}_SSH_PRIVATE_KEY` | `git-data.tf` | No |

Link 5 is the half the app actually holds: `git-data-replication.ts` reads
`GIT_TRANSPORT_SSH_PRIVATE_KEY` for ordinary push and fetch, `GIT_PROVISION_SSH_PRIVATE_KEY` to
provision, and `GIT_REMOVE_SSH_PRIVATE_KEY` to erase. It is also the **only** edge in the whole map
with zero existing coverage — the app-side tests `vi.stubEnv` the env *names* with stub values, which
proves the app reads the right variable and is structurally incapable of seeing which Terraform
resource fills it. All three `doppler_secret` addresses are in the 20-address birth target set, so
the dispatch this gate guards is the apply that creates the binding.

At link 5 the assertion is an **identity map, not a cardinality check**: a permutation is as fatal as
a collapse, and three distinct secrets pointing at three distinct keys in the wrong order is a fully
inverted authorization map that every distinctness test passes.

The rehearsal root is deliberately **outside** the assembly — it collapses all three slots by design,
and including it would make the guard permanently red. Scoping is positive (D3).

**Implementation shape: one resolution walk, not five independent assertions.** Links 2 and 3 are pure
identity maps (`git_transport_pubkey = var.git_transport_pubkey`;
`git_transport_pubkey = local.git_transport_pubkey`). You *traverse* an identity map; you do not
assert on it. Five independent per-link assertions would mean five extractors, five normalisers, five
de-duplications and five messages over three files — and would still miss a hop nobody anticipated.

The gate instead resolves each slot to its terminal resource and then applies five predicates:

1. slot count == distinct terminal count == 3 (covers M1–M6, M9)
2. every terminal is a `tls_private_key.<name>` address — never a `var.`, a `data.` source, a
   `file()`, or a hardcoded `"ssh-ed25519 …"` literal (M10). The predicate rejects *every* non-resource
   terminal, not just the variable case, because a literal is address-free and would otherwise fall
   through the extractor rather than be rejected
3. every named resource block exists in the root (M11)
4. **the authority map is an ORDERED composition, not a bijection** (M12, M13, **M16–M18**)
5. each side reads the **correct attribute** — `public_key_openssh` for the slots,
   `private_key_openssh` for the secrets (**M19, M20**)

**Predicate 4 is ordered, and that word is load-bearing.** An earlier draft said "the private-half map
is the expected bijection", which is strictly weaker and the battery could not tell the difference: M12
and M13 are both *double-use* collapses (one resource referenced twice, one referenced zero times), so
a pure cardinality check reds on both and looks identical to an identity check. A **permutation** —
transport and provision swapping terminals, or a 3-cycle through the three `doppler_secret` values —
is perfectly bijective, three-distinct, all-resources-present, and passes every cardinality predicate
while handing each authority the wrong key.

So the assertion is per-authority: for each `A ∈ {transport, provision, remove}`,
`resolve_slot(script_A) == resolve_secret(doppler_name_A)`, joined on the extracted terminal address
so it stays independent of how the resource is spelled (H3 still passes). The
`{forced-command script ↔ Doppler name}` table is hardcoded from the design and **anchored to a third
artifact** — `apps/web-platform/server/git-data-replication.ts`, whose header prose already documents
`GIT_PROVISION_SSH_PRIVATE_KEY → git-data-provision.sh` and the transport equivalent — never derived
from either file under test.

This is *strictly stronger* than per-link assertions because it composes — an unanticipated hop breaks
the walk rather than slipping past five checks — and its diagnostic is better: it names the hop at
which two chains converged.

**The set the guard quantifies over — the three forced-command script names — is hardcoded from the
design (ADR-068), never parsed back out of the artifact under test.** Deriving it from the template
would make the assertion `S == S`. The literal `3` lives in exactly one named constant in the gate
library, with the ADR-068 citation inline, because it must agree across the slot count, the terminal
count, the resource count and the secret count.

**Mutation matrix.** Every row must drive the gate RED. Derived from the design, before the guard is
written.

| # | Mutation | Link | Why it must red |
|---|---|---|---|
| M1 | All three `command=` lines interpolate `${git_transport_pubkey}` | 1 | The headline collapse |
| M2 | Only **two** collapse; transport stays distinct | 1 | The near boundary (2 distinct vs 3) — the role A11 plays in the existing suite |
| M3 | Template untouched; module binds `git_provision_pubkey = var.git_transport_pubkey` | 2 | Defeats any template-only or endpoints-only guard |
| M4 | Module call passes `git_remove_pubkey = local.git_transport_pubkey` | 3 | Root-level collapse, template and module canonical |
| M5 | Local resolves `git_remove_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)` | 4 | The quietest public-half collapse |
| M6 | A fourth `command=` entry reusing an existing var | 1 | Cardinality is not distinctness |
| M7 | **The guard's own dispatch:** extraction yields zero pairs | — | "0 distinct of 0" must ABORT. Zero is a broken instrument, never a pass |
| M9 | Two locals reach one resource via an alias or extra whitespace so the RHS strings differ | 4 | De-duplicate on the extracted address, never the raw string |
| M10 | A local is re-pointed at `var.git_remove_pubkey` carrying a default equal to the transport key | 4 | The apply-time collapse the address walk would otherwise miss |
| M11 | A local names `tls_private_key.git_remove` but no such resource block exists | 4 | Three dangling aliases satisfy reference-distinctness |
| **M12** | `doppler_secret.git_transport_ssh_private_key.value` → `tls_private_key.git_remove.private_key_openssh` | **5** | **The app's transport key becomes the erase key. Every ordinary push runs `rm -rf`. All of links 1–4 stay green** |
| **M13** | `doppler_secret.git_remove_ssh_private_key.value` → `tls_private_key.git_transport…` | **5** | The mirror: erasure hits the transport wrapper, which rejects non-git verbs, so every account deletion files a **false** "Art. 17 erasure failed" alarm |
| **M14** | An `apps/web-platform/infra/locals_override.tf` re-points a local at apply time | 3, 4 | Terraform merges `*override.tf` over the primary config. The gate reads only the file it is handed, so it is blind unless it ABORTs on the existence of any override file |
| **M15** | A second `module "git_data_userdata_v2"` with collapsed arguments, with `hcloud_server.git_data.user_data` re-pointed at it | 3 | The gate reads the block it was told to read and releases. Assert exactly one module instance with that `source`, and pin the **whole** `base64gzip(module.<label>.rendered)` expression — not just the label, or a `coalesce()`/conditional slips a second render in beside it |
| **M16** | **2-swap at link 4:** `git_transport_pubkey` and `git_provision_pubkey` exchange terminals | 4 | Three slots, three distinct terminals, all resources present, each secret still name-matched. **Every cardinality predicate passes.** The app's transport key authenticates into the provision slot |
| **M17** | **2-swap at link 1:** two `command=` script names exchange their `${…}` vars | 1 | Set-equality on script names passes and cardinality passes. Only the ordered composition catches it |
| **M18** | **3-cycle at link 5:** transport→provision's key, provision→remove's, remove→transport's | 5 | Perfectly bijective and three-distinct. This is the row that proves predicate 4 is ordered rather than a cardinality check wearing the word "bijection" |
| **M19** | A pubkey local reads `tls_private_key.git_remove.private_key_openssh` | 4 | Address-distinct, terminal-valid, bijective — and it bakes a **private** key into `user_data`, which is gzipped into Hetzner instance metadata |
| **M20** | A `doppler_secret.value` reads `.public_key_openssh` | 5 | Publishes a public key as the app's authentication material. Green under every address-only predicate |
| **M21** | **Deletion:** one `command=` line removed entirely | 1 | Two slots holding two distinct keys. Promoted from prose — a row with no number does not get built |
| **M22** | **Partial extraction:** a local resolves through an intermediate (`trimspace(local.some_key)`) so its RHS contains no `tls_private_key.<name>` | 4 | Yields 2 addresses from 3 slots. M7 covers *zero* extracted; nothing covered *2 of 3*. Must ABORT, not HOLD |
| **M23** | **Sibling-file relocation:** a pubkey local moved to a new `.tf` in the same root and re-pointed | 4 | The row that proves root-directory scoping. Promoted from Test Scenario prose |
| **M24** | Same resource, different attribute in two slots (`public_key_openssh` vs `public_key_pem`) | 4 | Two byte-different RHS strings, one key. Pins that de-duplication strips the attribute and keys on `tls_private_key.<name>` |
| **M25** | `hcloud_server.git_data` gains `lifecycle { ignore_changes = [user_data] }` | — | This silently disarms **D9's entire premise** that a replace is the only post-birth re-render route. The guard depends on that fact, so it must pin it |
| **M26** | A **fourth** `authorized_keys` line with **no** `command=` at all | 1 | Contributes no slot, so slot count stays 3 and set-equality on script names passes — **the gate releases**. That key gets the raw `git-shell -c "$SSH_ORIGINAL_COMMAND"` path, the CWE-22-unfenced path the transport wrapper exists to replace. Closed by asserting the block holds exactly three non-blank lines, every one a forced command |
| **M27** | An extra option appended to a `command=` line (`environment="GIT_DATA_REPO_ROOT=/srv"`) | 1 | The gate asserts the script name and terminating `${…}`, not the **option set**. Invisible today, and live the moment anything sets `PermitUserEnvironment yes` — two individually-invisible edits composing into a rooted `rm -rf` |

M8 (unreadable production root) is **folded into the fail-closed argument arm** rather than kept as a
separate row: in every sibling gate in this library the missing and unreadable cases land in the same
`[[ ! -f ]]` / `[[ ! -r ]]` branch. Its fixture uses a **dangling symlink** (the mechanism A4/A5
already use — `chmod 000` is a no-op under root and in some CI containers), and both the missing and
unreadable variants are exercised.

**The vacuity trap this matrix exists to close.** The natural implementation is a left-hand-side grep,
and *a collapse never touches the left-hand side*: `grep -c '_pubkey' git-data.tf` returns 3 on a fully
collapsed tree, and the template's three `${…}` names stay distinct under every collapse at links 2–5.
An LHS-only guard is true today, **stays true through the exact defect it names**, and converts
"unproven" into "proven" — strictly worse than no guard. Every arm extracts, normalises and
de-duplicates the **right-hand side**, and every link carries a measured collapse fixture.

**Comment-stripping is mandatory, and the ABORT must be QUOTE-AWARE — a blanket one is born red.**

The cloud-init header immediately above the `authorized_keys` block names all three wrappers in prose,
so stripping `#` comments before asserting is required. Separately, both existing strippers in this
library handle only `#`, while HCL also permits `//` and `/* */`, so an unparseable comment form must
fail closed.

**An earlier draft made that ABORT unconditional, and it would have shipped a gate that refuses the
canonical production tree on day one.** Measured this session against
`apps/web-platform/infra/`: **81 `//` occurrences across 19 of the 48 root `.tf` files**, plus `/*` in
several more — and **zero** of them are HCL comments. Every one is a URL inside a string literal or a
path glob inside a `#` comment. `git-data.tf` itself carries one, at
`git_data_betterstack_ingest_url = "https://s2734275.eu-central-1a.betterstackdata.com/"`.

So the rule is: **ABORT on `//` or `/*` only OUTSIDE string literals.** The library already contains
the machinery — the quote-aware YAML stripper Phase 2.1 names, which tests whether the delimiter sits
inside an open quote rather than what follows it. Reuse that discipline for HCL.

This is worth recording as more than a bug fix, because it is the plan's own warned-about failure
appearing one level up: the premise ("no such comment exists in the three files today") was measured
under the **three-file** framing and carried forward unchanged after D2 widened the unit to the whole
**48-file root**. It was also already false in the narrow framing. A premise measured under one scope
does not survive the scope widening that a later decision performs.

**Blast radius, which is why this is the highest-severity finding in the review.** Per D8 the suite
runs on every PR via `ci.yml`, unfiltered. A false-RED here would not merely fail this feature's own
tests — it would redden **every pull request in the repository** until someone deleted the arm. That
is precisely how a guard gets deleted six months later, so the live-tree arm must also produce a
**self-diagnosing** failure that distinguishes *"the gate could not parse the production root"* from
*"the production root violates the property."*

**Harness rows.** Mutations of the *suite*, not the guard.

| # | Harness edit | Expected |
|---|---|---|
| H1 | Delete any one new arm | RED via the anti-vacuity floor, raised by exactly the number of new **verdicts** |
| H2 | Neuter `fail()` so it appends without counting | RED via the existing ledger reconciliation |
| H3 | **Must-PASS, non-canonical:** three distinct but differently *named* vars, threaded consistently through every link to three distinct resources and three correctly-named secrets | **PASS.** The contract is the map, not the canonical spelling. A gate that reds here is string-matching the live file |
| H4 | **Must-PASS, non-canonical:** canonical tree with whitespace and comment noise on the `command=` lines | **PASS.** Anchored on content, not byte-exact lines |
| H5 | **Must-PASS:** a `https://…` URL in a local and a `/*` path glob inside a `#` comment | **PASS.** The row that would have caught the born-red blanket ABORT before it shipped |
| H6 | **Must-PASS:** a map-typed intermediate (`locals { git_keys = { transport = … } }` then `trimspace(local.git_keys.transport)`) | **PASS** up to a stated hop budget. An ordinary DRY refactor must not read as the defect. Beyond the budget it is an **ABORT naming the hop**, never a HOLD — a HOLD here falsely accuses the exact defect, which is how a guard gets deleted |
| H7 | **Must-PASS:** the three `tls_private_key` blocks relocated to a sibling `.tf` in the same root, correctly wired | **PASS.** The benign twin of M23. D2 claims root-scoping removes this false-RED; nothing proved it |
| H8 | **Must-PASS:** unrelated sibling keys and secrets present in the root | **PASS.** The live root already holds `tls_private_key.ci_ssh` and `.proxy_server`, so any resource-*enumerating* predicate is already wrong against production |

**The fixture needs a production-matching noise floor, not a clean three-file tree.** A minimal
fixture is exactly the "wrong but self-consistent fixture" failure mode, and it is what would have
hidden the born-red comment rule. The synthetic root must carry, at minimum: ≥2 unrelated
`tls_private_key` resources, ≥2 unrelated `locals` blocks in sibling files, a `https://` URL in a
string, a `/*` glob inside a `#` comment, and ≥1 unrelated `doppler_secret`.

**Four anti-vacuity paths beyond the rc-127 hole, each closed explicitly:**

- **A `sed` that lands in the wrong region.** The `assert_mutation` precedent guards landing with
  `cmp -s`, which proves the file *differs* — not that the edit landed where the arm claims. The
  fixture has three near-identical `command=` lines, so M1 written as a non-global `s///` rewrites only
  the first and **silently implements M2**: both red, the battery reports 2-for-2, and one row is
  measuring the other. Every arm therefore asserts post-mutation **shape**, not inequality — M1 checks
  the collapsed var appears 3 times, M2 that it appears 2, M12 that the transport secret's `value`
  changed *and* the other two did not.
- **Reason collisions on both verdicts.** Matching only a leading `HOLD`/`ABORT` token is **weaker
  than the precedent already in this suite** — `_a_abort` matches rc *and* a needle. Every verdict is
  matched as exact rc **plus a per-reason token**, so M3 (link 2) cannot pass on a HOLD naming link 4,
  and a fixture malformed in an unrelated way cannot pass an ABORT arm for the wrong reason.
- **Substring bleed.** HOLD and RELEASED share vocabulary (`distinct`, erase authority, authorization
  map), so matches anchor at line start on the gate's own message prefix.
- **The must-PASS side can go vacuous too.** A gate that early-`return 0`s on a tree it failed to
  parse satisfies a bare rc=0. H3–H8 assert rc=0 **and** the RELEASED token, symmetrically with the
  RED side — the shape `_a_hash` already uses.

**The floor needs two ledgers, not one.** AC10's verdict accounting catches a *deleted* arm, but an
arm edited from a RED expectation to a PASS expectation keeps the verdict count identical and the
floor never moves. Count RED-expecting and PASS-expecting arms separately.

H1 and H2 remain **prose expectations**, not new arms: both mechanisms already exist and are already
self-tested in the suite. Promoting them would inflate the floor without adding coverage.

H3 is the row that matters most — without a must-PASS input differing from canonical in a way the
contract permits, the battery cannot tell a real assertion from one that rejects everything.

**Fixture reality — the plan's earlier claim about this was wrong and is corrected here.** The suite's
existing `_a_tree` / R2 fixture builds only `ci.yml`, `modules/git-data-userdata/main.tf` and nine
payload stubs — shaped for the hash function. **It contains no `git-data.tf`, no `locals`, no
`tls_private_key` resource, no module call and no `doppler_secret`,** so links 3, 4 and 5 do not exist
in it. And `_a_abort` is hardwired to call `git_data_rung2_user_data_sha256`; it cannot assert on this
gate without parameterisation, which would touch ~17 existing call sites and become exactly the
cross-consumer widening this plan claims not to perform.

So Phase 1 must **build a new five-link synthetic production-root fixture**, and follow the
`assert_holds` / `assert_mutation` shape from `apps/web-platform/infra/git-data-luks.test.sh` (which
already guards against a mutation silently failing to land) rather than the `_a_abort` shape. That
helper is single-file while this gate reads three files, so it needs a copy-then-sed tree wrapper.
This fixture is the real cost driver of Phase 1 and is budgeted as its own task.

**The new assert helper pins an exact rc, mirroring `_a_abort`'s `rc -eq 1`.** If it checked merely
"non-zero", then during Phase 1 RED every M-arm would call an undefined bash function, get rc 127,
and **pass vacuously** — the whole RED phase would be theatre.

**ABORT and HOLD must be distinguishable**, and the plan pins the mechanism rather than leaving it to
implementation: ABORT (instrument refusing — no argument, unreadable root, unparseable comment form,
override file present) and HOLD (the property is violated) carry distinct leading tokens in their
messages, and the assert helpers match on those tokens, not merely on a non-zero rc.

## Architecture Decision (ADR/C4)

### ADR

**No new ADR. Amend ADR-149 instead**, adding the authorization-map condition as item **10** of its
`### Interlock release checklist` (which today runs 1–9; item 7 is the DC-2 replacement mandate and
item 9 was added by #6982 on the same precedent).

The reasoning is deliberate and is the reason a sibling ADR would be wrong. The three-key separation
is already decided — ADR-068's, with its rationale stated in place in the cloud-init template:
separate keys give provisioning, ref-write and erasure authority separate blast radii. This plan
enforces that existing decision; it does not make a new one. But the thing that *gates the dispatch*
is ADR-149's checklist, and that checklist is valuable precisely because it is the single enumeration
of what holds the button. Recording a new mechanical hold anywhere else splits that enumeration in
two — which is the exact failure ADR-149's own critique of "prose in a different file from this
button" names. So: amend, do not create.

The amendment is an in-scope task of this plan, not a follow-up.

**Ordinal note:** no new ordinal is claimed, so there is no collision risk to re-probe at ship time.

### C4 views

**No impact.** Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), by enumeration
rather than by a keyword grep:

- **External human actors:** none added or changed. The approving human is already modelled via the
  `sentry -> founder` paging edge and the environment approval; this plan changes what that human is
  *shown*, not who they are or what they can reach.
- **External systems / vendors:** none added. No new webhook, API, or third-party store.
- **Containers / data stores:** none added. `gitDataStore` already exists and its description already
  narrates the birth interlocks in detail.
- **Actor↔surface access relationships:** none changed. This is the load-bearing check for this
  particular plan, and it is worth stating precisely: the plan asserts that an existing authorization
  topology is what it already claims to be. It grants nothing, revokes nothing, and moves no edge.
  A collapse *would* change an access relationship — which is exactly why the guard exists — but the
  guard's own landing does not.
- **Derived cardinalities:** the plan adds no cron monitor, heartbeat slug, or workflow, so no count
  embedded in `model.c4` edge prose moves. Backed mechanically by running
  `plugins/soleur/test/c4-count-parity.test.sh`, not by the actor rubric above.

## Infrastructure (IaC)

Skipped — no new infrastructure. This plan provisions no server, service, cron, vendor account, DNS
record, cert, secret, firewall rule, or webhook. It adds a static assertion to an existing test
library, two arms of disclosure prose, and test coverage. No `.tf` file is edited; `git-data.tf` is
read by the guard and not written.

## Encryption Posture

Skipped — the plan introduces no persistent data store and no new cross-component connection. C2(a)
*discloses* an existing encryption posture rather than changing one: the plaintext-at-rest state of the
git-data store is already a ledgered exception in `scripts/encryption-posture-ledger.json` tracked by
#6897, and this plan neither creates that exception nor alters its terms. Making a ledgered exception
legible at the moment of approval is a disclosure change, not a posture change.

## Observability

```yaml
liveness_signal:
  what: the authorization-map gate's verdict — as a suite arm on every PR, and as an interlock step on
    both the birth and replace dispatch paths
  cadence: every pull request (ci.yml runs scripts/test-all.sh scripts, unfiltered), plus every
    dispatch of git-data-host-create and git-data-host-replace
  alert_target: the GitHub Actions run goes red; on a dispatch the job fails closed before terraform init
  configured_in: .github/workflows/ci.yml (the `bash scripts/test-all.sh scripts` step),
    scripts/test-all.sh (the `run_suite "tests/scripts/git-data-birth-readiness-gate"` line), and
    .github/workflows/apply-web-platform-infra.yml (both dispatch jobs)
error_reporting:
  destination: GitHub Actions annotation (::error::) on the dispatch paths; suite failure text plus a
    non-zero exit on the CI path
  fail_loud: true — the gate returns non-zero and the job stops before terraform init; the suite exits
    non-zero on any recorded failure and separately on the anti-vacuity floor
failure_modes:
  - mode: the three forced-command slots collapse onto fewer than three distinct keys
    detection: git_data_authorization_map_distinct_gate HOLDs, naming the link that collapsed
    alert_route: PR red at review; on a dispatch the job fails and nothing is planned or created
  - mode: the private halves are misrouted — a doppler_secret publishes the wrong key (links 1-4 stay
      byte-canonical, so this is invisible to every public-half check)
    detection: the link-5 bijection predicate HOLDs (M12/M13)
    alert_route: PR red at review; dispatch refuses
  - mode: a collapse arrives via git-data-host-replace, the only path a re-render can travel after
      birth, and the one with no human approver
    detection: the same gate wired as an interlock in that job (D9)
    alert_route: the replace job fails closed
  - mode: the guard is present but vacuous — extraction yields zero or fewer pairs than slots
    detection: the gate ABORTs rather than reporting agreement (M7, and the partial-extraction row)
    alert_route: CI red on the suite; dispatch refuses
  - mode: the guard is bypassed structurally — an *override.tf, a second module instantiation, or a
      pubkey local moved to a sibling .tf in the same root
    detection: the override ABORT (M14), the single-module assertion (M15), and root-directory
      scoping rather than single-file scoping
    alert_route: CI red; dispatch refuses
  - mode: arms are deleted or the suite exits early
    detection: the anti-vacuity floor, raised by exactly the number of new verdicts
    alert_route: CI red, naming the floor and the observed count
logs:
  where: GitHub Actions run logs — the suite's per-arm ok/FAIL lines on the CI path, and the
    interlock step's ::error:: annotation plus the gate's own HOLD/ABORT text on the dispatch paths.
    No host-side logging surface exists or is needed: the gate is static and never contacts a host.
  retention: GitHub's default Actions log retention (90 days); the verdict is also reproducible on
    demand from any checkout by running the suite, so the log is a convenience rather than the record
discoverability_test:
  command: bash tests/scripts/test-git-data-birth-readiness-gate.sh
  expected_output: "=== 116 passed, 0 failed ===" — the "ok   anti-vacuity floor" line reports the
    same 116
```

No credentials are required: every arm is static, runs against copied trees in a temp directory or the
committed production root, and there is no SSH anywhere in the verification path.

## Decisions

These are the forks the plan resolves deliberately. Each records the alternative and why it lost.

### D1 — The assertion lives in a NEW top-level gate function, not folded into either existing gate

`git_data_authorization_map_distinct_gate <path-to-git-data.tf>`, added to
`tests/scripts/lib/git-data-birth-readiness-gate.sh`, deriving the template and module paths from
`dirname` — mirroring how `git_data_rung2_rehearsal_gate` derives its evidence path.

**Note the argument is the production root, not the template.** That is what lets one function reach
all five links; a `(cloud_init)` contract structurally cannot reach links 3, 4 or 5.

- **Not folded into `git_data_birth_readiness_gate`:** DC-2 makes that function's mechanism a
  *deletion target*, and ADR-149 sequences the replacement as a dispatch precondition rather than
  post-release cleanup. A permanent property hung on a function scheduled for removal either gets
  dragged out with it or forces a re-home under dispatch-time pressure. Separately, its hardcoded
  RELEASED message enumerates what it does **not** prove; adding an orthogonal property makes that
  message false.
- **Not folded into `git_data_rung2_rehearsal_gate` — this one is fail-open and disqualifying.** That
  function has a second call site in `.github/workflows/infra-validation.yml` ("Rung-2 evidence
  freshness") which `exit 0`s when the evidence file is absent, by design. A distinctness arm folded
  in there goes silently dormant in exactly the window where the template and roots are being re-cut.
  Verified at that file's `if [[ ! -f "$EV" ]]` / `exit 0` block.
- **The dispatch job already states the principle for this shape**, verbatim at the second interlock:
  *"Separate step and separate function, because the two gates assert DIFFERENT facts and a reader
  should be able to tell which one held."* A third step is the established shape, not a new one.

### D2 — The guard quantifies over all FIVE links, over the whole Terraform ROOT; template-only is rejected as actively harmful

Recorded in full in the Guard Contract. Three parts, each of which an earlier draft got wrong:

- **Template-only is actively harmful.** A collapse never changes the left-hand side, so a
  template-only guard is true today and *stays true through the exact defect it names*. It converts
  "unproven" into "proven", which is worse than no guard.
- **Four links were not enough.** The private-half distribution (link 5) is where the app's authority
  actually comes from, and it is invisible to every public-half check.
- **One file is not the unit; the ROOT DIRECTORY is.** Terraform merges `locals`, `resource` and
  `module` blocks across **every** `.tf` in a root. Measured: the production root holds ~35 `.tf`
  files and `locals {` blocks in at least ten of them. So a guard handed only `git-data.tf` can be
  defeated by moving one local into a new `git-data-keys.tf` — `git-data.tf` stays byte-canonical and
  shows two distinct locals. The gate therefore reads **`dirname/*.tf` plus `*.tf.json`**, exactly as
  the hash function already globs the module directory. This also makes M11 (resource-existence)
  evaluable, and removes a false-RED against the perfectly legitimate layout where the three
  `tls_private_key` blocks live in a sibling file.

**Cardinality must be EXACT, never "the values present are pairwise distinct."** Every mutation in an
earlier draft was a *substitution*; none was a *deletion*. Deleting one `command=` line leaves two
slots holding two distinct keys, and Terraform tolerates the now-unused `templatefile` map key, so a
distinctness-only guard goes green on a host that lost a forced-command boundary. The assertion at
every link is `exactly 3`, and the `command=` script-name set is asserted by **equality** against the
design-derived set — not membership, because a *fourth* entry naming a fresh script with a fresh
variable is a new forced command on the host that a membership test ignores entirely.

**What the gate's message must therefore say**, per #8009's requirement that it state plainly which of
the two it proves: it proves **that the production Terraform root statically binds three distinct
forced-command slots to three distinct `tls_private_key` resources, and publishes each one's private
half under the Doppler name whose consumer holds that authority**. It does **not** prove the rendered
key material differs, because rendering requires terraform and real resources. The message says
exactly that rather than letting a reader infer the stronger claim.

### D3 — Root-scoping is positive (by argument), never by exclusion

The gate reads only the root directory it is handed, plus the template and module derived from its
`dirname`. It never walks upward and never enumerates siblings to exclude, so there is no
`--exclude rung2-rehearsal/` for a future edit to hide behind. A future third root is not
*exempted* — it is simply *not covered*, a visible gap rather than a silent pass.

Two refinements review forced, both fail-closed:

- **A missing or unreadable root, template or module is an ABORT, not a skip.** The fixture uses a
  dangling symlink, because `chmod 000` is a no-op under root and in some CI containers.
- **`*override.tf` / `*override.tf.json` in the root is an ABORT** (M14). Terraform merges override
  files *over* the primary configuration, so one added file re-points a local at apply time while
  every primary file stays canonical. This is the one hole positive scoping does not close by itself,
  and D3's earlier "no escape hatch" claim was wrong without it. None exists today, and nothing else
  in the repo would notice one appearing.

### D4 — The allowlist justification is corrected surgically; the phrase is NOT deleted

The premise an earlier draft worked from was wrong, and correcting it changes the shape of the fix.

**Measured: `identity-shaped render var` appears at exactly ONE site in the gate library** — the HOLD
message. The comment block above the constant lists the pubkeys among the templatefile *arguments* but
makes no identity claim about them. There is no wrong claim there to correct, only a missing one.

**And the phrase must not be deleted, because it is accurate for five of the eight tokens.**
`host_name`, both volume ids, `doppler_token` and `doppler_config_name` genuinely name which
host/volume/credential and never what boots. Only the three pubkeys are misdescribed. An AC demanding
`grep -c` return 0 would delete a correct description of the majority to fix its application to a
minority.

So the correction is:

1. **Add** a sentence to the comment block stating that the three pubkey tokens diverge in
   **capability count**, not identity — collapsing them moves erase authority onto the transport
   identity — and that this is what the new gate asserts.
2. **Minimally generalise** the HOLD message's phrasing (e.g. "a render var whose divergence does not
   change the host's capability set") so it stops implying the pubkeys are an identity case.
3. Leave the token list and every consumer byte-identical.

**No widening**, so `hr-type-widening-cross-consumer-grep` does not fire — but the sweep still had to
be done, and an earlier draft's claim that the constant has "exactly two consumers" **undercounted**.
Measured, there are six: the in-file membership loop and HOLD message, two `case " $GIT_DATA_… "`
sites plus a `grep -oE` over the gate file in `git-data-rung2-rehearsal.test.sh`, and two sites in
`tests/scripts/test-git-data-rung2-evidence-capture.sh`. The conclusion (no widening) survives; the
evidence for it had to be redone. `hr-write-boundary-sentinel-sweep-all-write-sites` **does** fire —
see the sweep table below.

**The sweep, and the hash-bound copy that cannot be fixed here.** The justification phrase propagates
across nine files. One is forbidden (`git-data-rung2-boot-evidence.env`) and one is **hash-bound**:
`modules/git-data-userdata/variables.tf` carries the *most explicit* statement of the wrong claim —
`MAY DIVERGE (identity-shaped — they name WHICH host/volume/credential, never WHAT boots)` over all
eight tokens. Correcting a **comment** there would move `3a2392fb…c1725`, void the rung-2 evidence and
buy a fresh **paid** Hetzner rehearsal.

So the plan deliberately leaves an uncorrected copy in a hash-bound file, and does not hide it: it is
recorded here, named in the gate library's corrected comment as a known divergence with its tracking
issue, and pinned byte-identical by an AC so an implementer following "correct every site" cannot walk
into it. Leaving it silently would be the defect; leaving it recorded is the only option that neither
voids the evidence nor pretends the sweep was complete.

### D5 — C2 lands in `## Before you dispatch`, NOT in the DO-NOT-DISPATCH banner

This is the decision most likely to be got wrong, because C2(b) *already exists* — inside the banner.

The banner is deleted by #7025 (ADR-149 checklist item 8), explicitly out of scope here. If the three
statements live in the banner, C2 evaporates the moment #7025 lands — precisely when the dispatch
becomes reachable. So they go in `## Before you dispatch`, which survives, and the banner is left
byte-identical.

**One coupling to record:** two of that section's six rows currently depend on the banner ("The banner
above is cleared"; "The rehearsal evidence named in the banner"). Those go dangling when #7025 lands.
This plan does not fix them — that is #7025's edit — but names them so #7025 inherits a known item
rather than a surprise.

### D6 — The disclosure runs in a PRECEDING, UN-GATED job, because the approver approves blind

An earlier draft placed the disclosure inside the gated job and claimed it reached the approver. It
does not, and the repo says so in three places.

GitHub holds an environment-gated job in `Waiting` **before its first step runs**. The job's own header
says the approver "approves BEFORE any step runs, so they cannot verify a plan," and the runbook's
`## Dispatch` section says "The approver approves blind… Everything that actually protects the store
runs after approval." A step placed after the interlocks and before `terraform apply` therefore
executes strictly **after** the approval click, and `$GITHUB_STEP_SUMMARY` is a post-run artifact.
Property 4 would have been unmet while AC21 passed — the plan's own cited defect class, reproduced.

**The fix, with an exact in-file precedent.** Add a separate `git_data_birth_disclosure` job carrying
the identical `if:` guard and **no `environment:`**, writing the three statements to
`$GITHUB_STEP_SUMMARY`; then `git_data_host_create` gains `needs: [git_data_birth_disclosure]`. The
same workflow already does this — the `apply` job carries `needs: preflight`, and `preflight` declares
no environment. While the gated job sits in `Waiting`, the run summary page — the page the approval
notification links to, and the page the *Review deployments* button lives on — already renders the
disclosure. That is the only mechanism GitHub offers to put text in front of this reviewer before the
click: environments have no description field, no custom protection-rule text, and `environment.url`
renders post-deployment.

Two consequences to hold: a failing disclosure job **skips** the gated job (acceptable, and
fail-closed), and the workflow-level concurrency group is workflow-scoped, so no deadlock is
introduced.

**Even so, the runbook remains the primary surface** — the operator reads it before typing the
dispatch command, and with `prevent_self_review: false` the dispatcher and approver are the same
person. The disclosure job is what makes the same statements unmissable on the approval page itself.

**The dispatch input form is not used as a third surface.** The `confirm` field's description is the
only text rendered as the token is typed, and that field's own description records why it is not the
place: it "accreted one clause per target and no operator reads a field label that long."

**But one input-form defect IS in scope and is fixed:** the `apply_target` description's
`git-data-host-create` clause is **stale** — it tells the operator the rung-2 interlock refuses and "a
dispatch today exits 1 before planning," which stopped being true when the evidence file merged in
#8002. That label is rendered at the exact moment of firing, and it currently says the opposite of the
truth. Correcting it is a one-line edit on the highest-read pre-click surface in the system.

### D7 — Guard 2 (the rehearsal counter-assertion) is CUT

An earlier draft added three arms to `git-data-rung2-rehearsal.test.sh` asserting that the rehearsal
binds all three pubkeys to one key. Cut, for three reasons that converged from two independent
reviews:

- **It buys zero coverage of the failure mode in `## User-Brand Impact`.** Guard 1 covers the entire
  production path. Guard 2 asserts a documentation fact.
- **Its red means "you improved something."** If #8010 or any successor ever wires the rehearsal to
  three distinct keys — the obviously-right long-term move — Guard 2 blocks that PR, and the next
  person's only visible remedy is deleting the arm. A ratchet pointed backwards.
- **It was the sole reason for a large block of cost and hazard**: a second suite in the edit set, a
  second anti-vacuity convention (`cases` vs `_ran`) that the plan then had to spend two sections
  warning about, plus a decision, a sharp edge and two ACs. Every one of those disappears with it.

**Replaced by one sentence** in the D4 comment correction — same file, already in scope, zero new
arms: *`rung2-rehearsal/rehearsal.tf` binds all three slots to `tls_private_key.rehearsal` by design;
the rehearsal structurally cannot exercise the authorization map, which is why this static gate
exists.* That converts "the rehearsal is out of scope" from an absence into a recorded fact, which was
Guard 2's only real value.

### D8 — PR-time coverage is bought with a LIVE-TREE ARM, not a new workflow step

An earlier draft proposed a new step in `.github/workflows/infra-validation.yml`. Rejected on
measurement:

- `ci.yml` runs `bash scripts/test-all.sh scripts` on `pull_request` with **no `paths:` filter and no
  `if:` gate**, and `scripts/test-all.sh` registers this suite via `run_suite`. Every PR already runs
  every arm in it.
- `infra-validation.yml` is `paths:`-filtered to `apps/*/infra/**`, so a step there would be
  **strictly narrower** than what `ci.yml` already provides — and it is the workflow holding the
  fail-open dormancy precedent.

So the PR-time coverage is a **live-tree arm inside the suite**, following the precedent already
there: the suite calls `git_data_birth_readiness_gate` against the real `cloud-init-git-data.yml`, and
arm A1 makes a missing live file a **loud failure**, never a skipped arm. The new arm does the same
against the real production root.

The suite header's rule — "EVERY ASSERTION RUNS AGAINST A SYNTHESIZED FIXTURE, NEVER THE LIVE FILE",
narrowed in 2026-08 to "no arm asserts the GATE'S VERDICT on the live template" — must be **amended in
the same commit, with a stated justification**, the way A1's was. The justification here is that the
property is invariant rather than time-dependent, so the header's original rationale does not apply.
Without that amendment the arm is a rule violation; without the arm, the gate never touches the real
tree anywhere in CI until dispatch.

### D9 — The gate ALSO guards `git-data-host-replace`, which is the only path that matters after birth

Measured: the `git_data_host_replace` job has **no `environment:`** — no human approver at all — and
sources only `git-data-host-replace-gate.sh`, a destroy-guard. It carries neither birth interlock.

That matters more than it first appears. `user_data` is ForceNew with no `ignore_changes`, and ADR-115
excludes git-data from the reboot primitive, so after the birth the **only** route by which a
re-rendered `authorized_keys` block reaches the host is a replace. The realistic incident is therefore
not a collapsed *birth* — that fires once, ever — but a collapsed *replace*, on the path with no
approver and, without this decision, no distinctness gate.

So the gate is wired into three places, each buying something the others do not:

| Surface | Catches |
|---|---|
| The suite's live-tree arm (every PR, via `ci.yml`) | The author, in review, before merge |
| `git_data_host_create`'s third interlock | Merge-order interactions and force-merges, at the one birth |
| `git_data_host_replace`'s interlock | **Every post-birth re-render — the only path a collapse can travel once the host exists** |

**A caveat that must ship with D9, not be discovered later.** `git_data_host_replace` has no
`environment:`, and therefore no `deployment_branch_policy`. `workflow_dispatch` runs the **selected
ref's** workflow *and its scripts*, so the gate this job sources from `${GITHUB_WORKSPACE}` is
supplied by the branch it is meant to police. This workflow already states that reasoning verbatim for
a sibling job, and rejects a `github.ref` guard as strictly weaker for the same reason.

Measured for contrast: `web-platform-infra-apply` carries a `branch_policy` with exactly one custom
policy, `main` — the **birth** path is ref-pinned; the replace path is not.

So D9's coverage is honest only when stated as: against an accidental collapse merged to `main` and
dispatched from `main`, the replace interlock works. Against a deliberate actor with repo write, it
does not.

**Scope split, decided during one-shot adjudication (2026-09-10).** An earlier revision prescribed
the remedy — give `git_data_host_replace` an `environment:` with a main-only branch policy — as part
of Phase 4.2. That is **removed from this PR** and filed as **F11**. Two reasons, both measured:

1. It is not a local fix. This workflow's own `confirm` description records a *deliberate,
   documented* posture that the replace-class targets carry no `environment:` reviewer gate —
   naming `registry-luks-recut`, `registry-host-replace`, `registry-region-migrate`,
   `inngest-host-replace` and `git-data-host-replace` together, and stating that for those "the gate
   chain, the destroy-guard and the id-pin are the entire protection." Changing one of the five
   inside a PR scoped to pubkey distinctness makes the fleet inconsistent and decides a
   fleet-wide policy question as a side effect.
2. It changes an authorization control on a **destructive** production path. Adding a required
   approval to an emergency host replace is an operational trade the operator should take against
   all five siblings at once, not inherit from a chore PR.

**What this PR ships instead:** Phase 4.2 still wires the distinctness gate into
`git_data_host_replace` — that is pure defence-in-depth and costs nothing. What it does *not* do is
claim the resulting interlock is non-circumventable. D9's limitation is stated verbatim in the
gate's own HOLD message and in the runbook, so the guard cannot imply protection it does not have.
A guard that names its own boundary is not the defect class #8009 is about; a guard that hides it
would be.

## Implementation Phases

Phase order is load-bearing: the failing tests land before the gate
(`cq-write-failing-tests-before`), the gate is wired before the disclosure that describes it, and the
hash re-check gates the push.

### Phase 0 — Preconditions (verify, change nothing)

- 0.1 Confirm the hash still reads `3a2392fb…c1725`.
- 0.2 Baseline the suite: `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → `80 passed`.
- 0.3 Re-measure the environment protection rule; record field, scope and date for C2(b).
- 0.4 Read `apps/web-platform/infra/git-data-luks.test.sh`'s `assert_holds` / `assert_mutation`
  helpers. They are the precedent — but they operate on a single file in place, while this gate reads
  a whole root directory plus a template and a module, so they need a copy-then-sed tree wrapper.
- 0.5 Re-run the write-boundary sweep for the justification phrase and confirm D4's disposition table
  still matches the tree.
- 0.6 Read the suite header's "synthesized fixtures only" rule and arm A1's amendment, which is the
  model for the live-tree arm's narrowing (D8).

### Phase 1 — RED: fixture, then failing arms, before any gate code

- 1.1 **Build the five-link synthetic root fixture.** This is the real cost of Phase 1 and has no
  existing analogue: the suite's R2 tree contains no `git-data.tf`, no `locals`, no `tls_private_key`
  and no `doppler_secret`, so links 3, 4 and 5 do not exist in it. The new fixture is a directory
  holding a template with three `command=` slots, a module `main.tf` with the argument map, and one or
  more root `.tf` files carrying the module call, the pubkey locals, three `tls_private_key` blocks
  and three `doppler_secret` blocks. It carries a **production-matching noise floor** — ≥2
  unrelated `tls_private_key` resources, ≥2 unrelated `locals` blocks in sibling files, a
  `https://` URL in a string, a `/*` glob inside a `#` comment, and ≥1 unrelated
  `doppler_secret` — because a clean three-file fixture is what hides a scope-widened premise.
- 1.2 **Build the assert helper pair.** It must (a) invoke the new gate, not
  `git_data_rung2_user_data_sha256` — `_a_abort` is hardwired to that function and cannot be reused
  without parameterising ~17 existing call sites, which would be exactly the cross-consumer widening
  this plan claims not to perform; (b) **pin an exact rc**, mirroring `_a_abort`'s `rc -eq 1`. If it
  accepted any non-zero, then during RED every arm would call an undefined function, get rc 127, and
  pass vacuously — the whole phase would be theatre; (c) match each verdict as exact rc **plus a per-reason token**, anchored at line start — matching a
  bare leading `HOLD`/`ABORT` is weaker than `_a_abort`'s existing rc+needle contract and lets an arm
  pass for the wrong reason.
- 1.3 Add the mutation arms M1–M7 and M9–M25, each mutating exactly one link of a copied fixture.
  Every arm asserts post-mutation **shape** (an expected token count in the mutated region), never
  `cmp` inequality — the fixture's three near-identical `command=` lines make a non-global `sed`
  silently implement a different row.
- 1.4 Add the must-PASS arms H3–H8, each asserting rc=0 **and** the RELEASED token.
- 1.5 Add the **live-tree arm** against the real production root, on A1's shape (missing/unreadable =
  loud fail, never a skip), and amend the suite header rule with its justification (D8).
- 1.6 **Run the suite and confirm it FAILS.** Record the failure text. Any new arm that passes here is
  testing nothing — rewrite it before proceeding.

### Phase 2 — GREEN: the gate

- 2.1 Add the private `_git_data_hcl_nocomment` helper. **Rejustify it correctly**: the library
  already contains *two* divergent comment-strippers (a quote-aware YAML one, and a naive HCL one
  whose own comment states they must not each run their own), so this de-duplicates an extant
  divergence rather than anticipating a future one. Back-port the naive HCL site onto the helper —
  same semantics, and its comment-blanking behaviour is load-bearing for line numbers, so preserve it.
  Leave the YAML stripper alone: different semantics, documented. **If the back-port is not done, cut
  the helper and inline the sed** — a helper with one call site that fails to absorb the existing
  copies is a third copy, which is worse than not factoring.
  Do **not** justify it by DC-2: ADR-149's own #6982 disposition records item 7 as
  "NOT SATISFIABLE AS WRITTEN", so that landing is blocked, not imminent.
- 2.2 Add `git_data_authorization_map_distinct_gate <path-to-production-root>`, fail-closed on a
  missing or unreadable argument, reading `*.tf` + `*.tf.json` across the root and deriving the
  template and module from `dirname`.
- 2.3 Implement it as **one resolution walk plus four predicates** (Guard Contract), not five
  independent per-link assertions. De-duplicate on the extracted `tls_private_key.<name>` address.
  De-duplication strips the attribute and keys on `tls_private_key.<name>`. Assert exact cardinality
  (`== 3`) at every link and **set equality** on the `command=` script names. Assert the **ordered**
  per-authority composition (predicate 4) and the **correct attribute** per side (predicate 5). ABORT
  when the extracted-address count is less than the slot count — that is a partial extraction, not
  agreement — and ABORT (never HOLD) when a resolution hop exceeds the stated budget.
- 2.4 ABORT on `//` or `/*` **outside string literals only** (quote-aware, reusing the library's
  existing quote-aware stripper discipline), and on any `*override.tf` / `*override.tf.json` in the
  root. **A blanket ABORT here is born red** — measured, the live root carries 81 `//` across 19 of 48
  `.tf` files, none of them HCL comments, one of them in `git-data.tf` itself.
- 2.5 Assert exactly one `module` block whose `source` is `./modules/git-data-userdata`, and pin the
  **whole** `user_data = base64gzip(module.<label>.rendered)` expression rather than the label alone.
  Also pin that `hcloud_server.git_data` carries no `ignore_changes` over `user_data` (M25) — D9's
  premise that a replace is the only post-birth re-render route rests on that fact.
- 2.6 Put the literal `3` in one named constant with the ADR-068 citation inline.
- 2.7 Write the HOLD message to name the consequence — the identity the web app holds for ordinary
  push and fetch would also be able to erase a user's repositories — and, per the sibling interlock
  steps, to end with a remedy and a "nothing has been planned or created" reassurance. Do not label
  the gap "Art. 17"; it is Art. 32(1)(d).
- 2.8 Write the RELEASED message to state exactly what it proves (D2), including that it does not
  compare rendered key material.
- 2.9 Raise the anti-vacuity floor, itemised in the file's existing convention, counting **verdicts,
  not arms** — and split it into **two ledgers**, RED-expecting and PASS-expecting, so flipping an
  arm's expectation moves a count.
- 2.10 Run the suite green.

### Phase 3 — The allowlist justification correction

- 3.1 **Add** the capability sentence to the comment block above the constant, including the
  rehearsal-collapse sentence that replaces cut Guard 2 (D7) and the note naming the surviving
  hash-bound divergence with its tracking issue.
- 3.2 **Minimally generalise** the HOLD message so it stops implying the pubkeys are an identity case.
  Do **not** delete the phrase — it is accurate for five of the eight tokens.
- 3.3 Leave the token list and all six consumers byte-identical, and prove it.

### Phase 4 — Wiring

- 4.1 Wire the gate as the third interlock step in `git_data_host_create`, after the rung-2 step and
  before `Terraform init`, wrapped in an `::error::` matching the two sibling interlocks.
- 4.2 Wire the gate into `git_data_host_replace` (D9) — the only path a collapse can travel after the
  host exists, and the one with no human approver. **Gate wiring only.** Do NOT add an
  `environment:` to this job: that remedy is split out as F11 (see D9's scope-split note), because
  it decides a fleet-wide policy the workflow documents for five sibling replace targets. Instead,
  the gate's HOLD message and the runbook must state D9's limitation verbatim — that on this path
  the gate is supplied by the branch it polices, so it holds against an accidental collapse
  dispatched from `main` and not against a deliberate actor with repo write.
- 4.3 Extend `plugins/soleur/test/terraform-target-parity.test.ts`'s job↔gate pairing block with the
  new gate, so 4.1 and 4.2 cannot be silently skipped. This is why AC27 is split.

### Phase 5 — C2 disclosure

- 5.1 Add the `git_data_birth_disclosure` job — same `if:` guard, **no `environment:`**, writing the
  three statements to `$GITHUB_STEP_SUMMARY` — and add `needs: [git_data_birth_disclosure]` to
  `git_data_host_create` (D6).
- 5.2 Add the three statements to `## Before you dispatch` in the runbook (D5), with the AC17/18/19
  calibrations.
- 5.3 Correct the stale `apply_target` description clause for `git-data-host-create`, which currently
  tells the operator the route is held and a dispatch exits 1 — untrue since #8002.
- 5.4 Fix the `## What the job does, in order` drift: it omits the rung-2 interlock and will now also
  omit the third. Renumber to include both.
- 5.5 Leave the DO-NOT-DISPATCH banner byte-identical.

### Phase 6 — Architecture record

- 6.1 Amend ADR-149's release checklist with item 10, inserted after item 9's closing sentence
  (`sized for the burst with the burst now bounded by W4's git config + the gc timer`) and before the
  `### Disposition — #6982 (2026-07-27)` heading.
- 6.2 Add a **disposition row for item 10 marked DONE (this PR)** in the same amendment. Item 8's
  terminal clause makes banner-clearing conditional on every item above it, so adding item 10 without
  a disposition would silently hand #7025 a new blocker it does not know about.

### Phase 7 — Deferred-item trackers

- 7.1 File F1 (`domain/legal`), F3 (`type/security`), F6 (`type/chore` + `domain/engineering`),
  F11 (`domain/engineering`). F7-F10 batch onto F6 per the Deferred Items table.
- 7.2 Link all three in the PR body.

### Phase 8 — Verification, before push

- 8.1 **Re-run `git_data_rung2_user_data_sha256`; confirm `3a2392fb…c1725` unchanged.** If it moved, a
  hash-bound file was edited — revert that edit; never edit the evidence to match.
- 8.2 Confirm the diff∩(13 hash-bound paths) is empty and the evidence file is not in the diff.
- 8.3 Run the suite green at its raised floor.
- 8.4 Run `plugins/soleur/test/c4-count-parity.test.sh` and
  `plugins/soleur/test/terraform-target-parity.test.ts`.
- 8.5 Run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- 8.6 `actionlint` the workflows; `bash -c` the extracted `run:` snippets with
  `GITHUB_STEP_SUMMARY=$(mktemp)`. Never `bash -n` a YAML file.
- 8.7 Full battery if `/var/tmp` is uncontended; if `test-all.sh` returns rc=4, report
  skipped-for-contention and run the affected suites directly. Never force.

## Files to Edit

| File | Change | Hash-bound |
|---|---|---|
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | New gate function + `_git_data_hcl_nocomment`; allowlist comment addition + HOLD-message generalisation | No |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | Five-link fixture, assert-helper pair, ~15 mutation arms, H3/H4, the live-tree arm, header-rule amendment, itemised floor raise | No |
| `.github/workflows/apply-web-platform-infra.yml` | New un-gated disclosure job + `needs:`; third interlock in `git_data_host_create`; interlock in `git_data_host_replace`; stale `apply_target` clause | No |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Extend the job↔gate pairing block with the new gate | No |
| `knowledge-base/engineering/operations/runbooks/git-data-birth.md` | Three statements in `## Before you dispatch`; step-list drift fix | No |
| `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` | Release-checklist item 10 + its disposition row | No |

**Read, never written:** `cloud-init-git-data.yml`, `modules/git-data-userdata/*.tf`,
`git-data-bootstrap.sh`, `git-data.tf`, `rung2-rehearsal/rehearsal.tf`,
`git-data-rung2-boot-evidence.env`.

**No longer edited** (Guard 2 cut, D7): `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

**The binding hash**

- **AC1** — `git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` prints
  `3a2392fb5b0d4fae9d4abeaf5ca10ee682430e473dd9eac1ca3d340ef4ce1725`, unchanged.
- **AC2** — `git diff --name-only origin/main` intersected with the 13 hash-bound paths is empty.
- **AC3** — `git-data-rung2-boot-evidence.env` is not in the diff at all.
- **AC3b** — `modules/git-data-userdata/variables.tf`'s `identity-shaped` line is byte-identical to
  `origin/main`. Stated as its own criterion because D4 instructs correcting the justification, and
  the most explicit copy of it lives in that hash-bound file — an implementer sweeping "every site"
  must be stopped here.

**C1 — the gate**

- **AC4** — A bare call with no argument prints `ABORT` and returns non-zero. The same arm covers the
  missing and unreadable-root cases (dangling symlink, not `chmod 000`).
- **AC5** — A **suite arm** — not an implementation-time check — invokes the gate against the real
  production root and asserts RELEASE at rc=0. It follows A1's shape: a missing or unreadable live
  root is a loud failure, never a skipped arm. The suite header's "synthesized fixtures only" rule is
  amended in the same commit with a stated justification, as A1's was. Its failure text is
  **self-diagnosing** — it distinguishes "the gate could not parse the production root" from "the
  production root violates the property". Since `ci.yml` runs this suite unfiltered on every PR, a
  false-RED here reddens every pull request in the repository until someone deletes the arm.
- **AC6** — The RELEASED message states exactly what it proves, and disclaims what it cannot see:
  rendered key material, the value resident in Doppler `prd` at any moment, the effect of a partial
  `-target`ed apply, and — per the security review — that the three-key split buys separate blast
  radii **on the host**, not in the holder, since the web application reads all three private halves
  from one process environment.
- **AC7** — The HOLD message names the consequence (the transport identity would gain erase
  authority), ends with a remedy and a "nothing has been planned or created" line, and does **not**
  label the gap "Art. 17" — it is Art. 32(1)(d), with Art. 5(1)(f) derivative.
- **AC8a** — Every collapse mutation (M1–M6, M9–M13, M15–M21, M23–M27) drives a non-zero return with
  a **HOLD** carrying that link's own reason token. Verdicts match exact rc **plus a per-reason token
  anchored at line start**, never a bare `HOLD`/`ABORT` prefix — so M3 cannot pass on a HOLD naming a
  different link.
- **AC8b** — Every instrument mutation (M7 zero-extraction, M8 unreadable root, M14 override file,
  M22 partial extraction, an over-budget resolution hop, and an unparseable comment form **outside a
  string**) drives a non-zero return with an **ABORT** carrying that fault's own reason token.
- **AC8c** — M12, M13 and especially **M16–M18** (2-swaps and the 3-cycle): the gate reds on a
  *permutation*, **while links 1–4 are byte-canonical and every cardinality predicate passes**. This
  is the criterion proving predicate 4 is an ordered composition rather than a cardinality check
  wearing the word "bijection".
- **AC8d** — M19 and M20: the gate reds when a slot reads `private_key_openssh` or a secret reads
  `public_key_openssh` — both address-distinct, bijective, and otherwise green.
- **AC8e** — **M26**: the gate reds on a fourth `authorized_keys` line carrying **no** `command=`.
  The block is asserted to hold exactly three non-blank lines, every one a forced command. Without
  this the added key falls through to the raw `git-shell -c "$SSH_ORIGINAL_COMMAND"` path — the
  CWE-22-unfenced path the transport wrapper exists to replace — while the slot count still reads 3
  and the gate releases.
- **AC8f** — **M27**: the gate reds on an unexpected option appended to a `command=` line (e.g.
  `environment="GIT_DATA_REPO_ROOT=/srv"`). The option list is asserted, not just the script name and
  the terminating `${…}`.
- **AC8g** — Each new arm is recorded as having failed **for its own stated reason** during Phase 1
  RED, not merely that the suite went red.
- **AC9** — H3–H8 all PASS, each asserting rc=0 **and** the RELEASED token (a gate that
  early-`return 0`s on an unparsed tree satisfies a bare rc=0). **H5 is load-bearing**: the gate
  releases on a tree carrying a `https://` URL in a local and a `/*` glob inside a `#` comment — the
  row that would have caught the born-red blanket comment ABORT. **H7** proves root-scoping removed
  the sibling-file false-RED rather than merely claiming it; **H8** proves the gate tolerates the
  unrelated `tls_private_key` siblings the live root already carries.
- **AC10** — The suite exits 0 and its anti-vacuity floor line reports the raised floor. The itemised
  rows **sum to the floor delta**, and the delta equals the number of new **verdicts** (not arms — an
  arm may record more than one). The floor is kept as **two ledgers**, RED-expecting and
  PASS-expecting, so an arm flipped from one expectation to the other moves a count.

**C1 — the allowlist**

- **AC11** — The allowlist constant's token list and all **six** consumer sites are byte-identical to
  `origin/main`, and the comment block gains the capability sentence. (Collapses the former
  AC11/AC12/AC13. No `grep -c == 0` assertion: the phrase is accurate for five of the eight tokens and
  must not be deleted, and an unscoped grep would false-fail on this plan file — the self-reference
  trap.)

**C2 — disclosure**

- **AC16** — `## Before you dispatch` carries all three statements in plain language.
- **AC17** — Statement (a) **quotes** the AC30 wording, cited by the `WORDING PINNED (AC30)` anchor,
  and says the **repositories** are not encrypted at rest. It must not compress to "LUKS is not in
  place" — the device exists, is mounted, and `luks_mounted=yes` is true *of the device*; that
  compression would contradict the ledger's `mechanism: "luks"` row.
- **AC18** — Statement (b) records field, scope and date as re-measured during implementation, and
  reports **two** facts, not one: `prevent_self_review: false` **and** `can_admins_bypass: true`. The
  second is the stronger half and was missing from the first draft — it means the control is not
  merely self-approvable; the same account can bypass the reviewer *and* the main-branch pin entirely,
  with no approval event at all. Saying only "not two-party" understates what the operator is being
  told. The earlier instruction not to generalise beyond one environment is **relaxed on
  measurement**: one unauthenticated API call shows **all five** gated environments
  (`inngest-config-signing`, `inngest-cutover`, `sentry-infra-apply`, `web-platform-infra-apply`,
  `workspaces-luks-cutover`) carry the same setting. That is a measurement, not an extrapolation, and
  it materially strengthens deferred item F3.
- **AC18b** — Statement (b) also states that the approval it describes governs the **birth** path
  only. Per D9, the post-birth `git-data-host-replace` path carries no approver at all, and a reader
  would otherwise conclude the host is permanently protected by a reviewer click.
- **AC19** — Statement (c) says the boot reached its final stage without tripping the named `FATAL`
  gates guarding LUKS mount, repo root, hooks path and provisioning; that reaching the emit is the
  evidence and the four literals are the channel the consumer asserts on, not four measurements. It
  must neither overclaim ("measured four invariants") nor underclaim ("attests nothing") — the
  underclaim would contradict the ledger's **rehearsal-volume** row recording that the capture script
  requires `stage:boot_complete` with `luks_mounted=yes` before writing evidence at all.
- **AC20** — Statement (c) states that exactly one boolean is measured — `nft_metadata_drop`, read
  from the live `inet soleur_git_data output` chain — that it read `yes`, and that it is in neither
  committed artifact. (Precisely: of the five emitted booleans, the evidence file's host-rows query
  selects only the four literals; it also selects non-boolean columns, so the claim is about the
  boolean set.)
- **AC21** — The `git_data_birth_disclosure` job carries **no `environment:`**, `git_data_host_create`
  carries `needs: [git_data_birth_disclosure]`, and the three statements render to
  `$GITHUB_STEP_SUMMARY` from that un-gated job — so they are on the run page while the gated job sits
  in `Waiting`. Verified by extracting the step's `run:` and executing it with
  `GITHUB_STEP_SUMMARY=$(mktemp)`.
- **AC22** — The disclosure step contains **no command substitution**. (The step is pure `echo` of
  strings fixed at implementation time; the former `bash -e` grep-guard was guarding a construct the
  step has no reason to contain.)
- **AC23** — `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes — the
  gate's own invocation over the changed set, never a hand-enumerated path list.
- **AC24** — The DO-NOT-DISPATCH banner is byte-identical to `origin/main`.
- **AC24b** — The `apply_target` description's `git-data-host-create` clause no longer claims the
  route is held and that a dispatch exits 1 before planning.

**Wiring and non-regression**

- **AC25** — The gate runs as a third interlock step in `git_data_host_create`, after the rung-2 step
  and before `Terraform init`.
- **AC25b** — The gate runs in `git_data_host_replace` (D9).
- **AC25c** — `plugins/soleur/test/terraform-target-parity.test.ts` asserts the job↔gate pairing for
  both jobs, so AC25/AC25b cannot be silently skipped by a human-read criterion alone.
- **AC26** — `## What the job does, in order` enumerates every step including the rung-2 and the new
  interlock.
- **AC27a** — All four birth-target registration sites are byte-identical to `origin/main`, asserted
  on their content, and the 20-address list is unchanged.
- **AC27b** — No `-target=` **flag** is added or removed. Asserted as
  `git diff -U0 -- <the workflow and the gate libs> | grep -E '^[+-][^+-].*-target='` returning empty
  — `-U0` and a path scope, because AC26's runbook renumbering necessarily rewrites a step-list item
  that quotes `-target=`, and a default-context whole-diff grep would red on a correct
  implementation. (An earlier draft's unscoped form contradicted AC26.)
- **AC28** — `plugins/soleur/test/c4-count-parity.test.sh` passes. (Path corrected — an earlier draft
  cited `apps/web-platform/test/`, which does not exist.)
- **AC29** — ADR-149 carries release-checklist item 10 **and its disposition row marked DONE**, so
  #7025's banner-clearing precondition is not silently extended.
- **AC30** — `actionlint` passes on the workflows. `bash -n` is not used on a YAML file.
- **AC33** — Issues for F1, F3, F6, F7, F8, F9 and F10 exist and are linked in the PR body, with
  labels verified via `gh label list` before use. F7–F10 come from the security review and are all
  **hash-bound**, so they batch with F6 into the next change that legitimately moves the hash.
- **AC34** — The corrected comment in the gate library names the surviving hash-bound divergence and
  cites its tracking issue.
- **AC35** — The PR body uses `Closes #8009` and references the C2 issue.

### Post-merge (operator)

None. Every step above is automatable and runs in-session or in CI.

The birth dispatch itself is **not** part of this PR — it is a separate, environment-gated step that
follows the merge, and this plan neither performs nor schedules it.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Sized MEDIUM (days); no blocking prerequisites — the evidence file is PASS and the
hash is current, so the work is additive to a released route. The advisory resolved all five forks
and its conclusions are carried into decisions D1–D3 and the Guard Contract. Three findings changed
the plan's shape materially:

- The fold-into-rung-2 option is **fail-open**, via a second call site in `infra-validation.yml` that
  exits 0 when evidence is absent. Verified independently at that file's `if [[ ! -f "$EV" ]]` block.
  This disqualified an option the brief left open.
- A template-only arm is **actively harmful**, not merely weak, because a collapse never changes the
  left-hand side. This is now the plan's headline sharp edge.
- The two suites use **different** anti-vacuity conventions (`_ran=$((passes+fails))` vs. the
  ADR-193 #2 `cases` counter at floor 83). Verified independently. **This finding is now moot** — it
  only mattered while the plan touched both suites, and Guard 2 was subsequently cut (D7), which is
  itself part of the argument for cutting it: the hazard was self-inflicted.

Additional risks R1–R7 were folded into the mutation matrix (M9, M10, M11), the Risks table, and the
ADR decision (amend ADR-149 rather than create a sibling).

### Plan Review Panel

**Status:** reviewed — four reviewers (correctness, simplicity, flow, architecture), escalated per the
`single-user incident` threshold.

The panel changed this plan materially rather than polishing it. The four findings that reshaped it:

- **Architecture found a fifth link.** The private-half `doppler_secret` distribution was absent from
  the assembly, and a one-line edit there inverts the authorization map while every enumerated link
  stays green. Independently verified before adoption. Without it the plan would have shipped a guard
  certifying something other than what its own HOLD message claims — the defect class #8009 is about,
  reproduced inside the fix for #8009.
- **Correctness found the assembly unit was wrong**: Terraform merges `locals` across every `.tf` in a
  root (~35 files here, `locals {` in at least ten), so a single-file gate is defeated by a new
  sibling file. It also found the matrix had no *deletion* rows, making a two-slot host pass.
- **Flow found the disclosure could not reach its reader.** An environment-gated job is held before
  its first step runs, so the in-job step executed after the approval click. D6 now uses a preceding
  un-gated job — with an in-file precedent — and flow also found the post-birth `git-data-host-replace`
  bypass that D9 now closes.
- **Simplicity found ~40% of the assembly was ceremony**: five independent per-link assertions
  collapsed to one resolution walk, and Guard 2 was cut entirely along with a second suite, a second
  floor convention, two ACs and a sharp edge.

Three plan claims the panel falsified are corrected in place and flagged as corrections rather than
silently rewritten: the "phrase appears in two places" premise (it appears in one), the
`_a_tree`/`_a_abort` fixture claim (that fixture has none of links 3–5), and the c4-count-parity path.

### Legal (CLO)

**Status:** reviewed

**Assessment:** **Gate disposition PASS.** Both C1 and C2 reduce compliance risk relative to the
status quo. No Art. 9 special-category processing, no missing lawful basis, and **no Art. 30 register
trigger** — this PR need not amend the register or the encryption-posture ledger.

Key calibrations, all folded into ACs:

- **Article precision.** The gap C1 closes is **Art. 32(1)(d)** — testing the effectiveness of a
  technical measure — not Art. 17. `git-data-remove.sh` is the Art. 17 erasure *path*, but the risk
  is *unauthorized* erasure, which is Art. 32 with Art. 5(1)(f) derivative. Folded into AC7.
- **C2(a) must not underclaim.** The LUKS device genuinely exists and is mounted; only the
  repositories are plaintext. Folded into AC17.
- **C2(b) must not over-generalise** beyond the one environment measured. Folded into AC18.
- **C2(c)'s calibration** was supplied verbatim and is folded into AC19.
- The plaintext-at-rest fact is **already fully recorded** — ledgered as `plaintext-exception` on
  `hcloud_volume.git_data` (tracking #6897, expiring 2026-10-22) and prior-disclosed in the Art. 30
  register at PA-2 §(g)(13). C2(a) propagates an existing record to the point of decision, which is
  the correct direction of travel. Creating a second record would invite drift.
- **CORRECTION — the CLO's stated reason was false, and the security review measured it.** The
  advisory kept `disclosed_as: "not-publicly-claimed"` on the grounds that "a job log and an internal
  runbook are not public surfaces." Measured: `gh repo view --json visibility` returns **PUBLIC** for
  `jikig-ai/soleur`. The runbook is committed to that public repo, and a public repo's Actions run
  summaries — where D6 places the disclosure — are world-readable. **Both C2 surfaces are public.**

  The *conclusion* survives, but on measured grounds rather than the stated ones: none of the three
  statements transfers any capability, because each is already public. (a) is already committed in
  `scripts/encryption-posture-ledger.json` and the Art. 30 register, and reaching the disk requires
  host compromise. (c) is already spelled out in the public `git-data-bootstrap.sh` under
  `WORDING PINNED (AC30)`. And (b) is returned by an **unauthenticated** call to
  `api.github.com/repos/jikig-ai/soleur/environments`, reviewer login included. So publishing all
  three is correct — and withholding them would only blind the operator.

  `disclosed_as` must nevertheless be **re-derived rather than assumed** on the next touch, since the
  premise that produced its current value is now known to be wrong. Folded into F1's tracking issue.

Two findings are **out of scope and filed rather than folded** (see Deferred Items):

- **F1 (Medium)** — the three-key separation is asserted by ADR-068 §6 and by `git-data-remove.sh`'s
  header but appears in no PA-2 §(g) measure. Recommended, not required: Art. 30(1)(g)'s standard is
  "a general description where possible," and this PR adds a *test* rather than changing a TOM, so no
  register touch is owed by this change.
- **F3 (Critical — record accuracy, UNVERIFIED)** — PA-10 §(g)(6) records "GitHub Environments +
  required reviewers" as a load-bearing organisational TOM. If tenant-repo environments also carry
  `prevent_self_review: false`, that recorded control is one person clicking twice. Not measured by
  this session, so it is stated as an open question rather than a finding of fact. One `gh api` call
  closes it, and the register has precedent for withdrawing this class of overclaim.

### Product/UX Gate

**Tier:** none

**Decision:** not applicable — no UI surface. The mechanical UI-surface override was evaluated against
`## Files to Edit` and `## Files to Create`: the edit set is two shell libraries, two test suites, a
workflow YAML, a runbook and an ADR. No path matches any UI-surface term or glob, so the override does
not fire and the tier is genuinely NONE rather than a subjective judgement.

**CPO carry-forward:** this work *is* CPO condition C. C1 is #8009 and C2 is the unfiled second half
of the same sign-off ("C — before any birth dispatch, not before ready"). The product decision has
already been made and recorded; re-asking would be ceremony. `requires_cpo_signoff: true` is satisfied
by that standing sign-off, and `user-impact-reviewer` runs at review time per the
`single-user incident` threshold.

## Deferred Items

Each has a tracking issue as an in-scope task of this PR — a deferral without a tracker is invisible.

| Item | Why deferred | Tracking |
|---|---|---|
| **F1** — record the three-key separation as a PA-2 §(g) measure in the Art. 30 register | This PR adds a test, not a TOM; no register touch is owed. Recommended tidy-up under the register's own house style | File issue, `domain/legal` |
| **F3** — verify whether tenant-repo environments carry `prevent_self_review: false`, and narrow PA-10 §(g)(6) if they do | Unverified; needs one `gh api` call against surfaces this work did not measure. Critical for record accuracy | File issue, `type/security` |
| **F4/F5** — the ledgered plaintext exception expiring 2026-10-22, and the register's "NOT YET PROVISIONED" statements going stale at birth | Both attach to the birth event or to #6897, not to this change | #6897 covers F4; F5 is a pre-birth follow-through |
| **F6** — the hash-bound copy of the wrong justification in `modules/git-data-userdata/variables.tf` (`MAY DIVERGE (identity-shaped …)` listing all eight tokens) | Correcting a **comment** there would move `3a2392fb…c1725`, void the rung-2 evidence and buy a fresh **paid** Hetzner rehearsal. Not a defensible trade for prose | File issue, `type/chore` + `domain/engineering`; fold into the next change that legitimately moves the hash |

| **F7** — `/home/git/.ssh/authorized_keys` is `git:git 0600` inside a git-owned `.ssh`, and `01-hardening.conf` pins no `AuthorizedKeysFile`, so sshd also honours `authorized_keys2` | The authorization map is rewritable at runtime by the very principal it constrains — post-exploitation persistence, but a real route the five-link **static** chain cannot see. Fix is `root:root` ownership plus an `AuthorizedKeysFile` pin, both in **hash-bound** files | File issue, `type/security`; batch with F6 |
| **F8** — `git-data-remove.sh` can report erasure success having erased nothing, when `/mnt/git-data` is not mounted | `readlink -f` succeeds on a non-existent path, so the guards pass and the `not present (no-op)` branch exits 0. Today it fails closed by directory ownership, not by assertion. Art. 17 correctness depends on distinguishing "not present" from "not visible". Fix is a `mountpoint -q` check — **hash-bound** | File issue, `type/security` + `domain/legal` |
| **F9** — `core.hooksPath` points at a directory owned and writable by the `git` account whose pushes the hook fences | No integrity boundary on the control. `$REPO_ROOT` must be git-writable; `$HOOKS_DIR` need not be — **hash-bound** | File issue, `type/security` |
| **F10** — the wrappers' "sshd passes NO client env (`AcceptEnv` empty)" claim is unasserted | Ubuntu ships `AcceptEnv LANG LC_*`; `01-hardening.conf` pins neither `AcceptEnv` nor `PermitUserEnvironment`. Holds today by default rather than by assertion, while protecting the `REPO_ROOT` of an `rm -rf`. Composes with M27 — **hash-bound** | File issue, `type/security`; batch with F7 |

| **F11** — give the five replace-class dispatch targets (`git-data-host-replace`, `registry-host-replace`, `registry-luks-recut`, `registry-region-migrate`, `inngest-host-replace`) an `environment:` with a main-only branch policy | Split out of Phase 4.2 during one-shot adjudication. The workflow's `confirm` description records the no-`environment:` posture for all five as deliberate, so this is a fleet-wide policy call, not a local fix — and it adds a required approval to destructive emergency paths. Without it, D9's replace interlock is supplied by the branch it polices; that limitation ships stated rather than hidden | File issue, `domain/engineering` |

All of these are covered by AC33 in the Acceptance Criteria above; the labels `domain/legal`,
`type/security`, `type/chore` and `domain/engineering` were each confirmed to exist at plan time via
`gh label list`.

**F7–F10 came from the security review and share one shape:** each is a real route to the erase
capability that the five-link chain cannot see, because the chain is **static** and these are
properties of a **live host** or of a file the host owns. That is not a defect in the gate's design —
it is the honest boundary of what a static assertion buys.

**Corrected during one-shot adjudication (2026-09-10).** An earlier revision of this paragraph said
that boundary was closed by "Phase 5.6's three-probe runtime verification". There is no Phase 5.6 —
Phase 5 runs 5.1-5.5 — and no such verification can exist in this PR, because **there is no git-data
host to probe**: birthing it is the very thing this PR unblocks, and the rung-2 rehearsal host was
destroyed. A runtime probe is only available *after* the dispatch. The boundary therefore stands
open and is carried by F7-F10, which is why all four are filed rather than closed here. Stating it
this way is the same discipline the plan applies everywhere else: name what the guard does not
prove instead of implying a check that cannot run.

## Test Scenarios

Beyond the mutation matrix, the end-to-end scenarios worth naming:

1. **The headline** — a tree with all three `command=` lines on one variable reaches the dispatch job;
   the interlock refuses, nothing is planned, nothing is created.
2. **The quiet one** — template and module canonical, one root local re-pointed at
   `tls_private_key.git_transport`. Every other gate in the repository stays green; this one refuses.
3. **The invisible one** — every public-half link byte-canonical, and
   `doppler_secret.git_transport_ssh_private_key` publishing the erase key. The app would push with a
   key sshd matches to `git-data-remove.sh`. Only the link-5 predicate catches it.
4. **The sibling-file one** — `git-data.tf` byte-canonical, one pubkey local moved into a new
   `git-data-keys.tf` in the same root and re-pointed. Only a root-directory-scoped gate catches it.
5. **The benign rename** — all three variables renamed consistently across all five links, still three
   distinct resources and three correctly-named secrets. The gate releases. This is what separates a
   property assertion from a string match.
6. **The instrument refusing** — a bare call with no argument; an unreadable root via dangling
   symlink; an `*override.tf` present; a `//` comment in the HCL. All ABORT, all distinguishable from
   a HOLD.
7. **The disclosure** — while `git_data_host_create` sits in `Waiting`, the run summary page already
   renders the three statements from the un-gated disclosure job.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| The guard is written LHS-first and is vacuous | **High** | Every arm requires a measured collapse fixture; the RHS discipline is in the Guard Contract and AC8a |
| Link 5 is omitted and the guard certifies a claim it never checked | **High** | M12/M13 + AC8c, which require links 1–4 byte-canonical while the arm reds |
| A sibling `.tf` in the same root defeats a single-file gate | **High** | D2: the unit is the root directory (`*.tf` + `*.tf.json`), not one file |
| Distinctness-only passes a *deletion* | **High** | Exact cardinality (`== 3`) and set equality on the script names, not membership |
| An `*override.tf` re-points a local at apply time | Medium | M14 ABORT |
| A second module instantiation is consumed instead | Medium | M15 + the `user_data` label assertion |
| Alias/whitespace or a partial extraction defeats raw-string de-dup | Medium | De-duplicate on the extracted address; ABORT when extracted count < slot count |
| Phase 1 RED is theatre because arms rc-127 on an undefined function | **High** | The assert helper pins an exact rc (Phase 1.2) |
| A fixture writes into the real tree and moves the hash | Medium | Every fixture copies; AC1 + AC2 catch it before push |
| An implementer sweeps the justification phrase into the hash-bound file | **High** | AC3b pins that line byte-identical; D4 names it explicitly |
| The disclosure lands where the approver never sees it | **High** | D6: an un-gated preceding job; AC21 asserts the absence of `environment:` |
| C2 evaporates when #7025 clears the banner | Medium | D5; AC24 pins the banner byte-identical |
| Adding checklist item 10 silently blocks #7025 | Medium | Its disposition row lands in the same amendment (AC29) |
| AC26 and AC27 contradict each other on `-target=` | Medium | AC27b uses `-U0` and a path scope |
| Sibling worktrees contend on `/var/tmp`; `test-all.sh` rc=4 | Low | Report skipped-for-contention; never force |

### Precedent Diff (deepen-plan Phase 4.4)

Every pattern-bound shape this plan prescribes has a sibling precedent in the repo. None is novel, and
each is adopted rather than reinvented:

| Shape prescribed | Precedent adopted | Divergence, and why |
|---|---|---|
| A fail-closed gate function sourced by a dispatch job | `git_data_birth_readiness_gate` and `git_data_rung2_rehearsal_gate` in the same library | None. Same ABORT-on-missing-arg contract, same `dirname`-derived sibling paths, same one-interlock-one-function shape the dispatch job's own comment argues for |
| Predicate assertions over `git-data.tf` | `git-data-luks.test.sh`'s `assert_holds` / `assert_mutation` | **Diverges:** those take one file and one sed; this gate reads a root directory plus a template and a module, so the helper needs a copy-then-sed tree wrapper. Recorded because the divergence is real work, not a detail |
| A live-tree arm in a fixtures-only suite | Arm A1, which calls `git_data_birth_readiness_gate` on the real template and makes a missing live file a loud failure | None. The suite header rule is amended with a stated justification exactly as A1's was |
| An itemised anti-vacuity floor raise | The `69 -> 77` and `77 -> 80` blocks in the same suite | None. Same itemised form; rows sum to the delta, counted in verdicts |
| A third interlock step in the dispatch job | The rung-2 interlock step, whose comment states the separate-step-separate-function principle verbatim | None |
| An un-gated job preceding an environment-gated one | The `apply` job's `needs: preflight`, where `preflight` declares no `environment:` | None. Same mechanism, same file |
| ADR checklist amendment by append | ADR-149 item 9, annotated "added by #6982" | None, plus a disposition row so #7025 is not silently blocked |

**No scheduled work is introduced**, so the Inngest-vs-GitHub-Actions cron precedent (ADR-033) does not
apply. **No new Terraform resource is introduced**, so the `-target=` allow-list precedent does not
apply — and the plan asserts that positively (AC27a).

## Sharp Edges

- **A collapse never changes the left-hand side.** `grep -c '_pubkey' git-data.tf` returns 3 on a
  fully collapsed tree, and the template's three `${…}` names stay distinct under every collapse at
  links 2–5. Any arm that greps the LHS is decorative. *(Stated once here; every other section
  cross-references this rather than restating it.)*
- **Distinctness is not the property; the MAP is.** Three distinct public keys are fully compatible
  with an inverted authorization map, because the app holds the *private* halves and those are bound
  in three separate `doppler_secret` blocks. An earlier draft of this plan enumerated four links and
  would have shipped exactly the defect #8009 exists to fix.
- **The Terraform unit is the ROOT DIRECTORY, not the file.** `locals`, `resource` and `module`
  blocks merge across every `.tf` in a root. A gate handed one file is defeated by a new sibling file.
- **`*override.tf` merges over the primary configuration** and is invisible to a gate that reads only
  the files it was handed.
- **The suite's existing fixture does not fit.** The R2 tree has no `git-data.tf`, no `locals`, no
  `tls_private_key`, no `doppler_secret`; `_a_abort` is hardwired to a different gate function. A new
  five-link fixture and a new assert-helper pair are required, and that is the real cost of Phase 1.
- **An assert helper that accepts any non-zero makes the RED phase theatre** — an undefined bash
  function returns 127, which is non-zero. Pin an exact rc.
- **Floors count verdicts, not arms.** The existing `69 -> 77` block has 7 rows summing to 8.
- **H2 cannot fire alone.** Neutering `fail()` on an all-green suite leaves `FAILURES` and `fails`
  both 0 and the ledger identity holds. The harness row must pair the neutering with an injected
  failure.
- **The cloud-init prose names all three wrappers immediately above the block it describes**, and HCL
  permits `//` and `/* */` comment forms neither existing stripper handles. Strip comments, and ABORT
  on a form you cannot parse.
- **A gate suite under `tests/scripts/` is registered manually.** If a future PR splits this gate into
  its own file there, it ships silent and green unless a `run_suite` line lands in `scripts/test-all.sh`
  in the same commit — `tests/scripts/` is structurally invisible to both orphan-suite detectors.
- **`bash -n` does not validate workflow YAML**, and `actionlint` does not validate a composite
  action. Extracted `run:` snippets need `GITHUB_STEP_SUMMARY` set or they fail on an ambiguous
  redirect.
- **Never edit the evidence file to match a moved hash.** If the hash moves, a hash-bound file was
  edited; revert the edit.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Assert on the rendered `authorized_keys` values | Requires terraform init/plan against real resources — not static, which the brief requires |
| Template-side arm only | Actively harmful — true today, and stays true through the defect it names (D2) |
| Four links (public halves only) | Misses the private-half distribution, which is what the app actually holds (D2, M12/M13) |
| Five independent per-link assertions | Five extractors and five messages over three files, and still blind to an unanticipated hop. One resolution walk composes and diagnoses better |
| Single-file scoping on `git-data.tf` | Narrower than the Terraform root; defeated by a new sibling `.tf` |
| Fix `rung2-rehearsal/rehearsal.tf` to use three distinct keys | Only meaningful with a fresh **paid** Hetzner rehearsal. The static gate covers what the rehearsal structurally cannot; a sentence in the corrected comment records the collapse |
| Guard 2 — a rehearsal counter-assertion | Cut (D7): zero coverage of the real failure mode, blocks the improvement it should welcome, and was the sole source of a second suite and a second floor convention |
| Fold into `git_data_birth_readiness_gate` | Wrong argument contract for links 3–5; falsifies its RELEASED message |
| Fold into `git_data_rung2_rehearsal_gate` | Its `infra-validation.yml` call site is dormant when evidence is absent |
| A new step in `infra-validation.yml` | Strictly narrower than `ci.yml`, which already runs the suite on every PR unfiltered (D8) |
| Deleting the `identity-shaped` phrase | It is accurate for five of the eight allowlist tokens (D4) |
| A new ADR | Would split ADR-149's single enumeration of what holds the button |

## Non-Goals / Out of Scope

Explicitly **not** done by this PR:

- **Dispatching the birth workflow.** This PR unblocks the dispatch; the dispatch is a separate
  environment-gated step that follows the merge.
- **Clearing the DO-NOT-DISPATCH banner.** ADR-149 checklist item 8, owned by #7025.
- **Editing `git-data-rung2-boot-evidence.env`** for any reason.
- **Editing any of the 13 hash-bound files**, including the copy of the wrong justification in
  `modules/git-data-userdata/variables.tf` (tracked as F6).
- **Touching the 20-address birth target list**, whose four registration sites stay in lockstep: the
  `-target=` list in the workflow, `def allow:` in `tests/scripts/lib/git-data-host-birth-gate.sh`
  (unparameterized — a singleton), that gate's separate presence loop, and
  `GIT_DATA_BIRTH_TARGET_BASES` in `plugins/soleur/test/terraform-target-parity.test.ts`. The pairing
  block in that same test file *is* extended (Phase 4.3) — that is a different assertion from the
  address list, which is why AC27 is split.
- **Guarding against a plain `ssh_authorized_keys:` entry.** The property is about the three
  forced-command slots. An added unrestricted key for the `git` user would be strictly *worse* than a
  collapse, and this gate does not cover it — cloud-init's own directive cannot carry `command=`,
  which is why the block is hand-written in `write_files:`. Named here so the next reader does not
  assume coverage that does not exist.
- **#8010** — the rung-2 gate checking assertion shape rather than that a rehearsal passed. **C1
  landing does not close it.**
- **#6286** — unrelated inngest cloud-init pin drift. **C1 landing does not close it.**
- **The DC-2 replacement** of the sentinel gate's mechanism. ADR-149's #6982 disposition records item
  7 as "NOT SATISFIABLE AS WRITTEN", so it is blocked rather than pending; the
  `_git_data_hcl_nocomment` helper is justified by de-duplicating an existing divergence, not by that
  landing.
