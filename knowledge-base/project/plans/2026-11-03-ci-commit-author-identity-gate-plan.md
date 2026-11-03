---
title: "ci: gate commit-author identity before gh pr ready — wrong -c user.email authors sail to cla-check"
date: 2026-11-03
slug: ci-commit-author-identity-gate
branch: feat-one-shot-12027-commit-author-identity-gate
issue: 12027
type: fix
closes: [12027, 7218]
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Extend `.claude/hooks/cla-signed-author-gate.sh` so the `gh pr ready`/`gh pr merge` deny covers every non-sanctioned author/committer email on `origin/main..HEAD` — not just the literal `noreply@anthropic.com` — while preserving the sanctioned carve-outs (the session's configured `user.email` and CLA-allowlisted / signed identities resolvable offline). Widen the companion rule/doc text to match and extend the hook's fixture suite. Closes #12027 and, by generalizing the hardcoded-email gap it names, #7218.

## Research Insights

### Premise Validation (Phase 0.6)

- **#12027 OPEN, #7218 OPEN** — verified via `gh issue view`. Neither is closed by an existing PR; the premise is live.
- **PR #12002 is OPEN** (not merged) — the incident branch exists; 6 commits authored `jean@jikig.ai` on a repo whose config supplies `jean.deruelle@jikigai.com`. Premise holds.
- **Collision precheck (`collision-precheck.sh 12027` / `7218`):** the only PR naming #12027 is **PR #12029 — this pipeline's own draft** (head `feat-one-shot-12027-commit-author-identity-gate`, this worktree's branch). Not a foreign duplicate. Foreign `test-all.sh` pids belong to `.worktrees/feat-one-shot-cto-class-r-read-only-ownership` — unrelated issue, no action.
- **Cited files all exist on `origin/main`:** `.claude/hooks/cla-signed-author-gate.sh`, `.devin/config.json` (binds the hook for `exec` at line 56), `.claude/settings.json` (binds it at line 159), `.github/workflows/cla.yml`, `cla-signed-author-gate.test.sh`, `devin-dispositions.tsv` (row 42). `scripts/precommit-guard.sh` named in the issue is the **plugin** script (exists at plugin root, `plugins/soleur/scripts/precommit-guard.sh` in-repo) — it restores the commit-on-main check in cloud, unrelated to author identity.
- **ADR corpus sweep** (`contributor-license|cla-assistant|corporate-cla|cla-signatures|contributor-assistant`): ADR-201 is the governing record — the CLA roster is `apps/cla-evidence/roster/ccla-roster.json`, the allowlist in `cla.yml` is untouched, and **a third required status check is an explicitly rejected alternative** (six-artifact lockstep + #6049 auto-fabrication ceiling). This plan adds no CI check; it extends an existing local gate — consistent with the ADR.
- **Premise deviation (measured, load-bearing):** the issue/pipeline brief calls `devin-ai-integration[bot]` a *sanctioned* override. Measured twice that it is **not**: learning `knowledge-base/project/learnings/integration-issues/2026-10-30-npm-e404-is-authz-masking-and-devin-commits-break-cla-check.md` (7/13 branch commits authored by the bot → permanent red `cla-check`; the bot is neither allowlisted nor able to sign) and live evidence — PR #11690 (`feat-one-shot-11687-main-ci-red`, devin-bot commits) shows `cla-check: fail`. `devin-ai-integration[bot]` must be **excluded** from the sanctioned set; the carve-out that exists is for CLA-**allowlisted** identities. Recorded as a `pending — assumed` technical row in `decision-challenges.md`.
- **`wg-cla-signed-author-before-merge` already claims the broad property** (`AGENTS.rules.md` line ~78: "every branch commit … MUST be authored AND committed by a CLA-signed identity") while the hook enforces one literal — the rule text is the target state; the mechanism is what lags.

### Mechanism Minimality (Phase 0.6b)

**Property List:**

- P1 — At `gh pr ready`/`gh pr merge`, deny when any unique author or committer email on `origin/main..HEAD` is not a sanctioned identity (the class, not one literal).
- P2 — Sanctioned set is derived offline from authoritative repo artifacts: session `git config user.email`, `<id>+<login>@users.noreply.github.com` whose login is in `cla.yml`'s `allowlist:` or `origin/cla-signatures:signatures/cla.json` `signedContributors[].name`, plus the pinned CLA-allowlisted human email for the sanctioned `-c` override path on unset-config sessions.
- P3 — The deny message names the offending emails/commits and the `filter-branch --env-filter` rewrite + `--force-with-lease` recovery (existing affordance, generalized).
- P4 — Guidance states "never pass `-c user.*` when git config already supplies identity" in the rule corpus and the `-c user.*` authority docs.

**Cut List (mechanism → property → what already covers it):**

- A third required CI status check → server-side coverage of web-UI/bot merges → **rejected by ADR-201** (six-artifact lockstep); cut, not designed.
- Enforcement inside `precommit-guard.sh` (issue's suggested site a) → same property P1 → the existing `cla-signed-author-gate.sh` is the already-bound chokepoint at the exact boundary (`gh pr ready`/`merge`) in both harnesses; extending it is strictly cheaper and covers #7218's named file.
- A ship-phase prose check (issue's alternate site) → same property P1 → prose self-attestation is invisible to a boolean gate (repo doctrine); the PreToolUse hook is the deterministic enforcement.
- Optional per-commit warning hook (issue's candidate c) → property "earlier-than-ready feedback" → cut: a new firing surface and latency on every `git commit` for marginal gain; the ready-gate deny already names the fix. Recorded as Non-Goal with a tracked follow-up.

### Repo Findings

- **The authoritative identity map is login-keyed, and email→login is only resolvable offline via GitHub's noreply convention.** `cla.yml:62` `allowlist: "dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot],soleur-ai[bot],soleur-infra[bot]"`; `origin/cla-signatures:signatures/cla.json` holds `deruelle` (id 54279) and `Elvalio` (id 92384917). A commit email `<DB-ID>+<login>@users.noreply.github.com` resolves to that login via GraphQL `commit.author.user.login`; a non-noreply email resolves only if registered on an account — unverifiable offline.
- **Upstream hardcode:** contributor-assistant drops `databaseId === 41898282` (`github-actions[bot]`) before the allowlist filter (`learning 2026-06-03`), so `41898282+github-actions[bot]@users.noreply.github.com` is sanctioned by mechanism regardless.
- **`pull_request_target` reads `cla.yml` from `main`** — an in-PR allowlist edit cannot self-heal; authorship on the branch is the only lever (learning 2026-10-30).
- **Sanctioned noreply emails observed in-tree:** `273333864+soleur-ai[bot]` (pinned in `fix-issue/SKILL.md:175`), `335404629+soleur-infra[bot]` (pinned in `.github/scripts/bump-inngest-bootstrap-pin.sh:132`), `41898282+github-actions[bot]`, `49699333+dependabot[bot]` (git history).
- **The `-c user.*` guidance lives at `plugins/soleur/skills/git-worktree/SKILL.md:461`** (the `hr-never-fake-git-author` bullet — retired id, body migrated to git-worktree §Sharp Edges per `scripts/retired-rule-ids.txt`; still the canonical `-c user.*` authority) — currently scoped to `<fake>` emails only; the `jean@jikig.ai` incident was a *real but wrong* email, outside that text.
- **`plugins/soleur/devin/INSTRUCTIONS.md:327`** already prescribes authoring as the CLA-allowlisted identity via `-c` overrides — accurate but silent on "do not override when config already supplies identity" (the exact #12027 failure).
- **Worktree identity machinery exists:** `worktree-manager.sh` `ensure_worktree_identity` (~line 1294) pins worktree local config from `--global` — covers config drift at creation, NOT per-commit `-c` overrides.
- **Hook wiring:** `emit_incident` + `hook_parse_input` + `soleur_ctx_sanitize_lines` pattern per the existing file; the suite `cla-signed-author-gate.test.sh` uses mktemp fixture repos and is auto-registered by `scripts/test-all.sh` glob `.claude/hooks/*.test.sh` — no manifest edit needed.
- **Test conventions:** `assert_fixture_dir` copy pinned byte-equal to `plugins/soleur/test/test-helpers.sh` (`fixture-dir-operand-assert.test.sh`); suite prints `<pass>/<total> passed`, exits 1 on any FAIL.

### Institutional Learnings Applied

- `2026-10-30-npm-e404-...-devin-commits-break-cla-check.md` — devin bot is not CLA-sanctioned; `pull_request_target` runs `cla.yml` from main.
- `2026-06-03-cla-fails-on-bot-commit-authored-by-loginless-identity.md` — null-login mechanism; github-actions[bot] hardcode-drop.
- `2026-04-24-fake-git-author-bare-repo-bot-override.md` — bare-repo config poisoning; `ensure_worktree_identity` precedent.
- `2026-06-04-subagent-commits-fail-cla-check.md` (PR #4948) — origin of the existing hook and its `filter-branch` remedy text.
- `2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md` — login-vs-email surface divergence precedent.

### Open Code-Review Overlap (Phase 1.7.5)

96 open `code-review` issues queried. Matches against the planned file list:

- `#7218` (names `.claude/hooks/cla-signed-author-gate.sh`) — **Fold in.** The subset-check this plan ships is the exact inversion #7218 prescribes; PR body carries `Closes #7218` alongside `Closes #12027`.
- All other files: no matches.

### Research Decision (Phase 1.6)

External research skipped — the mechanism is fully settled by repo sources (ADR-201, cla.yml, two measured incidents) and external perspective adds nothing to a repo-internal gate.

### Community / Functional Overlap (Phases 1.5, 1.5b)

No uncovered stacks (bash/CI tooling). Functional-overlap check ran inline (no `run_subagent` in this session — `sequential-fallback` disclosed): no community artifact covers a repo-internal PreToolUse CLA gate; nothing installed.

### Skill Description Budget (Phase 1.8)

No `description:` frontmatter edit to any `plugins/soleur/skills/*/SKILL.md` is planned (edits are body prose only) — check skipped per trigger.

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** Observability (discoverability probe corrected off the suite-shaped reject), Research Insights (retired-rule-id citations corrected), Precedent-diff note added.
**Research agents used:** sequential inline (`sequential-fallback` — no `run_subagent` in this session): repo research, learnings research, functional-overlap, spec-flow edge-case pass, plan-review panel lenses (DHH/Kieran/code-simplicity + standing checks), CTO domain consult.

### Key Improvements
1. Sanctioned-set derivation is offline and base-ref-pinned (`origin/main` cla.yml + `origin/cla-signatures` cla.json) — mirrors what `cla-check` accepts without a network dependency on the ready boundary.
2. `devin-ai-integration[bot]` corrected from "sanctioned" to DENIED on measured evidence (PR #11690 `cla-check: fail`; learning 2026-10-30).
3. Guard Contract with an 8-row design-derived mutation matrix (own-dispatch vacuity, second-member, committer-only, order-of-checks, harness mutation, two must-PASS discriminators).

### New Considerations Discovered
- `hr-never-fake-git-author` is a RETIRED rule id (`scripts/retired-rule-ids.txt:67`); its body lives in `git-worktree/SKILL.md` §Sharp Edges — the edit target is the bullet, not a corpus rule.
- The `discoverability_test.command` must be a single allowlisted verb with no shell metachars and under 15 s — the suite itself is rejected as the probe; `grep SANCTIONED` on the hook substitutes.
- `wg-cla-signed-author-before-merge` rule line is 538/600 bytes and `B_ALWAYS=44390/46000` — the widening is byte-constrained (recorded in Phase 3).

### Precedent-diff note (Phase 4.4)
The extension follows the hook's own precedent: the `noreply@anthropic.com` deny block (emit_incident + jq deny payload + `exit 0`), `hook_parse_input`/`soleur_ctx_sanitize_lines` libs, and the sibling-hook chain-boundary trigger grep (`ship-unpushed-commits-gate.sh`, `pre-merge-rebase.sh`). Fixture conventions copied from `cla-signed-author-gate.test.sh`/`ship-unpushed-commits-gate.test.sh` (mktemp repos + `assert_fixture_dir` copy pinned to `plugins/soleur/test/test-helpers.sh`). No novel pattern introduced.

## Problem Statement / Motivation

The `gh pr ready`/`gh pr merge` PreToolUse gate `.claude/hooks/cla-signed-author-gate.sh` denies only the literal `noreply@anthropic.com` author/committer. Every other non-CLA-signed identity sails through and burns a full CI cycle: `cla-check` resolves `commit.author.user.login` via GraphQL, an unregistered email resolves to a null login, and the required check fails — recovery is `git filter-branch --env-filter` + `--force-with-lease` plus a ~1h pipeline cycle. Two measured instances:

- **#12027 / PR #12002:** 6 commits authored `jean@jikig.ai` — an agent-passed `-c user.email` override on a repo whose git config already supplied the signed `jean.deruelle@jikigai.com` identity.
- **#7218 / PR #7169:** 8 commits authored `ops@jikigai.com` — a real-but-unsigned identity the gate could not see.

Root cause is two missing layers: (1) nothing local verifies commit authors against the sanctioned-identity set before ready/merge; (2) skill/rule guidance does not state "never pass `-c user.*` when git config already supplies identity".

## Proposed Solution

Invert the gate from a denylist-of-one to a **sanctioned-set subset check** (the direction #7218 prescribes). After the existing `noreply@anthropic.com` deny (kept first — its specialized message names the modal subagent-commit case and its tests pin it), a second stage collects the unique `%ae` ∪ `%ce` set on `origin/main..HEAD` and denies `gh pr ready`/`gh pr merge` when any member is not sanctioned.

**Sanctioned email set** (each source independently optional; all-empty → fail-open, matching the hook's posture):

1. `git -C "$WORK_DIR" config --get user.email` — the session's configured identity (merged local+global+system).
2. **Pinned CLA-allowlisted human emails** — a small `SANCTIONED_EMAILS` constant carrying `jean.deruelle@jikigai.com`, provenance-commented to `devin/INSTRUCTIONS.md` §Devin-specific considerations (the sanctioned `-c` override path for unset-config sessions; a non-noreply signed email is unresolvable to a login offline, so it must be pinned).
3. **Noreply-convention logins** — an email matching `^[0-9]+\+<login>@users\.noreply\.github\.com$` whose `<login>` appears in EITHER:
   - the `allowlist:` line of `.github/workflows/cla.yml` **read at `origin/main`** (`git show origin/main:.github/workflows/cla.yml` — the same ref `pull_request_target` executes, per ADR-201's base-ref invariant; a PR-head allowlist edit cannot self-authorize the gate), OR
   - `signedContributors[].name` in `git show origin/cla-signatures:signatures/cla.json` (jq is already a hook dependency).

This covers `soleur-ai[bot]`/`soleur-infra[bot]`/`github-actions[bot]`/`dependabot[bot]`/`renovate[bot]`/`claude[bot]` noreply emails (allowlisted logins) and signed contributors using GitHub noreply emails (`Elvalio`) — **and it correctly DENIES `158243242+devin-ai-integration[bot]@users.noreply.github.com`**, which is in neither roster (measured fail, PR #11690 / learning 2026-10-30).

The deny message lists the offending emails with sample commits, names the sanctioned sources, and generalizes the existing `filter-branch --env-filter` + `--force-with-lease` remedy to the offender emails.

## Technical Considerations

- **Known false-positive bound (accepted):** a signed contributor's *non-noreply* email (e.g. `Elvalio`'s real address on a shared branch) cannot be resolved to a login offline → deny. Fail-closed is the safe direction for a CLA gate; the deny message documents the sanctioned-set sources so the operator sees why.
- **`%ce` (committer) is checked alongside `%ae`** — the rule (`wg-cla-signed-author-before-merge`) says "authored AND committed"; a rewrite that fixes only the author leaves the committer unsigned.
- **Merge commits on the branch** are commits too — they flow through the same check (their authors are typically the operator or `github-actions[bot]`, both sanctioned).
- **Read sources at base refs, not PR head** — `origin/main` for cla.yml, `origin/cla-signatures` for cla.json. Both refs already gate the hook's early exits (`origin/main` is required; `cla-signatures` absence degrades only that component).
- **No new required check, no allowlist/roster edit, no new workflow** — consistent with ADR-201 (roster untouched, no third required check, additive evidence never gates).
- **`hr-never-fake-git-author` bullet widening** (`git-worktree/SKILL.md` §Sharp Edges, line ~461 — retired id, migrated body): the incident email was real-but-wrong, so the text widens from "`<fake>`" to "any `-c user.*` override when config already supplies identity, or any identity outside the sanctioned set".
- **Hook style:** `[[ ]]`, `local`, stderr diagnostics, deny payload via `jq -n`, `soleur_ctx_sanitize_lines` on commit-subject text, no `^`-anchored guardrail greps — per constitution and sibling hooks.

### SpecFlow edge cases (Phase 3, executed inline — sequential-fallback)

Every branch of the sanctioned-set evaluation must terminate in `exit 0` — the hook's contract is JSON-deny-or-pass, never a non-zero exit:

- `cla.yml` carries the word "allowlist" in its comment block (lines ~12–14, ~51–61) besides the real `allowlist:` key — the parse must anchor `^[[:space:]]+allowlist:[[:space:]]*"` and stop at the first match.
- `git show origin/cla-signatures:signatures/cla.json` fails hard when the ref is absent (partial clone) — every `git show`/`git config` read needs `|| true`-class guarding inside the builder; under `set -eo pipefail` a bare `$()` abort kills the hook before the deny JSON emits.
- `signedContributors` schema drift → parse with `.signedContributors[]?.name // empty` (jq `// empty` convention, not bare `.[0]`).
- Noreply login extraction is `+`→`@` substring surgery with literal string equality (no regex on the login — GitHub logins are `[a-z0-9-]+`/`[bot]`-suffixed, but treating the extracted token as a literal kills metacharacter edge cases by construction).
- Comparison is case-exact email equality; `git config user.email` whitespace/CR needs trimming.
- An empty `OFFENDERS` result must be distinguishable from an unevaluable run: offenders-empty → pass; all-sources-empty → pass; per-source failure → that component contributes nothing (never a global abort).

## Implementation Phases

### Phase 1: Hook extension (`.claude/hooks/cla-signed-author-gate.sh`)

- Add a sanctioned-set builder (config email + `SANCTIONED_EMAILS` constant + noreply-login resolvers against `git show origin/main:.github/workflows/cla.yml` allowlist and `git show origin/cla-signatures:signatures/cla.json`).
- Add the subset-check stage after the existing noreply deny: enumerate unique `%ae`/`%ce` on `origin/main..HEAD`, partition into sanctioned/offenders, deny with offender list + generalized filter-branch fix on any offender.
- All-sources-empty → `exit 0` (fail-open). Individual source failures degrade that component only.

### Phase 2: Fixture-suite arms (`.claude/hooks/cla-signed-author-gate.test.sh`)

New arms per the Guard Contract mutation matrix: wrong-identity `-c` email denies; allowlisted-bot noreply passes; signed-login noreply passes; devin-bot noreply denies; committer-only offender denies; mixed authors denies; unset-config + pinned human email passes; all-sources-absent fail-opens; and the harness self-test (assert_deny instrument actually parses the deny payload).

### Phase 3: Guidance convergence

- `AGENTS.rules.md` — widen `wg-cla-signed-author-before-merge` body: name the sanctioned set and add the "never `-c user.*` when config already supplies identity" clause. **Byte-cap constraint:** the rule line is 538/600 bytes and `B_ALWAYS=44390` against the 46000 ratchet (`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`) — the widening must re-verify the rule line stays < 600 bytes and the corpus under cap; if the clause cannot fit, move the detail into the hook's header comment and keep the rule line pointing at the sanctioned-set semantics only.
- `plugins/soleur/skills/git-worktree/SKILL.md` — widen the `hr-never-fake-git-author` Sharp-Edges bullet (line ~461; retired id, migrated body — edit the bullet text, not a rule id).
- `plugins/soleur/devin/INSTRUCTIONS.md` — extend the §Devin-specific "Commit author identity" bullet: prefer configured identity; `-c` only when config is unset and only with an allowlisted email.
- `plugins/soleur/skills/work/SKILL.md` — one line at the incremental-commit guidance (author identity comes from git config; never `-c user.*` to override a configured identity).
- `plugins/soleur/skills/ship/SKILL.md` — one line in the `gh pr ready`-boundary gate cluster (after the recurring-vendor-expense block) naming the author-identity gate's subset semantics.

## Files to Edit

- `.claude/hooks/cla-signed-author-gate.sh`
- `.claude/hooks/cla-signed-author-gate.test.sh`
- `AGENTS.rules.md`
- `plugins/soleur/skills/git-worktree/SKILL.md`
- `plugins/soleur/devin/INSTRUCTIONS.md`
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/skills/ship/SKILL.md`

## Files to Create

- None (the deliverable extends an existing guard; `knowledge-base/project/specs/<branch>/tasks.md` is a planning artifact, not a deliverable).

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's next `gh pr ready` either falsely denies a clean branch (over-broad sanctioned-set failure) or lets a wrong-identity branch burn a CI cycle — both visible as pipeline stalls, not user-facing product damage. This repo's end user is the operator.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the gate reads commit metadata already in git history and two repo-tracked rosters; no new egress, store, or credential surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a local advisory deny/allow in the agent's own workflow cannot reach a user's data, money, or trust surface — worst case is a wasted CI cycle (the status quo the fix removes).
- `threshold: none, reason:` the touched files are repo-local hooks/skill prose — not the preflight sensitive-path set — and the gate reads only metadata already committed to git.

## Observability

```yaml
liveness_signal:
  what:            "deny/pass decisions emitted as rule-incident rows for rule_id wg-cla-signed-author-before-merge (emit_incident), plus the fixture suite registered in scripts/test-all.sh under .claude/hooks/*.test.sh"
  cadence:         "per `gh pr ready`/`gh pr merge` invocation; suite per CI run"
  alert_target:    "weekly rule-metrics aggregator reads .claude/.rule-incidents.jsonl; CI red on suite FAIL"
  configured_in:   ".claude/hooks/cla-signed-author-gate.sh (emit_incident call); scripts/test-all.sh suite glob"
error_reporting:
  destination:     "hook deny JSON on stdout (the only channel a PreToolUse gate has); incident rows in .claude/.rule-incidents.jsonl"
  fail_loud:       "permissionDecision:'deny' payload names offending emails; a silently-broken sanctioned-set builder resolves to exit 0 (documented fail-open posture, same as today)"
failure_modes:
  - mode:          "sanctioned-set drift — a bot added to cla.yml allowlist on main but author email pattern not matching"
    detection:     "over-deny surfaces immediately at the operator's next `gh pr ready` (fail-closed direction); under-deny is bounded to the noreply convention which is the only offline-resolvable mapping"
    alert_route:   "operator-visible deny message at ready time"
  - mode:          "origin/cla-signatures ref absent (partial clone) — signed-noreply contributors over-denied"
    detection:     "deny message names the sanctioned sources; the missing component is listed in it"
    alert_route:   "operator-visible deny message at ready time"
logs:
  where:           ".claude/.rule-incidents.jsonl (per-repo, emit_incident sink)"
  retention:       "repo-local until swept; aggregator reads weekly"
discoverability_test:
  command:         grep SANCTIONED .claude/hooks/cla-signed-author-gate.sh
  expected_output: SANCTIONED
```

## Guard Contract

### Guard 1 — commit-author sanctioned-subset check (extended `cla-signed-author-gate.sh`)

**Property.** Every unique author and committer email on `origin/main..HEAD` belongs to the offline-derivable CLA-sanctioned set (session `git config user.email`, pinned allowlisted-human emails, or a `<id>+<login>@users.noreply.github.com` whose login is in the `origin/main` copy of `cla.yml`'s allowlist or `origin/cla-signatures`' `signedContributors[].name`) before `gh pr ready`/`gh pr merge` proceeds.

**Assembly.** The property quantifies over (a) the unique `%ae` ∪ `%ce` set from `git log origin/main..HEAD` — the single chokepoint every branch commit flows through; (b) the trigger commands `gh pr ready`/`gh pr merge` matched by the existing chain-boundary grep (unchanged); (c) the sanctioned-set sources — `git -C "$WORK_DIR" config --get user.email`, the `SANCTIONED_EMAILS` constant, and the two base-ref roster reads — every member flows through ONE `is_sanctioned` predicate, the chokepoint where membership is decided. There are exactly two deny sites: the preserved `noreply@anthropic.com` first-stage deny and this subset deny.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the login-membership check — accept ANY `*[bot]@users.noreply.github.com` email | RED — the devin-bot arm (`158243242+devin-ai-integration[bot]`, measured cla-check failure) and a fabricated `999999999+madeup[bot]` arm must still deny |
| 2 | Neuter the set-builder to always return empty and keep `exit 0` (vacuous dispatch: "0 checked" reads as pass) | RED — the wrong-identity arm must still deny; the explicit all-sources-absent arm distinguishes legitimate fail-open from vacuity |
| 3 | Check only the FIRST commit's author (stops at first member) | RED — the mixed-author arm: compliant first commit, unsanctioned second commit must deny and name the second offender |
| 4 | Check `%ae` only, drop `%ce` | RED — the committer-only arm (clean author, unsanctioned committer) must deny |
| 5 | REORDER the subset check ahead of the dedicated `noreply@anthropic.com` deny | RED — the noreply arm asserts the dedicated subagent-commit deny message, which a generic subset deny loses; order is the property (specialized remedy before generic) |
| 6 | Suite-side: delete the deny-payload JSON parse inside `assert_deny` (harness mutation, guard untouched) | RED — an instrument self-test / counter floor proves the suite can still observe a deny |
| 7 | Must-PASS discriminator: allowlisted-bot noreply + signed-login noreply + config-equal authors on one branch | PASS — separates this guard from a deny-everything stub |
| 8 | Must-PASS discriminator: all sanctioned sources unreadable/absent | PASS (fail-open) — the property is "enforce when evaluable", not "deny by absence" |

**Anchor.** The guard compares stored values — `cla.yml`'s allowlist and `cla.json`'s signatures — read at `origin/main` and `origin/cla-signatures` respectively, never the PR head, so a branch cannot widen the roster that sanctions its own commits (mirroring the `pull_request_target` base-ref invariant in ADR-201 §5). The pinned `SANCTIONED_EMAILS` constant is repo-reviewed in the same diff; a weakening needs a second commit a reviewer can see.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A ship/ready-time gate: unique authors on origin/main..HEAD must be a subset of {git config user.email, devin bot, CLA roster}; block gh pr ready otherwise (precommit-guard.sh or a ship phase)." | Phase 1 — subset check in `cla-signed-author-gate.sh` (site chosen over the two suggested alternates; see Cut List) | mapped |
| 2 | "Doc/rule line in ship + work skill text and/or AGENTS corpus." | Phase 3 — `AGENTS.rules.md` + `git-worktree` + `work` + `ship` + `INSTRUCTIONS.md` edits | mapped |
| 3 | "Optionally a pre-commit hook warning when committer email != configured and no override is sanctioned." | — | descoped — justification: optional in the ask; a new per-commit firing surface buys only earlier feedback over the same property the ready-gate already blocks; tracked as Non-Goal with follow-up |
| 4 | "The sanctioned override path (bot/`devin-ai-integration[bot]` or the CLA-allowlisted identity on unset-config sessions) must be PRESERVED as a carve-out, not banned outright" | Sanctioned-set design, Phase 2 T-carve-out arms — but the devin-bot membership is corrected by measured evidence (it fails cla-check; PR #11690, learning 2026-10-30); the CLA-allowlisted-identity and allowlisted-bot carve-outs ARE preserved | mapped (with correction) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Subset check in `cla-signed-author-gate.sh` | "unique authors on origin/main..HEAD must be a subset of" + #7218 "Invert the check" | asked |
| Sanctioned set = config + noreply-login resolvers + pinned human email | "{git config user.email, devin bot, CLA roster}" + #7218 "the allowlist the CLA action actually uses … or appears in signatures/cla.json" | asked |
| Deny message generalizing filter-branch fix | implicit in gate's existing affordance (issue: "the remedy the gate's own deny message documents") | inferred — justification: a deny with no recovery path strands the agent mid-pipeline; the existing hook already establishes this contract |
| `noreply@anthropic.com` first-stage deny preserved | — | inferred — justification: existing behavior + specialized message for the modal subagent-commit class; removing it would regress coverage the issue did not ask to remove |
| `AGENTS.rules.md` / skill-prose widenings | "Doc/rule line in ship + work skill text and/or AGENTS corpus" | asked |
| Test arms + Guard Contract | — | inferred — justification: `cq-write-failing-tests-before` + plan Phase 2.12 make the battery part of the guard deliverable, not optional scope |

### Split Assessment

- Subsystems touched: 3 — `.claude`, `plugins/soleur`, `AGENTS.rules.md` (repo root)
- Planned files: 7 | Estimated changed lines: ~320
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `gh pr ready` (or `gh pr merge`) on a branch whose `origin/main..HEAD` commits carry ANY author or committer email outside the sanctioned set is denied by `cla-signed-author-gate.sh`, and the deny payload names each offending email. Verified by the suite's wrong-identity arms (`jean@jikig.ai`-class, `ops@jikigai.com`-class).
- [ ] AC2 — A branch authored entirely by `158243242+devin-ai-integration[bot]@users.noreply.github.com` is denied (regression pin for the measured PR #11690 failure — devin bot is NOT sanctioned).
- [ ] AC3 — Commits authored/committeed by the session's `git config user.email`, by an allowlisted-bot noreply email (`<id>+<allowlisted-login>@users.noreply.github.com`), by a signed contributor's noreply email (`<id>+Elvalio@users.noreply.github.com`), or by the pinned allowlisted human email are NOT denied (carve-outs preserved, including the unset-config `-c` override path).
- [ ] AC4 — The `noreply@anthropic.com` first-stage deny still fires with its specialized message ahead of the subset check (existing T1–T6 arms stay green).
- [ ] AC5 — Fail-open posture preserved: invalid `.cwd`, non-worktree, `main`/`master`/detached, missing `origin/main`, or ALL sanctioned sources unreadable → `exit 0`.
- [ ] AC6 — `AGENTS.rules.md` `wg-cla-signed-author-before-merge`, `git-worktree/SKILL.md` `hr-never-fake-git-author` Sharp-Edges bullet, `devin/INSTRUCTIONS.md` §Devin-specific considerations, `work/SKILL.md`, and `ship/SKILL.md` all state the sanctioned-set semantics and the "never `-c user.*` when config already supplies identity" rule.
- [ ] AC7 — `bash .claude/hooks/cla-signed-author-gate.test.sh` reports all arms passed and exits 0; the suite is picked up by `scripts/test-all.sh` unchanged (glob `.claude/hooks/*.test.sh`).
- [ ] AC8 — PR body carries `Closes #12027` AND `Closes #7218` (the fix covers both named gaps).

## Domain Review

**Domains relevant:** Engineering (tooling/CI gate) — assessed all 8 domains semantically; no marketing/sales/product/support/finance/legal/operations surface. CTO consult executed inline (no `run_subagent` in this session — `sequential-fallback` disclosed; role executed, independent agent did not).

### Engineering

**Status:** reviewed (inline, sequential-fallback)
**Assessment:** Site selection is correct — extending the already-bound `gh pr ready`/`merge` PreToolUse hook beats both alternates in the issue (`precommit-guard.sh` is the commit-on-main cloud-restore; a ship-phase prose check is self-attestation, invisible to a boolean gate). The sanctioned-set derivation mirrors exactly what `cla-check` accepts (allowlist ∪ signatures, login-keyed) intersected with the only offline-resolvable email→login mapping (GitHub noreply convention). Reading rosters at base refs matches ADR-201 §5. Accepted risk: non-noreply signed contributors over-deny (fail-closed, documented). No architecture change — same hook, same trigger, wider predicate.

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Edit/Create (mechanical override checked: no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, no ui-surface-terms path match).
**Decision:** skipped (no user-facing surface — orchestration/tooling change)

## Architecture Decision (ADR/C4)

No ADR — this change extends an existing guard's predicate to match the property its governing rule (`wg-cla-signed-author-before-merge`) already states; it creates no ownership/tenancy boundary, substrate, trust boundary, or ADR divergence. ADR-201 remains the governing record and is untouched (roster unchanged, allowlist untouched, no third required check, additive evidence still never gates).

**C4 views — checked and found already-modeled:** (a) external human actors — none new (commit authors are the existing `founder`/contributor actors in `model.c4`); (b) external systems — GitHub/`cla.yml`/`cla-signatures` are read-only inputs the existing Devin/Claude hook elements already consume (the `devin` element's hook-registry description in `model.c4` covers `.claude/hooks/` dispositions); (c) containers/data stores — none; (d) actor↔surface relationships — unchanged (the gate reads the same refs CI reads; no new edge). Conclusion: no `.c4` edit. Read `model.c4` (1071 lines — Devin/hook/plugin elements at lines 24–53, contributor actor at ~121), `views.c4`, `spec.c4` — all three consulted; derived cardinalities not applicable.

## Non-Goals

- **A per-commit warning hook** (issue candidate c) — deferred: a new firing surface and per-commit latency buys only earlier feedback over the same property the ready-gate already denies; a tracked `type/chore` follow-up should be filed at ship if the operator wants it.
- **A third required CI status check / allowlist or roster edits / `cla.yml` changes** — rejected by ADR-201 and out of scope.
- **Email→login resolution via GitHub API** — deliberately offline-only: a PreToolUse hook must not add a network dependency to the ready boundary; the noreply convention is the only resolvable mapping and covers every sanctioned identity class in use.

## Test Scenarios

- **unit** — Given a branch with commits authored `jean@jikig.ai` and config `user.email=jean.deruelle@jikigai.com`, when `gh pr ready` fires, then DENY names `jean@jikig.ai` (the #12027 repro).
- **unit** — Given commits authored `ops@jikigai.com` (non-noreply, unsigned, unconfigured), when `gh pr merge` fires, then DENY (the #7218 repro).
- **unit** — Given commits authored `158243242+devin-ai-integration[bot]@users.noreply.github.com`, when `gh pr ready` fires, then DENY (regression pin; the bot is in neither roster).
- **unit** — Given commits authored `273333864+soleur-ai[bot]@users.noreply.github.com` with the allowlist fixture carrying `soleur-ai[bot]`, when `gh pr ready` fires, then PASS.
- **unit** — Given commits authored `92384917+Elvalio@users.noreply.github.com` and a `origin/cla-signatures` fixture listing `Elvalio`, when `gh pr ready` fires, then PASS.
- **unit** — Given `git config user.email` unset and commits authored `jean.deruelle@jikigai.com` (pinned `SANCTIONED_EMAILS`), when `gh pr ready` fires, then PASS (unset-config carve-out).
- **unit** — Given a clean-author commit whose COMMITTER is unsanctioned, when `gh pr ready` fires, then DENY (`%ce` coverage).
- **unit** — Given commit 1 sanctioned + commit 2 unsanctioned, when `gh pr ready` fires, then DENY naming commit 2's email (second-member matrix row).
- **unit** — Given `.github/workflows/cla.yml` absent at `origin/main`, `origin/cla-signatures` absent, and config unset, when `gh pr ready` fires, then PASS (all-sources-empty fail-open).
- **unit** — Given the existing T1–T6 fixtures, when the suite runs, then all still pass (noreply deny preserved, trigger boundaries unchanged).
- **integration** — `bash .claude/hooks/cla-signed-author-gate.test.sh` exits 0 and prints `<n>/<n> passed`.

## Success Metrics

- Zero non-sanctioned-author commits reach `gh pr ready`/`merge` without a deny — the two measured incident classes (#12027 `jean@jikig.ai`, #7218 `ops@jikigai.com`) plus the devin-bot class all deny pre-CI.
- Zero new false denies on the four documented carve-outs (configured identity, allowlisted bots, signed noreply logins, pinned human override).

## Dependencies & Risks

- **Risk: sanctioned-set drift** — a bot newly added to `cla.yml` allowlist passes automatically (noreply+allowlist check reads `origin/main` cla.yml); a NEW non-noreply human identity requires a `SANCTIONED_EMAILS` pin + config. Mitigation: the deny message names the sources.
- **Risk: stale `origin/main`** — an allowlist narrowed on main since last fetch over-denies. Direction is fail-closed; `git fetch` recovers.
- **Risk: `pull_request_target` semantics** — none; the local gate is advisory to the agent, never the security boundary. CI `cla-check` remains authoritative.
- **Dependency:** `jq` (already used by the hook for the deny payload), `git`, fixture-repo isolation conventions in the suite.

## References & Research

- Issues: #12027 (this fix), #7218 (folded in — same mechanism), #7169 (incident PR), #4948 (origin of the hook)
- Evidence: PR #11690 `cla-check: fail` (devin bot measured non-sanctioned); PR #12002 (incident)
- ADR-201 (`knowledge-base/engineering/architecture/decisions/ADR-201-corporate-cla-is-a-repo-tracked-roster-not-an-allowlist-entry.md`) — CLA architecture; rejects a third required check
- Learnings: `2026-10-30-npm-e404-...-devin-commits-break-cla-check.md`, `2026-06-03-cla-fails-on-bot-commit-authored-by-loginless-identity.md`, `2026-04-24-fake-git-author-bare-repo-bot-override.md`, `2026-06-04-subagent-commits-fail-cla-check.md`, `2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md`
- Surfaces: `.github/workflows/cla.yml:62` (allowlist), `origin/cla-signatures:signatures/cla.json`, `plugins/soleur/skills/fix-issue/SKILL.md:175` (sanctioned `-c` precedent), `plugins/soleur/devin/INSTRUCTIONS.md:327`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- The sanctioned-set builder reads `git show origin/main:.github/workflows/cla.yml` and `git show origin/cla-signatures:signatures/cla.json` — the fixture repos must plant BOTH refs/files or the all-sources-empty arm silently passes everything (the vacuity the matrix row 2 exists to expose).
- `pull_request_target` reads `cla.yml` from `main` — do NOT suggest an in-PR allowlist edit as a remedy anywhere; it cannot self-heal.
- The deny payload must keep `exit 0` with `permissionDecision: "deny"` JSON — the hook's contract is JSON-deny, never a non-zero exit.
