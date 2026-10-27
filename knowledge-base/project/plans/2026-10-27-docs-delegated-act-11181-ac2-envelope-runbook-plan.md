---
title: "docs: Commit the AC2 delegation-envelope runbook for epic #11181"
type: docs
date: 2026-10-27
slug: docs-delegated-act-11181-ac2-envelope-runbook
branch: feat-one-shot-11181-ac2-envelope-runbook
issue: 11181
lane: cross-domain
brand_survival_threshold: none
---

# docs: Commit the AC2 delegation-envelope runbook for epic #11181

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** 2 (Research Insights, Premise Validation) — the MINIMAL plan's remaining sections were verified, not rewritten.
**Research roles run:** sequential-fallback inline in this subagent (no `Agent` tool in the OpenCode Task context): plan Phase 1 fan-out, plan-review eng panel (DHH / Kieran / code-simplicity lenses), deepen-plan Phases 2–5 (skill discovery, learnings scan, verify-the-negative, post-edit self-audit), conditional gates 4.5/4.10/4.11/4.13 evaluated and skipped. `Reviewed-Coverage: sequential-fallback` — no independent sub-review ran.

### Key Improvements

1. Every verification command the plan prescribes was executed once at plan time (AC-1..AC-5 forms measured against the real bytes and branch); the self-reference trap in AC-3's absence-grep was found by the sharp-edges catalogue and closed with a PR-body prose rule.
2. Premise validation closed with live evidence: epic #11181 OPEN, delegation comment 6417763814 author-typed `User` at the envelope's recorded time, PR #11210 MERGED with `mergedAt` equal to the envelope's precondition timestamp, dispatched applies green, destination path absent and unclaimed by any receipt.
3. The public-repo redaction question was resolved as a ruled technical item (byte-identical wins: ADR-289 receipts fingerprint the git-read bytes; content carries no secret values) and persisted to decision-challenges.md for CTO confirmation.

### New Considerations Discovered

- The 4.5 network-outage scan hits twice on "unreachable" — both are the privacy claim ("private IPs are unreachable from the internet"), not a connectivity symptom; the checklist does not fire (disposition recorded below).
- The post-merge "epic OPEN" check in AC-3 is a consequence read, not the verifiable property; the PR-body grep is the deterministic half (per plan-review standing-check reasoning about ambient flip risks).
- No decision-challenges row can be auto-ruled in this harness (no `Agent` tool): three `pending - assumed:` rows are primed for the lead's batched CTO spawn (tasks.md 1.1).

## Overview

The executed-act production envelope for epic #11181 AC2 (owner-side relay activation under ADR-068 Phase 3) exists today only as a scratch file at `/tmp/opencode/delegated-act-11181-ac2-envelope.md`. ADR-289 requires the verifier to read envelope bytes from git (`git show HEAD:<path>`), so a scratch-only envelope is unverifiable in any later audit and is lost on any machine restart. This plan commits that single file, byte-for-byte, to its intended KB destination `knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md`, alongside the existing `delegated-merge-*-envelope.md` precedents. The deliverable is a KB-only documentation PR with no code or infrastructure changes; the PR body carries `Ref #11181` only — never `Closes`/`Fixes` — because epic #11181 stays open for residual operator-class items.

## Research Insights

### Premise Validation (Phase 0.6)

- **Epic #11181**: `gh issue view 11181 --json state,title,closedByPullRequestsReferences` → `OPEN`, "Epic: ADR-068 Phase-3 GA blockers (multi-host /workspaces) — non-cutover track", closed by no PR. Premise holds: the epic stays open; the PR body must reference, not close.
- **Source file**: `/tmp/opencode/delegated-act-11181-ac2-envelope.md` exists (36 lines) and matches the ADR-289 Production Envelope shape (delegation URL, `Epic: #11181`, Scope item, fenced Command block, blast radius, gates, verification, abort, rollback, stop conditions).
- **Destination**: `knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md` is ABSENT on both `origin/main` and this worktree — the shape is *build* (one new file), not *modify*. No `soleur-delegated-act` receipt comment on #11181 pins a different `envelope=<path>` value, so the stated destination is free.
- **Delegation**: comment 6417763814 on #11181 exists, authored 2026-10-26T13:55:06Z by a `User` (not a bot) — consistent with the envelope's recorded creation time.
- **Executed act**: `apply-web-platform-infra.yml` `workflow_dispatch` runs around the act all conclude `success` (e.g. run 40412555839 at 2026-10-26T22:27Z, 40486279399 at 2026-10-27T10:09Z). Today's failing runs are `push`-triggered CI legs on other branches, not the dispatched apply.
- **Collision pre-check**: `collision-precheck.sh 11181` exited 10 naming open PR #11348 — that is *this branch's own* WIP draft PR (`WIP: feat-one-shot-11181-ac2-envelope-runbook`), not a foreign duplicate. Foreign `test-all.sh` process rows belong to the unrelated worktree `feat-one-shot-web1-pg-deferral-repark` and do not touch this PR's file set (no test files change here).
- **Repo visibility**: `jikig-ai/soleur` is PUBLIC. See Decision: byte-identical commit, below.

