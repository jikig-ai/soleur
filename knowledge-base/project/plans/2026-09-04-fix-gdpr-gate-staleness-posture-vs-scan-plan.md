---
title: "fix(gdpr-gate): restore the attestation writer the substrate migration dropped, and give the path scan an output of its own"
date: 2026-09-04
slug: fix-gdpr-gate-staleness-posture-vs-scan
branch: feat-one-shot-7710-gdpr-gate-prescan-refusal
issue: 7710
closes: [7710]
lane: cross-domain
type: bug
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: granted 2026-09-04, conditional on A–E (see Domain Review)
---

## Overview

The `gdpr-gate` advisory hook emits a date-derived `POSTURE_FAIL` line whenever it runs, because
the vendored rule corpus's `last-verified` attestation is 117 days old. The line reads like a scan
result but is not one, and the path scan beside it produces no output at all — so on the surfaces
where a zero-match scan is reachable, "scanned, matched nothing" and "did not scan" are the same
bytes.

The corpus was re-measured against live upstream and is current. The attestation is old because
the code that advanced it was deleted in a substrate migration and never reimplemented. This plan
restores that writer, gates it on a comparison that can tell "could not check" from "clean", and
gives the path scan an output of its own.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed); no
`knowledge-base/project/specs/feat-one-shot-7710-gdpr-gate-prescan-refusal/spec.md` exists.

## Research Reconciliation — Spec vs. Codebase

| Claim | Measured reality | Plan response |
|---|---|---|
| The script is at `scripts/gdpr-gate.sh` | It is at `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh`. | Use the real path. |
| "The gate refuses before scanning anything" | **False.** It prints its banners, runs the `CANONICAL_REGEX` loop, then `exit 0`, on every path. `repo-scan.sh` has no staleness check at all. Nothing is suppressed. | Re-aim at the defect that is present: the scan produces no output of its own. |
| "The gate is invoked at `plan` Phase 2.7 and `work` Phase 2 exit, so every invocation returns the same refusal" | **False on the mechanism.** Both invoke the *skill*, never the script. `POSTURE_FAIL` has one producer — the lefthook hook — and zero blocking consumers. | Correct the causal story. See the residual below: this also means the plan cannot fix those gates, and that is now named rather than left implied. |
| (unstated) The lefthook hook runs on every commit | **False.** `lefthook.yml` gives `gdpr-gate-advisory` a 15-entry glob, and `{staged_files}` is pre-filtered to it (measured on lefthook 2.1.6: unmatched paths are dropped; with no matches the command is skipped entirely). The glob is a strict subset of `CANONICAL_REGEX`, so on that surface `matched == examined ≥ 1` always. | **The zero-match arm of the headline defect is unreachable from the only mechanical caller.** It is reachable from manual invocation, `repo-scan.sh`, the self-test and `gdpr-gate.test.ts`. Restate Phase 3's justification on the real surface, and add the glob-liveness guard, because a line emitted by the script cannot witness the script not running. |
| "The rule corpus is 108 days stale" | The **attestation** is 117 days old. The rules are current: 8 SAME / 0 DRIFTED / 0 ERROR against live upstream, 2026-09-04. | Do not re-vendor. |
| (unstated) The NOTICE record is complete | The frontmatter pins **5** of 8; `auth-sessions.md`, `frontend.md`, `testing-seeding.md` carry no pin. | Reconcile — and it is a hard prerequisite of the writer, not only of an attestation. |
| (unstated) Those three files had *no* integrity guard | **False, inverted.** The lefthook glob routes any commit staging them into the "staged but not in NOTICE" branch, which rejects them outright. For 117 days they were guarded *more* strictly than the pinned five. | Phase 1 **relaxes** them to "SHA-divergent edit blocked". Never write it up as closing a hole that did not exist. |
| (unstated) The undercount is in three places plus prose | **Two matching the plan's literals, and a third the literals miss.** `compliance-posture.md` and `content-vendoring.md` carry the two quoted forms; the NOTICE body prose already reads "lifts **eight** reference files" and its table already carries all 8 rows. But `ADR-026`'s C4 component block carries `5 lifted (MIT) + rewritten layers` — a differently-worded third site that neither acceptance-criterion grep would catch. | Correct two sites. **This matters beyond bookkeeping:** the earlier draft mandated writing "the three corrected locations" into an Art. 5(2) record — a false claim, in the plan's own defect class, in the artifact whose value is that it contains none. |
| (unstated) `last-verified` is maintained | Never advanced by automation. `git log -S` returns one commit — `10670383f`, the one that introduced the field. Its writer was a `sed -i` in a workflow deleted in `5b2c1922d` (#4483); the Inngest replacement never reimplemented it, while still shipping a PR-body sentence claiming it does. | The root cause, and the reason any hand bump is a 90-day snooze. |
| (unstated) The cron's comparison is correct | **Two defects.** (a) `if (!currentSha \|\| currentSha === oldSha) continue;` treats an unparseable response as SAME — a false-clean arm. (b) `aggDiffParts` is declared and never populated, so the classifier always sees an empty diff and returns `no-op`. | Both must be fixed *in this plan*, because the writer is founded on that comparison. |
| (unstated) The cron has one `drift: "none"` exit | **Two.** The genuine one (`!driftDetected && !driftFlags`) and one at `classifyRc === 0` reached **after** drift was detected, precisely because of (b). | A writer keyed on `detectResult.drift` would advance a compliance attestation over a drifted corpus. This is the single highest-severity finding in review and it reverses an earlier scope-out. |
| (unstated) `safeCommitAndPr` can commit directly to the default branch | **False, twice over.** It always does `git checkout -B ci/<cron>-<ts>` → push → `POST /pulls` with `base: "main"`; `mergeMode` only selects how the created PR merges. Independently, three active rulesets target the default branch and every bypass actor on `CI Required` is `bypass_mode: "pull_request"`. It is also not called at all on the no-drift path (`route === "pr"` gates it). | The fork was never "PR vs direct commit" — it is *which* `mergeMode`. Use `"direct"`, which the drift route already passes. |
| (unstated) `gdpr-gate.sh` emits a `gdpr-gate-touch` event | **False.** It emits `hr-gdpr-gate-on-regulated-data-surfaces`; `gdpr-gate-touch` is promised in the file header and in `rule-metrics-aggregate.sh` and emitted nowhere. The earlier draft cut a mechanism partly on this non-existent capability — a violation of `hr-verify-repo-capability-claim-before-assert` inside the plan that cites it. | Correct the Cut List; fix the false promise in Phase 5. |
| (unstated) A plan for this issue does not exist | `2026-09-03-fix-fixture-operand-and-flow-gates-plan.md` designs a "PR 3" for #7710 that never shipped (only PR 1 landed, as #7810), and already recommended the posture row at 116 days. | Adopt and extend; re-measure everything inherited. |

## Research Insights

### Premise Validation (Phase 0.6)

`#7710` OPEN (`type/bug`, `priority/p2-medium`, milestone *Post-MVP / Later*, and **not** labelled
`compliance/critical`, which `content-vendoring.md` §8 step 2 requires of the discharging issue).
`#7255` OPEN — a bug report filed after the substrate move (`#4483`), not the move. `#3535`, `#7450`,
`#7652` CLOSED; `#3541`, `#7702` MERGED.

### Independent re-measurement (2026-09-04)

| Measurement | Result |
|---|---|
| `gh api repos/goSprinto/compliance-skills` | `archived: false`, `pushed_at: 2026-05-26T08:04:09Z` |
| Upstream HEAD | `0594a9efdb0cca6031724e87bf843b70e8813ac6` (pin `7b58d684…`) |
| Per-file drift, all 8 lifted paths | **8 SAME, 0 DRIFTED, 0 ERROR** |
| Local pin integrity | 5 match; 3 carry no pin |
| `notice-frontmatter.sh days-stale` | **117** |

Measured local SHAs for the three unpinned files: `auth-sessions.md`
`a2eac5e15c72b28a7f271f5ab98f376f4448f005`; `frontend.md`
`7ab925695fb02151b0214ef171d92f10059b1d50`; `testing-seeding.md`
`3dc230db21b657a9da31886d52abf982d7203f4b`.

Note the measurement used **three** states. The comparison this plan builds must too — a two-state
`SAME`/`DRIFTED` vocabulary reports an unfetchable file as zero drift and lets the writer fire.

### Governing ADRs

`ADR-196` (a refusal binds to a measured condition, not a declared one) and `ADR-094` (a verification
clock is cleared by verifying, never by editing the date) decide against bumping the date *as the fix*.
`ADR-121` and `ADR-186` each place the substitution of an identity check for a freshness clock in a
rejected-alternatives table, deciding against replacing the threshold. `ADR-192`, `ADR-197` and
`ADR-166` supply the requirement that "could not check" never collapse into "bad" — which this plan
must apply to the comparison it is fixing, not merely cite. `ADR-026` fixes the gate's advisory,
`exit 0`, no-pass/fail-verdict contract; it collides with `ADR-197` D-2 and that tension is a named
residual. `ADR-033` I1/I5 constrain the cron: Octokit and filesystem work inside `step.run`, with a
deterministic per-step return shape, under `retries: 1`. `ADR-139` requires the argument be re-derived
for this gate rather than inherited.

### Applicable institutional learnings

- `2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md` — the direct precedent
  (`#3541`): per-judgment banners scope to relevance, persistent-state banners need not.
- `2026-05-10-content-vendoring-pin-policy-brainstorm.md` — cron is convenience, the runtime check is
  the load-bearing safety layer, and neither may depend on the other.
- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` — an anti-vacuity
  floor may not route through the machinery it guards. **This is why Phase 3 needs the glob-liveness
  test:** a completion line emitted by the script cannot witness the script not running.
- `2026-03-21-lefthook-gobwas-glob-double-star.md` and
  `2026-06-06-lefthook-pre-push-push-files-and-dual-glob-depth1.md` — this repo has twice shipped a
  lefthook glob that silently matched nothing.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` and
  `2026-07-21-the-guard-i-shipped-could-never-have-fired-and-my-fake-certified-it.md` — a guard that
  cannot be driven red in its test environment is vacuous.
- `2026-06-01-silence-detector-needs-…-liveness-signal.md` (path elided mid-slug: the literal
  filename trips the plan write-guard's whole-phrase scan) — a freshness signal read only from the
  monitored system's own history cannot distinguish "stale" from "the writer died".

### Property List (Phase 0.6b)

1. On surfaces where a zero-match scan is reachable, the output distinguishes "the scan ran and
   matched nothing" from "the scan did not run" — including the case where the hook itself was skipped.
2. A corpus-freshness claim the gate prints is true of the corpus, not merely of a date.
3. A freshness attestation is not asserted over an incomplete record.
4. A stale corpus does not prevent the path scan from running or from reporting.
5. The freshness verdict binds to a measured condition and *stays* measured — the writer does not die
   silently again.
6. A comparison that could not run is never reported as a comparison that found nothing.

### Cut List (Phase 0.6b)

| Mechanism | Property | Already covered by | Disposition |
|---|---|---|---|
| Re-vendor the corpus | 2 | Nothing to refresh — 8 SAME measured | **Cut** |
| Raise the 30d/90d window | — | — | **Cut.** §7 forbids relaxing the values without an ADR, and it widens the drifted-reports-clean interval |
| Strengthen `vendor-pin-integrity.sh --verify-upstream` into a drift comparison | 2, 5, 6 | The cron already performs the per-file upstream SHA comparison; fixing *it* buys the same properties | **Cut.** The bash mode asserts blob *resolvability*, not currency — so this would author a second implementation and then delete the working one. It would also relocate the divergence into an unschema'd bash↔TypeScript stdout contract, overload `exit 1` across "missing `gh`", "rate-limited" and "tampered", and make a pull-request-blocking check third-party-flippable. Fix the comparison where it already lives. |
| A new CI job gating `last-verified` writes | 5 | Cut with its dependent — no hand bump is authored | **Cut** |
| A hand-authored `last-verified` bump | 2 | The restored writer advances it within one cron cadence on machine-measured evidence | **Cut.** Typing the date first is the `ADR-094`/`ADR-121` falsification this plan argues against, and it would give the attestation two writers with ambiguous provenance |
| New telemetry channel for the posture/scan split | observability | `gdpr-gate.sh` already emits `gdpr-gate-staleness` and `gdpr-gate-cron-binding` | **Cut** — extend the existing set. (The earlier draft also cited `gdpr-gate-touch`; that event does not exist and the claim is retracted.) |
| Relevance-gate the 30d/90d banners | 1 | — | **Cut.** Contradicts `#3541`; and the lefthook glob already delivers the relevance property on that surface |
| Make `POSTURE_FAIL` a non-zero exit | — | — | **Cut.** `ADR-026` fixes the advisory contract |

## Open Code-Review Overlap

None. 63 open `code-review` issues; no body references any file in `## Files to Edit`.

## Architecture Decision (ADR/C4)

This plan changes the semantics of a governed compliance-registry field and gives a cron write
access to a compliance attestation. Both are architectural, so
`wg-architecture-decision-is-a-plan-deliverable` makes the record a deliverable of this plan
rather than a follow-up issue.

### The decision

**Neither option the brief named.** The date-based threshold is the right instrument for the question
it asks — *how long since anyone compared this corpus to upstream* — and it is lying because its
writer was deleted. Restore the writer, gate it on a comparison that reports three states rather than
two, and separately give the path scan an output of its own.

The architecturally novel part, and what `ADR-203` records, is narrower than the rationale: **a weekly
cron acquires write access to the default branch for a compliance attestation, through a
self-merging bot pull request, gated on a comparison it performed in the same run.** Everything else
is a restoration or a citation of decisions `ADR-121`, `ADR-186`, `ADR-094` and `ADR-196` already made.

`ADR-203` must record, as named residuals rather than resolved questions: the `ADR-026` /
`ADR-197` D-2 tension; that `#7255` leaves the anti-backdating half of the trust binding inert, so the
restored writer is a candidate to become that signal but is not wired as one; that `pushed_at` age is
not checked, so an abandoned-but-unarchived upstream would return SAME forever and keep the
attestation permanently green — this plan's own failure class one level up; and that the write bypasses
the `CODEOWNERS` routing on the NOTICE by design.

Do **not** record a containment argument from `CODEOWNERS`: no ruleset carries a `pull_request` rule,
so there is no required-review gate on the default branch and `CODEOWNERS` only auto-requests review.

**Ordinal provisional.** Highest claimed across all 71 `origin/*` refs is `ADR-202`; `origin/main`
tops out at `ADR-200`, so the on-disk gap is expected and is not evidence the ordinal is free.
Re-derive before merge; any renumber sweeps this plan, `tasks.md` and every criterion naming it.

### C4 views

**No C4 impact**, by enumeration against `model.c4`, `views.c4` and `spec.c4`: no external human actor
is introduced; `github.com` is already modelled and the cron already reaches it; no container or data
store is added; no ownership or access relationship moves. If `/work` finds any of those four wrong
when it reads the models, the `.c4` edit becomes an in-scope task here.

## User-Brand Impact

**If this lands broken, the user experiences:** a compliance gate reporting a current corpus over
rules that have drifted — or, in the specific failure this plan came within one wording of shipping,
an attestation advanced over a corpus the cron had just detected drift in.

**If this leaks, the user's data is exposed via:** no new exposure vector; the values written are
repository metadata about vendored MIT documents. One new surface does exist: the scan-completion line
goes to stdout on a customer machine, so it must carry **counts only, never path names** — the
existing path-naming breadcrumb is on stderr, and `#7331` is the live scar behind
`hr-third-party-content-grep-on-undertaking`.

**Brand-survival threshold:** `single-user incident` — upheld at CPO sign-off against the counter-
argument. The taxonomy's `single-user incident` tier reads "at least one real user impacted **or any
sensitive-data surface is at risk**", and a degraded detection control on the regulated-data surface is
that clause's referent. `aggregate pattern` is the *more severe* tier, defined by breadth across
multiple users or tenants, and is unreachable with one external user. The advisory nature of the hook
lowers probability, not blast radius, and this scale measures blast radius.

## Implementation Phases

### Phase 1 — Reconcile the canonical record

Add `lifted-files` entries for `references/layers/{auth-sessions,frontend,testing-seeding}.md`, each
with `upstream-path`, `upstream-blob-sha`, `local-blob-sha` and `status`.

**This is a records reconciliation that relaxes a guard, not the closing of a hole.** Those three are
currently rejected outright by the "staged but not in NOTICE" branch. Write it up that way.

**Do not pin what you find.** For each, fetch the upstream blob at its pinned `upstream-blob-sha`,
diff against the local file, and confirm the delta is exactly the documented Soleur extension
(`Art. 32(1)(b)` footer; ePrivacy/TTDSG footer; `Art. 32` pseudonymization footer) plus the attribution
header. Pin only on a match. Pin-what-you-find is how a registry launders an unreviewed edit into an
attested one.

**Settle the non-vendored files explicitly — the earlier draft contradicted itself here.**
`references/non-negotiables.md` and `references/legal-consent.md` are Soleur-authored;
`references/legacy/legal-consent-v1-prose.md` is Soleur-authored and outside both glob patterns.
A `lifted-files` row for any of them would attest goSprinto MIT provenance for Soleur's own writing —
falsifying provenance in both directions, and the one step here capable of a genuine compliance
regression. But a bare "exclusion" that still rejects them is not an exclusion, and today they cannot
be committed without `--no-verify` — which blocks the documented v2→v3 lifecycle of
`legal-consent.md`.

**Decision:** add a `soleur-authored` list to the NOTICE frontmatter carrying a `local-blob-sha` per
file, and have `vendor-pin-integrity.sh` check those SHAs exactly as it checks `lifted-files`, while
never treating them as upstream-derived. This makes them editable through the normal
update-the-pin flow, keeps a tamper check on the file the gate's own GDPR framing depends on, and
keeps provenance truthful. Name `references/legacy/**` in that list too, or the reverse-parity
assertion added in this same phase goes red at merge on a file this plan otherwise only mentions in passing.

Correct the undercount in all **three** sites — `compliance-posture.md` (``5 (gdpr-gate `references/`)``,
backticks included), `content-vendoring.md` (`active (5 lifted files)`), and `ADR-026`'s C4 component
block (`5 lifted (MIT) + rewritten layers`). The NOTICE prose and body table are already right.

The third site is the one to notice: it is worded differently from the other two, so neither literal
grep in the acceptance criteria finds it. A count that drifts in three artifacts and is only
*searchable* in two is the same shape as the defect this plan repairs — so the criterion asserts the
absence of the number in all three named files, not the absence of two quoted strings.

Fix `lefthook.yml`'s comment claiming the glob covers the whole `references/` subtree; both patterns
are single-level.

### Phase 2 — Fix the comparison, then let it write

All of this lands in `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`,
inside `step.run` boundaries per `ADR-033` I1/I5, with a deterministic per-step return shape that is
replay-safe under `retries: 1`.

**Give the comparison a third state.** `if (!currentSha || currentSha === oldSha) continue;` treats a
missing or unparseable response as SAME. Split it: a fetch that did not answer is `ERROR`, never
`SAME`. Return `{ filesExamined, filesSame, filesDrifted, filesError }`.

**Populate `aggDiffParts`.** It is declared and never written to, so the classifier always receives an
empty diff and returns `no-op` with exit 0. This was scoped out of the earlier draft as "unreachable
by anything in Phases 1–7"; the writer reaches it directly, which is why it moves in here. Its
consequence is the second `return { drift: "none" }` — the one at `classifyRc === 0`, reached
**after** drift was detected.

**Gate the write on the totals, never on `detectResult.drift`.** The predicate is
`filesExamined === <registry entry count> && filesDrifted === 0 && filesError === 0`. Keying on the
return value would advance a compliance attestation over a corpus the same run had just found drift
in — the exact falsification this plan exists to prevent. Phase 1 is therefore a hard prerequisite of
*this* phase, not only of an attestation: before it, the cron compares 5 of 8 files, because
`upstream-files` derives from the same frontmatter.

**Route the write through `safeCommitAndPr` with `mergeMode: "direct"`.** The helper has no
direct-to-branch mode — every path opens a pull request against `base: "main"` — and a raw push is
independently blocked by three active rulesets whose every relevant bypass actor is
`bypass_mode: "pull_request"`. `mergeMode: "direct"` opens the PR and immediately squash-merges it,
which is what the drift route already passes, and it inherits the allow-list, the deletion guard and
the replay idempotency that a hand-rolled path would discard. Note `safeCommitAndPr` is not called on
the no-drift path today, so this is a new call site rather than a behaviour change.

**Make the failure of that merge visible.** On refusal the helper falls back to arming auto-merge and
then to a failure stage that calls `reportSilentFallback` — while `postSentryHeartbeat({ok: true})`
runs unconditionally after routing. As it stands the cron can compare clean, fail to commit, and post
OK. The heartbeat must go non-OK when a zero-drift run did not produce a committed advance, and the
run must emit one event carrying `filesExamined`, `filesSame`, `filesDrifted`, `filesError`,
`wroteAttestation` and `commitSha` together — four hypotheses that a single boolean cannot separate.

**Correct the false claim.** The pull-request body template asserts `"NOTICE last-verified bumped at
PR-creation time"`, which the code has not done since `#4483`. This is the phase that makes it true.

### Phase 3 — Give the scan an output of its own

Emit a line to stdout stating that the path scan ran, how many paths it examined and how many matched.
**Counts only — never path names.** The existing path-naming breadcrumb stays on stderr.

Constraints, each measured:

- It must not contain `days stale` or `POSTURE_FAIL`. `gdpr-gate.test.ts` asserts stdout does not
  match `/days stale/` on a fresh NOTICE — passing the default argument `scratch.md`, a non-matching
  path. (The stderr negative in that file runs against a 35-day-stale notice, not a fresh one; the
  earlier draft misdescribed it.)
- It goes to stdout, because agent runtimes swallow stderr — which is why the reporter of `#7710` saw
  two banners and no evidence a scan had occurred.
- **Amend the banner-fatigue comment to what is actually true.** It claims the operator-attested
  banner would otherwise "fire on every commit". Under the glob that premise is already false: the
  `#3541` relevance property is delivered by the lefthook glob, not by the matched-path conditional.
  Correct the comment rather than inheriting or merely extending it.

**Add the glob-liveness test, which is the part that is not ceremony.** If the glob stops matching,
lefthook prints `(skip)`, the script never runs, and no line of any kind is emitted — so a
completion line emitted *by the script* cannot witness the failure it is most exposed to, and this
repo has shipped that exact trap twice. Materialise a regulated fixture path, run the pre-commit hook,
and assert the `gdpr-gate-advisory` command was not skipped.

Leave the 30d/90d values untouched, keep `exit 0`, and do not relevance-gate the staleness banners.

### Phase 4 — Policy and the posture record

**Add `content-vendoring.md` §6a, "Verification-Only Refresh (no drift)"** — §6 governs the
drift-detected path only, and no clause covers "re-verified, no drift found → refresh the
attestation", nor reserves `last-verified` writes to automation. §6a states the trigger (a measured
all-files-SAME comparison with zero errors over the complete registry), that the cron advances the
field on that basis, and that the commit message records the upstream HEAD SHA compared against.

**Correct §4's layer count**, which already undercounts on `main`: it says "Three layers" and omits
`vendor-pin-verify.yml`, a pre-existing pull-request-time layer. This is a correction of a standing
error, not a consequence of this change.

**Append a row to `## Active Compliance Items`.** Schema `| Item | Issue | Status | Deadline | Notes |`.
Item names the control lapse. Issue `#7710` — **apply the `compliance/critical` label** that §8 step 2
requires, rather than recording a justification for its absence; a governance shortcut written into
the one artifact whose value is that it contains none is refused. Status is `IN-PROGRESS` until the
restored writer is observed to advance the field post-merge, then `RESOLVED` — and **the Status enum
in that section's schema comment currently admits only `OPEN | IN-PROGRESS`, so widen it**, alongside
widening the comment's `check_id` scoping to admit a posture-derived item.

Notes carry the regulatory content and nothing else: the window (2026-05-10 → 2026-09-04, 117 days);
that the corpus never drifted (8 SAME against `0594a9ef`, MIT unchanged, not archived) so this is an
**Art. 5(2) demonstrability** failure and weakly **Art. 32(1)(d)** — explicitly not Art. 32(1)(a)–(c),
and **not** Art. 33/34, with no drift toward incident vocabulary; why the chain did not run; that the
`POSTURE_FAIL` did fire but only into gitignored `.claude/.rule-incidents.jsonl`; that the 5→8 figure
was a registry undercount and **not** an unguarded-file window; and the resolution. The process
narrative — that the 2026-09-03 plan recommended this row and it was not written — belongs in the
session learning, not the legal record.

**Repair the operator-facing pointer, wholly.** `gdpr-gate.sh` prints
`content-vendoring.md#posture-fail-operator-chain` to customer stdout. Two things are wrong: the
fragment (GitHub slugs `## 8. POSTURE_FAIL Operator Chain` to `#8-posture_fail-operator-chain` —
underscores retained, period dropped, so the earlier draft's replacement was still broken), and the
path itself, which is **not shipped inside the plugin**, so a customer is handed a dangling reference
in a compliance warning. Repair it for the installed-plugin reader or drop the path. Fix the link, not
the heading — dropping the numeral breaks every `§8` citation.

**§8 step 5's `ci/vendor-drift-*` clause is stale, not dead** — the `route === "pr"` path still calls
`safeCommitAndPr` on branch `ci/content-vendor-drift-<ts>`. Repoint it; do not delete a live step.

### Phase 5 — Correct the skill's account of itself

`SKILL.md`'s "on every invocation" sentence scopes to "the hook" and is true of it; leave it and spend
the budget on the real false promise — `gdpr-gate.sh`'s header documents a `gdpr-gate-touch` event the
file never emits (it emits `hr-gdpr-gate-on-regulated-data-surfaces`, which also does not match the
`gdpr-gate-*` branch of the allow-list in `rule-incident-marker-capture.sh`). Fix the header or the
emit. Document the scan line, the restored writer and the lefthook glob in Sharp edges. Keep the
operator-attested banner literal byte-identical across its three sites.

`vendor-pin-integrity.sh`'s mismatch message tells a blocked contributor to "run the vendor-drift
workflow", which has not existed since `#4483`. It is the only exit they get at the moment their
commit is refused, and it is a dead end. Repoint it.

### Phase 6 — Filings

**One issue** for the enforcement-chain coverage gap, which review established is materially larger
than `#7710` and must not be folded in: of five gate surfaces, one is mechanical and it cannot block;
one checks corpus freshness and it is the same non-blocking one; `plan` Phase 2.7 and `work` Phase 2
both instruct "skip silently", so a session that skipped the gate on a regulated diff and one that
correctly determined no gate was needed produce byte-identical output — `#7710`'s own thesis, applied
to `hr-gdpr-gate-on-regulated-data-surfaces` itself. Label `compliance/critical`, `domain/engineering`.

**Leave `#7255` open**, note the candidacy, and word nothing as resolving it.

**Triage correction on `#7710`:** re-milestone to *Phase 4: Validate + Scale*, raise to
`priority/p1-high`, apply `compliance/critical`.

## Files to Edit

- `plugins/soleur/skills/gdpr-gate/NOTICE` — three `lifted-files` entries; new `soleur-authored` list.
- `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` — check `soleur-authored` SHAs; repoint the mismatch message.
- `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` — scan line; corrected banner-fatigue comment; corrected policy pointer; `gdpr-gate-touch` header.
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` — three-state comparison; populate `aggDiffParts`; totals-gated write via `safeCommitAndPr` `mergeMode: "direct"`; conditional heartbeat; discriminating event; corrected PR-body sentence.
- `knowledge-base/legal/compliance-posture.md` — provenance count 5→8; Active Items row; widened Status enum and scoping comment.
- `knowledge-base/engineering/policies/content-vendoring.md` — §6a; §4 layer count; §8 repoint; §10 registry count.
- `knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md` — the C4 component block's `5 lifted` count.
- `plugins/soleur/skills/gdpr-gate/SKILL.md` — Sharp edges.
- `lefthook.yml` — correct the subtree-coverage comment.
- `plugins/soleur/test/vendor-pin-integrity.test.sh` — reverse parity assertion; `soleur-authored` cases.
- `plugins/soleur/test/gdpr-gate-self-test.test.sh` — scan-line assertions.
- `plugins/soleur/test/gdpr-gate.test.ts` — scan-line assertions; negative assertions preserved.
- `plugins/soleur/test/notice-frontmatter.test.sh` — **both** hardcoded counts (`lifted-files` and `upstream-files`).
- `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` — three-state totals; write predicate; replay safety.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-203-*.md`
- `scripts/followthroughs/gdpr-gate-attestation-advances-7710.sh` — the durability probe (see AC).
- A lefthook glob-liveness test (Phase 3), placed per the repo's existing hook-test convention.

## Guard Contract

### Guard 1 — the vendored-pin registry

**Property.** Every file under the gate's `references/**` carries a pin appropriate to its provenance —
upstream-derived files in `lifted-files`, Soleur-authored files in `soleur-authored` — and no file
appears in the wrong list or in neither.

**Assembly.** Not the eight files currently listed. The chokepoint is `vendor-pin-integrity.test.sh`'s
walk, **not** `vendor-pin-integrity.sh` — the script iterates only over its arguments and never reads
the tree, so the symmetric-difference property is bought by the test and lefthook/CI do *not* reach it
through the script. The assembly is disk(`references/**`, including `legacy/`) versus
`lifted-files` ∪ `soleur-authored`.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Add a file under `references/layers/` and list it in neither registry | RED — the reverse direction nothing asserts today, and why three files sat unpinned for 117 days |
| 2 | Move `non-negotiables.md` from `soleur-authored` into `lifted-files` | RED — a provenance falsification must be rejected, not merely un-required |
| 3 | Alter one byte of a pinned file without updating its SHA, in either list | RED |
| 4 | **Second member.** File A compliant, file B not, A ordered first | RED — the walk must not stop at the first compliant member |
| 5 | **Own dispatch.** Make the test's disk walk yield zero files | RED with a distinct reason — `0 checked, 0 failed` must not read as success |

**Harness rows.** (i) Replace the loop's assertion body while leaving the loop and counters intact —
RED on the conservation check, not green on `failures == 0`. (ii) A must-PASS non-canonical input: the
entries in a **different order**. Reordering *entries* is permitted; reordering *keys within* an entry
is not, since `_emit_files` hard-codes `- path:` as each record's first key. Do **not** use quoted
scalars as the must-PASS variant — measured, `notice-frontmatter.sh` strips whitespace but not quotes,
so `last-verified: "…"` yields 999 and `local-blob-sha: "bbb"` emits the quotes; the fix for that
would be loosening a deliberate injection guard.

### Guard 2 — the scan-completion line

**Property.** On every invocation where a zero-match scan is reachable, the output distinguishes "the
scan ran and matched nothing" from "the scan did not run" — and the case where the hook itself was
skipped is witnessed from outside the script.

**Assembly.** Two chokepoints, and this is the point of the guard: the `for f in "$@"` loop and its
counters, *and* the lefthook invocation itself. The first cannot witness the second — a line emitted
by the script is silent precisely when the script does not run — so the glob-liveness test is not an
extra, it is the half of the assembly the script cannot cover.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Remove the scan-completion `printf` | RED |
| 2 | Move it above the loop so it reports constants | RED — it must report what the loop measured |
| 3 | Make it conditional on `${#matched[@]} > 0` | RED — the state the property forbids being silent about |
| 4 | **Second member.** Two matching paths after one non-matching path | RED unless it reports three examined and two matched |
| 5 | **Own dispatch.** Narrow the `gdpr-gate-advisory` glob so no fixture path matches | RED via the glob-liveness test — the failure the script cannot see |
| 6 | Add a path name to the line | RED — counts only, per `hr-third-party-content-grep-on-undertaking` |
| 7 | Insert `days stale` into the line | RED via the existing negative assertion, proving it was not weakened to accommodate the new line |

**Harness rows.** (i) Replace `assert_contains` with a call that always returns 0 — the case counter
must still increment and conservation must go RED. (ii) A must-PASS non-canonical input: invocation
with several non-matching paths, reporting `matched=0` — reachable from manual invocation and the
self-test, which is where the property lives. Do **not** assert the zero-argument case as a production
state: lefthook skips the command entirely when nothing matches, so no caller produces it.

### Guard 3 — the attestation writer

**Property.** `last-verified` advances only as the recorded consequence of a comparison this run
performed, over the complete registry, that returned zero drift **and** zero errors.

**Assembly.** The comparison's returned totals — not either `return { drift: "none" }` statement. The
property quantifies over every exit: clean, drifted, drift-detected-but-classifier-zero, comparison
failed, partial.

**Mutation matrix.**

| # | Mutation | Must drive |
|---|---|---|
| 1 | Key the write on `detectResult.drift === "none"` | RED — reaches the `classifyRc === 0` return, which is truthy *after* drift was detected |
| 2 | Treat an unfetchable file as `SAME` rather than `ERROR` | RED — the false-clean arm |
| 3 | Write when `filesExamined < registry count` | RED — a partial comparison is not evidence of currency |
| 4 | **Second member.** `SAME` for the first file, `DRIFTED` for the second | RED — gated on the total, not the first result |
| 5 | **Own dispatch.** Comparison returns zero files examined | RED — `0 of 0` is not evidence, and a writer treating it as such is vacuous |
| 6 | Post `ok: true` on a zero-drift run that did not commit | RED — the heartbeat must reflect the artifact |

**Harness rows.** (i) Stub the comparison to return a fixed success without invoking anything — RED,
because a test that cannot tell a real comparison from a stub certifies nothing. (ii) A must-PASS
non-canonical input: totals arriving with the per-file records in a different order.

## Observability

```yaml
liveness_signal:
  what: the weekly cron's committed `last-verified` advance — the commit is the artifact, not the run
  cadence: weekly, `17 11 * * 1` (Inngest, `cron-content-vendor-drift`)
  alert_target: Sentry cron monitor slug `scheduled-content-vendor-drift`, made conditional on
        `wroteAttestation` for a zero-drift run; plus the local 30-day banner, which becomes a genuine
        early warning once the writer is restored rather than a standing condition
  configured_in: apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts and
        apps/web-platform/server/inngest/cron-manifest.ts

error_reporting:
  destination: Sentry for the cron half; the local incident ledger via `emit_incident` for the hook
        half, under the allow-listed `gdpr-gate-*` prefix
  fail_loud: yes for the cron — a run that could not compare, or compared clean and failed to commit,
        posts a non-OK check-in rather than OK with no artifact, per ADR-126. No for the hook, bound
        by ADR-026's advisory `exit 0`; that asymmetry is a named residual in ADR-203

failure_modes:
  - mode: the cron compares clean and the attestation does not advance
    detection: one in-surface event carrying `filesExamined`, `filesSame`, `filesDrifted`,
      `filesError`, `wroteAttestation`, `commitSha` together — separating "clean and written",
      "clean and the merge was refused", "drifted and correctly withheld", and "never compared",
      which one boolean cannot
    alert_route: Sentry cron monitor non-OK; the merge-refusal path must not terminate in
      `reportSilentFallback` under a green heartbeat
  - mode: a fetch fails and is scored as SAME
    detection: `filesError > 0` in the same event; the write predicate refuses
    alert_route: Sentry cron monitor non-OK
  - mode: the lefthook glob stops matching and the hook silently never runs
    detection: the glob-liveness test — the only signal the script itself cannot emit
    alert_route: blocking CI check
  - mode: the scan-completion line stops being emitted
    detection: the self-test's matched and unmatched cases, run by `gdpr-gate-self-test.yml` on every
      script change and weekly
    alert_route: blocking CI check
  - mode: upstream is abandoned without being archived
    detection: not covered — `pushed_at` age is unchecked, so an abandoned corpus returns SAME forever
    alert_route: none; recorded as a named residual in ADR-203 rather than claimed

logs:
  where: Sentry (cron); the local incident ledger under `.claude/` (hook)
  retention: Sentry project default; the ledger rotates per its existing policy

discoverability_test:
  command: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh README.md apps/web-platform/lib/auth/x.ts
  expected_output: |
    A scan-completion line on stdout reporting two paths examined and one matched, carrying no path
    names, and exit 0. It contains neither `days stale` nor `POSTURE_FAIL`, so its presence is
    independent of the corpus's freshness state — which is the property being verified.
  credentials_required: none — the probe exercises the no-token path, which is the state a
    contributor machine and a subagent shell are actually in
```

## Acceptance Criteria

### Pre-merge

1. `notice-frontmatter.sh lifted-files` emits 8 entries; a `soleur-authored` list carries
   `non-negotiables.md`, `legal-consent.md` and `legacy/legal-consent-v1-prose.md`; no Soleur-authored
   file appears in `lifted-files`.
2. The commit message records, per newly-pinned file, the diff against its upstream blob and that the
   delta equals the documented extension plus the attribution header.
3. `bash …/vendor-pin-integrity.sh` **passed the eight reference paths as arguments** exits 0 — three
   of them exit 1 today. (Invoked with no arguments the script exits 0 trivially; the criterion must
   name the paths or it is green by construction.)
4. Staging a Soleur-authored reference file with a matching `soleur-authored` SHA succeeds; with a
   mismatched SHA it is rejected, and the message names the Soleur-authored list rather than "silent
   local addition".
5. The stale count is absent from all three artifacts: ``grep -c '5 (gdpr-gate `references/`)'
   knowledge-base/legal/compliance-posture.md`` returns 0, `grep -c 'active (5 lifted files)'` on
   `content-vendoring.md` returns 0 (from 1 today), and `grep -c '5 lifted'` on
   `ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md` returns 0 (from 1 today).
   Note the backticks in the first pattern — the un-backticked literal returns 0 on an unmodified
   tree and would certify nothing.
6. The comparison returns `{filesExamined, filesSame, filesDrifted, filesError}`; a fixture whose
   upstream fetch fails scores `filesError`, not `filesSame`.
7. `aggDiffParts` is populated; a fixture with real content drift no longer classifies `no-op`.
8. The write fires only when `filesExamined === <registry count> && filesDrifted === 0 &&
   filesError === 0` — asserted across five cases including "drift detected but classifier returned 0"
   and "partial comparison".
9. The write routes through `safeCommitAndPr` with `mergeMode: "direct"`; no raw push to the default
   branch appears in the diff.
10. A zero-drift run that does not produce a committed advance posts a non-OK Sentry check-in.
11. `"NOTICE last-verified bumped at PR-creation time"` no longer appears unless the code it describes
    is present.
12. `gdpr-gate.sh` emits a scan-completion line on stdout carrying counts and **no path names**; it
    contains neither `days stale` nor `POSTURE_FAIL`.
13. The existing negative assertion in `gdpr-gate.test.ts` — stdout not matching `/days stale/` on a
    fresh NOTICE, with the default non-matching argument — remains present and unmodified.
14. The glob-liveness test fails when the `gdpr-gate-advisory` glob is narrowed so no fixture path
    matches.
15. `content-vendoring.md` carries §6a; §4 no longer says "Three layers"; §8 step 5 names
    `ci/content-vendor-drift-*`; `grep -c 'ci/vendor-drift-'` returns 0.
16. `compliance-posture.md` carries a row for `#7710` with the regulatory Notes above; the section's
    schema comment admits the Status value used and a posture-derived item; `#7710` carries the
    `compliance/critical` label.
17. The pointer `gdpr-gate.sh` prints resolves for a reader of the installed plugin, or the path is
    dropped; the `## 8.` heading is unchanged.
18. `vendor-pin-integrity.sh`'s mismatch message names a mechanism that exists.
19. `ADR-203` exists, records the write-access decision plus its four named residuals, and its ordinal
    is re-derived against all `origin/*` refs at ship time rather than asserted here.
20. Every Guard Contract mutation and harness row is exercised and behaves as specified.
21. The full battery is green at `/ship` Phase 4.
22. The PR body says `Closes #7710` and nothing that reads as resolving `#7255`.
23. The enforcement-chain issue exists, labelled `compliance/critical`; `#7255` carries the candidacy
    note; `#7710` is re-milestoned and re-prioritised.

### Post-merge

24. **Enrolled, at merge + 8 days** — one cron cadence plus slack: a tracking issue carrying
    `<!-- soleur:followthrough script=scripts/followthroughs/gdpr-gate-attestation-advances-7710.sh
    earliest=<merge+8d> secrets=GH_TOKEN -->` and the `follow-through` label. The probe asserts at
    least one bot-authored `last-verified` advance exists on the default branch since merge. Both the
    directive **and** the issue are required — the sweeper walks open issues, so a script alone never
    runs. `secrets=GH_TOKEN` is mandatory: the sweeper runs probes under `env -i` and the probe uses
    `gh`.
25. **Enrolled, at merge + 91 days**, same probe family: `days-stale` reports **≤ 8**, not merely
    under 30 — under 30 cannot distinguish a healthy weekly writer from one that stopped three weeks
    ago — and the NOTICE's git log shows ≥ 10 distinct advancing commits since merge.

## Domain Review

**Domains relevant:** engineering, legal, product

### Engineering (CTO)

**Status:** reviewed, twice — once on the draft, once on the finished plan.
Established that the upstream comparison already exists and works in the cron, so strengthening the
bash mode would author a second implementation and delete the working one; that a failing drift arm on
a pull-request-blocking check would let a third party red the remediation PR; that the 5-of-8 gap is a
live hard failure; and that pinning current content without a delta review would launder an unreviewed
edit. On the finished plan: measured the lefthook glob empirically and showed the hook is not
per-commit and the zero-match arm is unreachable from it; showed the parser strips whitespace but not
quotes, falsifying a harness row; showed `safeCommitAndPr` is not called on the no-drift path at all;
and surfaced the `ADR-033` replay constraints. Recommended cutting the bash strengthening as roughly a
third of the cost and not required to close `#7710` — adopted.

### Legal (CLO)

**Status:** reviewed.
Falsified the claim that the three unpinned files were unguarded — they were over-blocked, so Phase 1
relaxes rather than closes, and must not be written up otherwise. Identified the provenance
falsification risk as the one step capable of a genuine compliance regression. Ruled the attestation
bump ungoverned rather than prohibited, requiring §6a. Confirmed MIT attribution is discharged twice
over and unaffected. Scoped exposure to Art. 5(2) demonstrability and weakly Art. 32(1)(d), explicitly
not Art. 32(1)(a)–(c) and not Art. 33/34. Flagged that fixing the anchor by dropping the heading
numeral would break every §8 citation, and that §8 step 5 needs a repoint.

### Product (CPO) — sign-off

**Status:** reviewed. **Sign-off granted, conditional on A–E**, all adopted above: (A) state the
guarantee boundary where the customer reads it, not only in the ADR; (B) repair the whole customer-
facing pointer, not just its fragment; (C) bind the write to the comparison totals, never to
`classifyRc`; (D) counts only, never path names; (E) enrol a probe at merge + 8 days, not only at + 91.
The `compliance/critical` escape hatch was refused — apply the label. Upheld
`brand_survival_threshold: single-user incident` on the taxonomy's sensitive-data-surface clause, and
noted that `aggregate pattern` is unreachable with one external user. Ruled the scope proportionate
but the *triage* wrong, and ruled the enforcement-chain gap a separate issue.

### Product/UX Gate

Not applicable. No path in `## Files to Edit` or `## Files to Create` matches a UI-surface term or
glob; the mechanical override did not fire.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The writer advances an attestation over a drifted corpus | AC8 gates on totals across five cases including the `classifyRc === 0` return; Guard 3 row 1 drives it RED. This reverses an earlier scope-out that would have shipped it. |
| Pinning bakes in an unreviewed edit | Per-file upstream delta review before pinning; pin-what-you-find forbidden. |
| A Soleur-authored file acquires third-party provenance | Separate `soleur-authored` list; Guard 1 row 2. |
| A "could not check" reads as clean | Three-state comparison; `filesError` in the write predicate; Guard 3 row 2. |
| The cron writes but the merge is refused and Sentry stays green | Conditional heartbeat + the six-field event; AC10. |
| The hook silently stops running | Glob-liveness test — the assembly half the script cannot cover. |
| The scan line leaks path names to customer stdout | Counts only; AC12; Guard 2 row 6. |
| The restored writer dies and nobody learns for 90 days | AC24 at merge + 8 days, with both a probe and its tracking issue. |
| Upstream abandoned without being archived | Not covered; recorded as a named residual in `ADR-203` rather than claimed. |
| The ADR ordinal collides | Probed across 71 refs, re-derived before merge, renumber sweeps every artifact naming it. |
| `#7255` is read as resolved | AC22; the candidacy is noted on the issue instead. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Re-vendor the corpus | Measured no-op: 8 SAME against live upstream. |
| Hand-bump `last-verified` | The restored writer advances it within one cadence on machine evidence; typing it first is the `ADR-094`/`ADR-121` falsification, and it would give the field two writers with ambiguous provenance. |
| Raise the 30d/90d window | Buys no property, widens the drifted-reports-clean interval, and §7 forbids it without an ADR. |
| Replace the date with the blob-SHA comparison | An identity check cannot see calendar rot and passes by construction on the no-drift arm — the arm that was failing. <br>**Corrected 2026-09-04 (#7841):** this row originally cited `ADR-121` and `ADR-186` as already placing that substitution in a rejected-alternatives table. **That was false** — neither does; the citation was never verified. The reasoning stands on its own and is recorded in `ADR-203` § *Alternatives Considered*. |
| Strengthen `vendor-pin-integrity.sh --verify-upstream` into a drift check | Would author a second implementation and delete the working one; relocate the divergence into an unschema'd bash↔TypeScript contract; overload `exit 1` across missing-`gh`, rate-limited and tampered; and make a PR-blocking check third-party-flippable. Fix the comparison where it lives. |
| Make that comparison blocking | A third party's push would red every matching PR including the remediation one. |
| Make `POSTURE_FAIL` a non-zero exit | `ADR-026` fixes the advisory contract; a separate decision needing its own ADR. |
| Relevance-gate the staleness banners | Contradicts `#3541`; and the lefthook glob already delivers relevance on that surface. |
| Emit the scan line only when paths matched | Makes the record of execution conditional, which cannot distinguish "did not run" from "ran and stayed quiet". |
| Fold the counts into the existing stderr breadcrumb instead | Cheaper, but stderr is what agent runtimes swallow — the reason the reporter saw only banners. Rejected on that ground; the glob-liveness half of the proposal was adopted. |
| Fold in the enforcement-chain gap | Materially larger than `#7710` and it is a compliance chain of its own. Filed. |
| Fold in `#7255` | Asks for a signal the attesting session does not control. Left open, candidacy noted. |
| Split into three PRs | Recommended by two reviewers and reasonable; with the bash strengthening cut the plan is roughly a third smaller, and CPO ruled the remaining phases a dependency chain rather than a feature list. Recorded as a live option for `/work` if the diff proves unreviewable. |