### Property List (Phase 0.6b restatement)

1. The envelope's bytes are readable from git at the committed path so `delegation-verify.sh` (ADR-289 V4: `GIT_LITERAL_PATHSPECS=1 git show HEAD:<path>`) and any future receipt audit can resolve `envelope=<path>`; a scratch-only copy is lost on machine restart and unverifiable.
2. Epic #11181 remains open after this PR merges (PR body `Ref #11181`, never `Closes`/`Fixes`).
3. Exactly one committed copy exists at the intended KB destination; no collateral files change.

### Cut List (Phase 0.6b)

- Mechanisms proposed by the ask: the file copy and the KB-only PR. Property 1 is bought by `git add` + commit of the file as-is — covered by existing git machinery; no new script, gate, index entry, or CI change is needed. Checked: the runbooks directory has no README/index/manifest enumerating its files, and no test or workflow enumerates that directory's contents. Nothing further cut.

### Decision: commit byte-identical, not redacted (technical ruling)

The source file names RFC1918 peer IPs (`10.0.1.10/.11`), Doppler secret *names* (no values), and host names, and the repo is public. Redaction considered and rejected: ADR-289 receipts pin `sha256=<verified-envelope-sha256>` against the git bytes, so any edit makes the committed envelope permanently mismatch the fingerprint a future receipt records, defeating the audit purpose that motivates the commit. The content discloses nothing not already public in this repo's committed runbooks (e.g. `runbooks/ci-ssh-token-replace.md` names Doppler secret names and the Access endpoint; `runbooks/delegated-merge-*-envelope.md` publish the same envelope shape): private-range IPs are unreachable from the internet, secret values are absent, and the delegation comment the file links is itself public. Ruling is `technical`, class-persisted in decision-challenges.md.

### Repository patterns (local research — sequential-fallback inline; see note)

- Precedents: `knowledge-base/engineering/operations/runbooks/delegated-merge-10663-envelope.md` and `delegated-merge-10789-envelope.md` — committed envelope runbooks, plain markdown, no YAML frontmatter, heading `# Delegated merge of change <N> (epic <M>)` then `## Production Envelope - <label>`. The new file follows the same body shape already (its H1 is `# Delegated act — ADR-068 AC 2 ...`); copy as-is, no restyling.
- Mechanism authority: `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` — Decision (Option H), V4 (envelope read from git), receipts. The CTO agent's delegated-act receipt duty: `plugins/soleur/agents/engineering/cto.md` §6 (`<!-- soleur-delegated-act v1 ... envelope=<path> sha256=... -->`).
- Plan frontmatter convention (recent plans, `grep '^type:' knowledge-base/project/plans/*.md`): `chore`, `feat`, `fix` in use; `docs:` prefix appears in the skill's own commit-message example (`docs: create plan and tasks for <BR>`); this plan uses `type: chore` with a `docs:` title prefix — chore is the closest existing enum member for a KB-only archival commit.

### Institutional learnings

- `knowledge-base/project/learnings/2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md` — acceptance criteria assert the invariant, not a proxy: the ACs below compare the committed bytes against the source (`cmp`), not merely that the file exists.
- No learning matches this task's shape more closely than the above; the grep over `knowledge-base/project/learnings/` for envelope/delegation surfaced no gotcha about committing envelope runbooks.

### Related issues / PRs

- Epic #11181 (open, referenced — never closed here); PR #11210 (merged precondition, per-host SOLEUR_PROXY_BIND injection); PR #11348 (this branch's own WIP draft).

### Conventions (CLAUDE.md → AGENTS.md)

- `hr-never-run-commands-with-unbounded-output` respected (all gh queries bounded with `--limit`/`head`). KB dirs sanctioned; runbooks path already exists. Version files untouched (KB-only PR; CI semver label at ship).

### External research

Skipped (Phase 1.6: strong local context, docs-only archival commit; no security/payments/API surface beyond the redaction question resolved above from ADR-289 itself).

### Research execution note

This planning run executes inside a Task subagent (no `subagent`/`Task` tool in this harness session; nesting depth is one). The Phase 1 fan-out roles (repo-research-analyst, learnings-researcher, functional-discovery, SpecFlow) were executed inline sequentially in this process: directory/functionality greps, ADR and precedent reads, gh evidence checks above. Disclosure: `Reviewed-Coverage: sequential-fallback` — no independent sub-review ran.

### Deepen-pass findings (2026-10-27)

- Precondition citation verified live (quality-check: no memory-cited numbers): `gh pr view 11210 --json state,title,mergedAt` → `MERGED`, "feat(infra): per-host SOLEUR_PROXY_BIND injection for owner-side relay (ADR-068 item 2)", `mergedAt` 2026-10-26T15:56:37Z — byte-equal to the envelope's recorded confirmation time, and the title independently confirms the envelope's owner-side relay scope. #11348 confirmed as this branch's own WIP PR.
- Verify-the-negative pass (deepen 4.45): the plan's negative claims were each measured — "no credential values" (AC-2 grep on real bytes: zero matches, planted control fires), "the delegation comment is already public" (read via `gh api` this session), "the destination is unclaimed" (no `soleur-delegated-act` receipt on #11181 as of 2026-10-27). Post-edit self-audit: no dropped or renamed symbols across rounds.
- Conditional-gate dispositions: 4.5 network-outage scan matched twice, both on the phrase "unreachable from the internet" (a privacy claim about RFC1918 space), not a connectivity symptom — checklist does not fire; `## Hypotheses` not required. 4.55 downtime/cutover: no trigger (the PR runs no apply; the envelope's `gh workflow run` line is historical record, dormant by construction — this change adds only a markdown file). 4.10 encryption posture, 4.11 guard contract, 4.13 task design: no trigger (no store, no guard, no autonomous-task surface in Files lists). 4.9 UI-wireframe: no UI-surface file.
- Halt gates passed: 4.6 User-Brand Impact present with valid `none` threshold and no sensitive-path diff; 4.7 pure-docs skip (all paths `^knowledge-base/`); 4.8 PAT-shaped grep: no hits; 4.12 Scope Check: one unfenced section, three subsections, every ask mapped, both `inferred` rows carry dependency-naming justifications, no `status: BLOCKED` marker.
- Skill/agent discovery (deepen phases 2/5): the OpenCode harness advertises the bare-id Soleur skill tree; no project-local or third-party plugin skill bears on a KB archival commit (checked `plugins/soleur/skills/` routing descriptions: `archive-kb` post-dates this work — it archives *completed* artifacts after merge, not applicable pre-merge). Review agents undiscoverable-spawn (no `Agent` tool); their lenses ran inline as disclosed above.
- Rule-ID citation census (deepen quality check): the plan cites one rule id, `hr-never-run-commands-with-unbounded-output` — confirmed active at `AGENTS.md:28`. No fabricated or retired ids.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` bodies contain no mention of `knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md` and no mention of `11181`. Check ran against the final Files list (one created file; zero edited files).

## Files to Create

- `knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md` — byte-identical copy of `/tmp/opencode/delegated-act-11181-ac2-envelope.md` (2501 bytes, sha256 `ffa9cbe118ac875635f5ae051682c418f678f069b22a9d546e2e9c901d038b5f`, captured 2026-10-27). Copy via `cp`; no edit of a single byte, including line endings.

## Files to Edit

None. (Planning artifacts — this plan file and `knowledge-base/project/specs/feat-one-shot-11181-ac2-envelope-runbook/{tasks.md,decision-challenges.md}` — are written by the pipeline itself and ride in the same branch; they are not product diff.)

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user-visible artifact. The "user" here is the founder-operator and any later audit session: a wrong-path, altered-bytes, or uncommitted envelope means `delegation-verify.sh` cannot resolve `envelope=<path>` from git (ADR-289 V4), so the AC2 act becomes permanently unverifiable and the only copy is one machine restart from loss.
- **If this leaks, the user's workflow is exposed via:** committing the envelope into a PUBLIC repo — the file names RFC1918 peer IPs, Doppler secret names, and internal host topology. Verified non-exposing: no secret *values* are present (names only), the IPs are private-range and unreachable from the internet, the delegation comment linked is already public, and committed repo siblings (`runbooks/ci-ssh-token-replace.md`) publish the same class of detail.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches no path matching the preflight sensitive-path regex and ships no user-facing or production-mutating artifact — a documentation archival whose worst failure is a lost audit trail, not a degraded experience.

## Implementation Phases

### Phase 1 — Archive the envelope (single commit)

1. `cp /tmp/opencode/delegated-act-11181-ac2-envelope.md knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md`
2. Verify bytes before committing: `sha256sum` of the new file equals the anchor above.
3. PR body: one-line summary, the literal reference line `Ref #11181`, no `Closes`/`Fixes`/`Close` footer tokens — and the body must NOT spell a forbidden token adjacent to `#11181` even in prose (write "epic stays open for residual operator-class items", never "never Closes #11181"): the AC-3 absence-grep would false-fail on the prohibition sentence itself (absence-grep self-reference trap, plan sharp edges).

### Verification already run at plan time (every prescribed command executed once)

- `grep -cE 'sdu_[A-Za-z0-9]+|dop_(pat|oi|st)_[A-Za-z0-9]+|gh(p|o|u)_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|-----BEGIN'` against the actual source bytes: `0`, rc 1 — AC-2 holds pre-commit; a planted `sdu_` control line proves the pattern can fire.
- `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` on the branch: rc 1 (empty) — AC-4 form verified, triple-dot so a sibling merge cannot redden it.
- `git ls-files knowledge-base | grep delegated-act-11181`: rc 1 pre-commit — AC-5 form verified; expect exactly 1 line after this PR's commit.
- AC-3 body greps probed against a compliant sample body (absence check rc 1, `Ref #11181` present rc 0) and against the trap body ("Never write Closes #11181…"), which the absence check matched — motivating the prose rule in step 3.
- All `knowledge-base/**.md` citations in this plan glob-resolve (the sole unresolved one is the destination file itself, which this plan creates).

> **Addendum — 2026-10-27 (review fix round, F1/F4, CTO-ruled):** the three bullets above are plan-time snapshots recording pre-amendment predicates; at ship-time verification the amended forms govern — AC-4 = `grep -vE '^knowledge-base/|^\.markdownlintignore$'` exiting 1 (one exemption line added, precedent #9757/#10789), AC-5 = the copy-census form (two name-matching paths, one `cmp` match). The bullets also record the class the plan missed: no probe asked whether the byte-frozen runbook passes the required repo-sweep `markdown-lint` job (it yields MD034:5, MD032:18, MD032:27), which the sibling archives carried `.markdownlintignore` exemptions for. Durable prevention lands as an addendum to the existing 2026-10-22 learning (compound step, ruling F2).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Commit the AC2 delegation-envelope runbook into the knowledge base" | Files to Create / Phase 1 | mapped |
| 2 | "the only copy of the executed-act envelope for epic #11181 AC2 (owner-side relay activation) exists at /tmp/opencode/delegated-act-11181-ac2-envelope.md" | Files to Create (byte-identical anchor) | mapped |
| 3 | "its intended destination is knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md" | Files to Create | mapped |
| 4 | "KB-only documentation PR; no code or infra changes" | AC-4 (diff-scope) | mapped |
| 5 | "PR body carries \"Ref #11181\" only (never Closes/Fixes — epic #11181 stays open for residual operator-class items)" | AC-3 | mapped |
| 6 | "Plan detail level: MINIMAL" | this template choice | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `runbooks/delegated-act-11181-ac2-envelope.md` (create) | "its intended destination is knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md" | asked |
| Phase 1 step 2 sha256 check | — | inferred — justification: the AC2 envelope's auditability rests on the committed bytes matching what the verifier fingerprinted (`verified-envelope-sha256` in the receipt line, cto.md §6); a silent byte drift makes every future receipt fail `receipt-mismatch`, and per learning `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy` the check must assert content, not existence. |
| AC-2 secret-value absence scan | — | inferred — justification: the repo is public and the ask is a commit to the knowledge base; an irreversible history rewrite would be the only remedy for a committed value, so the cheap negative scan is a safety dependency of "commit into the knowledge base," not new scope. |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base/`
- Planned files: 1 (product diff) | Estimated changed lines: 36
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Operations

Assessment ran inline (sequential-fallback — see Research Insights; no domain-leader spawn available in this subagent). Other seven domains: none. Engineering (no architectural decision — ADR-289/ADR-068 decisions are recorded, not made here), Product (no user-facing surface; mechanical UI-surface override does not fire — no UI path in Files lists), Legal (no legal document, no regulated data; the public-disclosure question is resolved as technical above), Marketing/Sales/Finance/Support (no content, pipeline, budget, or customer-support surface).

### Operations

**Status:** reviewed
**Assessment:** the commit places an operational runbook in the sanctioned ops-runbook shelf beside two `delegated-merge-*-envelope.md` precedents; it records an already-executed, already-green act and prescribes no new provisioning, vendor, or expense. The one operational dependency it satisfies is ADR-289 V4: envelopes must be readable from git for later verification. No cost or vendor implications; no new process — this is the recording end of the standing-delegation process, not the enacting end.

## Acceptance Criteria

- [x] AC-1 — Byte-identical archival: `git show HEAD:knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md | sha256sum` equals `ffa9cbe118ac875635f5ae051682c418f678f069b22a9d546e2e9c901d038b5f` on the PR head.
- [x] AC-2 — No credential values in the added file: `git show HEAD:knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md | grep -cE 'sdu_[A-Za-z0-9]+|dop_(pat|oi|st)_[A-Za-z0-9]+|gh(p|o|u)_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|-----BEGIN'` exits 1 (zero matching lines).
- [ ] AC-3 — Epic stays open: the PR body contains the literal text `Ref #11181` and no case-insensitive `closes #11181` / `fixes #11181` / `close #11181` token; after merge, `gh issue view 11181 --json state -q .state` returns `OPEN`.
- [x] AC-4 — KB-only diff. Amended at work-time (explicit, per verify-by-literal-command discipline; review finding F1, CTO-ruled 2026-10-27): `git diff --name-only origin/main...HEAD` lists only paths under `knowledge-base/` **plus the single `.markdownlintignore` exemption line** — the exemption is forced by the required repo-sweep `markdown-lint` CI job against a byte-pinned file (fixing in place is forbidden by ruling T1 / ADR-289 V4) and is precedented by the #9757 block and the 10789 same-PR exemption (Phase 2 of its plan). AC-4's intent (no code or infra change) survives; the verification command becomes `git diff --name-only origin/main...HEAD | grep -vE '^knowledge-base/|^\.markdownlintignore$'` exiting 1 (empty).
- [x] AC-5 — Destination exactness: the file exists at `knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md` and is the tree's only committed copy. Amended at work-time (explicit, per verify-by-literal-command discipline): the plan-time form `git ls-files knowledge-base | grep delegated-act-11181` measured 1 line only because this plan was still untracked then; after the plan commit it also matches this plan's filename. Fixed predicate: `git ls-files | grep delegated-act-11181` names exactly two paths, of which exactly one `cmp`-matches the source bytes (the runbook); the other is this branch's planning artifact, not a copy of the envelope. Measured 2026-10-27: `ENVELOPE-COPY` count = 1.

## Test Scenarios

- Given the source scratch file on disk, when `cp` lands it at the destination, then AC-1's `sha256sum` over `git show HEAD:<path>` prints the anchor hash (`integration`: deterministic command above).
- Given a reviewer suggests "tidying" the envelope markdown (frontmatter, heading normalization), when the diff is checked, then AC-1 fails on any byte change — the precedent files carry no frontmatter and the receipt fingerprints bytes, so formatting edits are out of scope by construction (`unit`-equivalent: the cmp check itself). `integration`.
- Given the PR body drafted per Phase 1 step 3, when `gh pr view <N> --json body -q .body | grep -icE 'clos(es|e) #11181|fixes #11181'` runs, then it exits 1, and the same pipe with `grep -c 'Ref #11181'` exits 0 (`integration`).
- Given the branch, when `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` runs, then it prints nothing and exits 1 (`integration`).

No e2e scenario: nothing renders or executes. No new pyramid markers needed.

## Context

- Destination path and the `Ref`-not-`Closes` posture come verbatim from the tasking; both were verified consistent with repo reality (see Premise Validation).
- Adjacent state, deliberately not this PR's deliverable: no `<!-- soleur-delegated-act v1 ... -->` receipt comment was found on #11181 as of 2026-10-27. The receipt duty belongs to the session that performed the act (cto.md §6), not to this archival PR; its absence is recorded here so the epic owner can reconcile rather than so this branch silently expands scope.
- The envelope's own `Command:` block (`gh workflow run apply-web-platform-infra.yml -f host_proxy_tls_enabled=true`) is historical record; nothing in this plan dispatches it.
- Lane default note: Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## References

- Epic (referenced, never closed here): #11181 — "Epic: ADR-068 Phase-3 GA blockers (multi-host /workspaces) — non-cutover track"
- Mechanism: [ADR-289-standing-delegation-and-production-envelope.md](../../engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md) (Decision Option H; V4 git-read; receipts)
- Precedents: `knowledge-base/engineering/operations/runbooks/delegated-merge-10663-envelope.md`, `delegated-merge-10789-envelope.md`
- Receipt contract: `plugins/soleur/agents/engineering/cto.md` §6; `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` §8
