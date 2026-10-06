---
title: "fix(ci): take pipe-fed early-exit grep readers to zero in infra and CI (Wave A2), fold the gen-github-egress-cidr race (J)"
type: fix
date: 2026-10-06
slug: pipefail-early-exit-wave-a2-infra-ci
branch: feat-one-shot-merge-queue-pipefail-wave-a2
issue: 9217
closes: none
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): take pipe-fed early-exit grep readers to zero in infra and CI (Wave A2)

Spec lacks a valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (fail-closed).
PR body uses `Ref #9217`, `Ref #7005`, `Ref #6601`, `Ref #7376`, `Ref #9482`; never `Closes`.

## Enhancement Summary

**Deepened on:** 2026-10-06
**Method:** the plan-review panel (DHH, Kieran, code-simplicity, CTO devex) served as the review fan-out; the deepen gates 4.5-4.12 were run mechanically; every cited issue, PR, rule id, path and command was re-verified live (below). No additional per-section research agents were spawned: the Phase 1 research already read the guard, the three user_data renders, the apply workflows and the pin sites directly.

### Key improvements applied
1. Corrected a false claim: `scripts/check-deploy-script-parity.sh` does not tie the two `_gak_ref_ok` copies; the `GAK_BOTH` rows of `ci-deploy.test.sh` do (Kieran P1).
2. The real-table probe now runs `scan_sweep` on a scratch root, so `SWEEP_PATHSPEC` and `PATTERN_V2` are exercised and the "zero rule" for `.github` and `lefthook.yml` is proven, not only the verdict (Kieran P1).
3. Mutation row 6 inserted below the gated rows (above them it was masked by a stale-deferral red), and rows 2, 3, 4, 7 demoted to one-off hand mutations (simplicity P1).
4. Suite lists completed (`cloud-init-user-data-size.test.ts`, `cron-egress-enforce-probe.test.sh`, `soleur-host-bootstrap-observability.test.sh`, `inngest-luks-cutover.test.sh`, `cloud-init-ghcr-seed-login.test.sh`); `web-private-nic-guard.sh` added to the re-provision-on-merge risk.
5. Behaviour-preserving form for `reusable-release.yml` (`|| tags=""`), AC exit-status traps fixed, streaming-producer census added (none among the 140 lines).

### New considerations discovered

- The per-merge apply excludes the inngest, registry and git-data hosts, so the user_data drift is silent until the next full apply or dispatch; the plan no longer cites the destroy guard as a barrier.
- `cron-egress-*` edits re-run the nft install on web hosts at merge, and #8945 records that `nft -f` does not replace atomically (see R9).
- Two plan-review reviewers recommend splitting class W up front; persisted as a User-Challenge in `specs/feat-one-shot-merge-queue-pipefail-wave-a2/decision-challenges.md`.

### Live verifications run in this pass

- `gh issue view` on #9554, #9525, #9523, #9552, #9576, #9529, #9571, #9569, #8945, #7432, #9482, #7376, #6601, #7005, #5288: all exist; #9554/#9525/#9523/#5288 MERGED, the rest OPEN; titles match the roles the plan gives them.
- Rule ids cited in the plan all resolve to active `[id: ...]` entries in `AGENTS.md`.
- Gate 4.12: exactly one unfenced `## Scope Check`; gate 4.8: no PAT-shaped token; gate 4.11: `python3 scripts/lint-guard-contract.py` green (1 guard entry in this plan).
- `bash .claude/hooks/grep-q-pipe-guard.test.sh` takes 2.9 s locally and prints `PASS: grep-q-zero-sweep-pass`.

## Overview

The 2026-10-06 sweep (#9554, merge `ed6a77b868`) made the guard derive the pipe-fed early-exit
`grep` population repo-wide and converted the production roots. What remains in infra and CI is
deferred in `SWEEP_DEFERRALS` (`.claude/hooks/grep-q-pipe-guard.test.sh:420`): 92 hits under
`apps/web-platform/infra/*`, 45 under `.github/*`, 1 in `lefthook.yml`, 2 in the drain-labeled-backlog
workflow prompt (140 code lines, re-measured on `origin/main` 2026-10-06 with the guard's own
`PATTERN_V2`, comments and `# sigpipe-demo: intentional` lines dropped).

This plan converts them to a semantics-preserving form, deletes or lowers the rows, adds
mutation-checked probe rows over the REAL table, and folds item J: the unexplained red on run
37426931446 turned out to be a genuine instance of the same class (see Research Insights). Items B, D,
E, F, G, H, I are follow-on PRs (Program roadmap, below).

**Two findings change the shape of the work and are the reason this is not "convert 140 lines":**

1. **21 of the 92 infra hits sit in files that feed `user_data` of hosts that carry NO
   `ignore_changes=[user_data]`.** `cloud-init-inngest.yml` (4), `cloud-init-registry.yml` (13),
   `cloud-init-git-data.yml` (3) and `git-data-bootstrap.sh` (1, embedded by
   `modules/git-data-userdata/main.tf:84`). Any byte change replaces the host (`inngest-host.tf:477`,
   `zot-registry.tf:604`, `git-data.tf:483`; `inngest-host.tf:477-481` says it outright: "every
   cloud-init edit force-replaces it ... gate all cloud-init edits to the maintenance-window
   `apply_target=inngest-host` dispatch"). The per-merge apply is an allow-list that excludes these
   hosts (they are `OPERATOR_APPLIED_EXCLUSIONS` or dispatch-only), so nothing is replaced at merge:
   the edit plants silent `user_data` drift that the PR `plan` comment and
   `scheduled-terraform-drift.yml` would surface and that the next full apply or dispatch turns into a
   replace (the inngest host is the sole scheduler, ADR-100; the registry is the sole pull path,
   ADR-169). A lint-motivated edit must never schedule that. These four files keep an exact-count
   deferral row each, with the reason stated; they are not converted in this PR.
2. **The guard's documented forms (here-string, process substitution) are not valid in 3 of the
   dialects in play** (`#!/bin/sh` scripts, Terraform `remote-exec` inline strings run by `/bin/sh`,
   cloud-init `runcmd`/`#!/bin/sh` write_files), and a here-string silently changes semantics for an
   empty value (adds a newline: `printf '' | grep -qv x` is rc 1, `grep -qv x <<<""` is rc 0).
   The default transform below is dialect-neutral AND byte-exact.

## Research Insights

### Premise Validation (Phase 0.6)

Held: `origin/main` is `ed6a77b868` and this worktree contains it; #9217, #7005, #6601, #7376, #9482,
#9167, #8022 are all OPEN (`gh issue view`); the guard's live `DEFERRED:` lines match the brief
(92 / 45 / 1 / 2 in the A2 rows); run 37426931446 is `Infra Validation`, attempt 2, job
`deploy-script-tests (3/4)` failed on `gen-github-egress-cidr.test.sh`; drafts #9552 (item H) and
#9576 (item D) exist and neither touches a file in this plan (`gh pr diff --name-only`). Stale or
wrong in the brief: nothing material, but J ("decide flake vs real") resolves to real (below), and the
brief's row `apps/web-platform/infra/*` hides the replace-class carve-out
above. The ADR corpus was grepped for the mechanism (no ADR governs the guard's deferral table; ADR-100
and ADR-169 govern the replace-class hosts and are cited, not changed).

### Property List and Cut List (Phase 0.6b)

Properties: (P1) no pipe-fed early-exit `grep` remains in infra/CI code outside the four
replace-class files and intentional demos; (P2) the guard keeps each converted subtree at zero and the
four gated files at their exact count; (P3) no behaviour change on any host or CI step, and no host
replace is scheduled; (P4) J is explained from the artifact and the race is closed; (P5) the evidence
lands on the existing trackers (#9217, #9167).

| Mechanism proposed in the ask | Property | Already on main? | Disposition |
|---|---|---|---|
| here-string / process substitution | P1 | the guard header lists them, but `grep -c ... >/dev/null` (also listed, "grep -c compared against 0") is dialect-neutral and byte-exact | **Amended**: `-c` form is the default, here-string only where bash is certain AND input is never empty-capable (3 sites, F2) |
| delete or lower SWEEP_DEFERRALS rows | P2 | table exists (`:420`) | kept; rows split, not widened |
| mutation-checked rows | P2 | `_vp`/`sweep_probe_fail` harness exists (`:795`) | kept; new rows reuse `sweep_verdict` over the real table |
| fix J "if real and in the infra subtree" | P4 | n/a | kept (it is real, in `apps/web-platform/infra/scripts/`) |
| per-file source-text pin helper / new ratchet | none | n/a | **Cut**: pin census is a one-off work step; nothing committed |
| `--ratchets` selector, affected-paths index change | none here | item G / H | **Cut** (follow-on, #9552 owns H) |

### The measured race behind J (Phase 0.6c: the figure and the command that produced it)

The failing assertion is `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh:779`:
`grep -vE '^[[:space:]]*#' "$GEN" | grep -qE '^[[:space:]]*meta_json=...'` under `set -uo pipefail`
(`:12`). `$GEN` is 17,002 bytes; `grep -v` writes in 4 KiB chunks and `grep -q` exits at the first match
(line 88), so the producer takes SIGPIPE (rc 141) or, under CI's ignored SIGPIPE, EPIPE (rc 1) and the
pipeline reads as a miss. The CI log shows exactly that: `FAIL: live fetch bounded (no comment-stripped
meta_json=... line)`, `94 passed, 1 failed (95 cases)`, rc 1 after 5 s, passing on attempt 1.

Reproduced locally (16 cores, the assertion's exact pipeline, 3,000 iterations each):
`default SIGPIPE: miss=19/3000 (0.63%)`, `ignored SIGPIPE (trap '' PIPE): miss=11/3000 (0.37%)`, with
`grep: write error: Broken pipe` on stderr. Command: the loop in task T1.1 below. The
file has 4 more instances (`:265`, `:305`, `:312`, `:615`); `:305` and `:312` pipe `python3 "$ORACLE"`
into `grep -q`, the producer-side variant. **Verdict: real, latent since #5288, in the infra subtree,
not a flake.** It sits in the `apps/web-platform/*.test.sh` row (Wave B territory) only because `*`
crosses `/` in the row globs; the fix is in scope because the brief says so.

### Hit census (re-measured 2026-10-06; command: the guard's `PATTERN_V2` through `git grep --no-index --exclude-standard -anE`, comments and marker lines dropped)

| Class | Files (hits) | Dialect and pipefail | Reaches a host via | Treatment |
|---|---|---|---|---|
| **H** replace-class (21) | `cloud-init-registry.yml` (13), `cloud-init-inngest.yml` (4), `cloud-init-git-data.yml` (3), `git-data-bootstrap.sh` (1) | bash and `#!/bin/sh` inside `write_files`; `runcmd` | `user_data` of `hcloud_server.{registry,inngest,git_data}` (no `ignore_changes`) | **Not converted.** Exact-count rows, stated reason, converted only inside a PR already scheduled for the maintenance-window dispatch |
| **W** web-host deploy artefacts (50) | `ci-deploy.sh` (15), `cron-egress-postapply-assert.sh` (12), `server.tf` (9, `remote-exec` inline, `/bin/sh`), `soleur-host-bootstrap.sh` (5, `#!/bin/sh`, `set -e`), `web-private-nic-guard.sh` (4, `set -u`), `cron-egress-enforce-probe.sh` (2, `set -e`), `workspaces-luks.tf` (1, inline), `cron-egress-resolve.sh` (1), `cloud-init.yml` (1, `runcmd`) | mixed; pipefail ON only in `ci-deploy.sh`, `cron-egress-resolve.sh` | `terraform_data.deploy_pipeline_fix` (`apply-deploy-pipeline-fix.yml` auto-applies on merge; `[skip-deploy-fix-apply]` is NOT used), `cloud-init.yml` is inert on web-1 (`ignore_changes=[user_data]`, `server.tf:597`) | Convert (F1) |
| **C** CI/dev-only infra (21) | `inngest-userdata-budget.sh` (7), `registry-userdata-budget.sh` (6), `scripts/sigpipe-triage-feasibility.sh` (3), `zot-image-oci-archive.sh` (2), `inngest-luks-cutover.sh` (1), `git-data-userdata-budget.sh` (1), `audit-bwrap-uid.sh` (1) | bash, pipefail ON (all but audit-bwrap-uid) | nothing deployed | Convert (F1; F3 for the demo) |
| **CI** (48) | `.github/workflows/*.yml` (42 in 18 files), `.github/scripts/check-pr-body-vs-diff.sh` (2), `.github/scripts/check-sweep-completeness.sh` (1), `lefthook.yml` (1), drain workflow prompt (2) | GHA `run:` is `bash -e {0}` unless the step sets `shell: bash` or `set -o pipefail` (checked per step in Phase 0) | nothing deployed | Convert (F1, F2, F4) |

(Class sums: 21 + 50 + 21 = 92 infra; 45 `.github` (42 workflow lines + 3 script lines) + 1 + 2 = 48 for the CI
class.) Pipefail is ON for only part of the population; the rest is latent (a
future `set -o pipefail` or a longer producer flips it), which is why the guard counts all of it.

### Institutional learnings applied

- `learnings/test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`: the mechanism, and that the producer side (a stub that never reads) is invisible to a line search; the join is Wave B.
- `learnings/test-failures/2026-10-05-the-pipefail-sweep-was-seven-times-the-tracker-figure-and-the-audits-absent-in-ci-row-was-wrong.md`: re-measure before quoting; every count in this plan carries its command.
- `2026-10-05-i-told-the-operator-a-count-was-wrong-and-my-grep-had-counted-a-comment.md`: the 168 raw lines in infra/CI include 28 comment or marker lines; the code census is 140.
- `2026-02-21-github-actions-workflow-security-patterns.md`: `run:` defaults to `bash -e`, not `-eo pipefail`.
- `2026-03-20-terraform-base64encode-cloud-init-deduplication.md`, `2026-04-19-cloud-init-packages-stage-silent-drop-audit.md`: templatefile `$${` escaping and `ignore_changes=[user_data]` semantics; the carve-out depends on them.
- `2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md`: run ratchets by name; `TEST_GROUP=affected` leaks to nested runners.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`: the new probe rows must mutate the table, not only the code.

### Code-review overlap (Phase 1.7.5)

87 open `code-review` issues queried; three name a file in this plan: #3829 (`pr-quality-guards.yml`, Sentry
monitor scrub gate) **Acknowledge** — different concern; #8593 (`scheduled-inngest-health.yml`, probe
window) **Acknowledge** — the one line this plan touches (`:284`) is not the probe window; #2197
(`server.tf`, billing doc) **Acknowledge** — unrelated. None is folded in or closed.

## Open Code-Review Overlap

#3829, #8593, #2197: acknowledged, remain open (see above). No fold-in.

## Hypotheses

The description matches the network-outage trigger words (SSH, firewall, timeout) only because the post-merge apply of the web-host `terraform_data` resources runs over an SSH bridge through the Cloudflare Tunnel and the stub inventory lists `ssh`. No connectivity symptom is diagnosed and no sshd or fail2ban hypothesis is proposed. Layers L3 firewall, L3 DNS/routing, L7 TLS and L7 application are opted out with one artefact: the last three `apply-deploy-pipeline-fix.yml` runs succeeded (`gh run list --workflow apply-deploy-pipeline-fix.yml`: 2026-10-04 dispatch, 2026-10-01 push x2), the bridge uses no admin-IP grant (header of that workflow), and no hostname, route or HTTPS path is touched. The one service-layer risk, a mis-edited host script, is covered by the owning suites and the apply run log (`workflow run log`).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "apps/web-platform/infra/* (92, mode =) ... Convert ... then DELETE or lower the row" | 21 of the 92 are in files whose edit force-replaces prod hosts on the next full apply (ADR-100, ADR-169; no `ignore_changes=[user_data]`); the per-merge apply excludes those hosts, so the drift is silent until then | Row is replaced by four exact-count rows (21), not deleted; 71 converted |
| "Convert with here-string / process substitution" | invalid in `#!/bin/sh`, Terraform inline, `runcmd`; here-string changes empty-input semantics | Default form is `grep -c ... >/dev/null` (F1), forms table in the guard header gains one row |
| J: "decide flake vs real" | real: 19/3000 locally at the exact assertion; source-text-pin pipeline over a 17 KB file | Fix in this PR (5 sites), lower the `apps/web-platform/*.test.sh` ceiling by 5 |
| `.github/*` 45 "arm path-gated batteries" | true; also two parity pairs must change in lockstep (below) | Lockstep tasks T3.x |
| "the deploy-pipeline-fix drift gate may fire" | it is a designed auto-apply (`apply-deploy-pipeline-fix.yml` `paths:` includes `ci-deploy.sh`, `cron-egress-*`); the merge is the authorization | Class W is NOT skipped with `[skip-deploy-fix-apply]`; post-merge verification reads the run |

## Program roadmap (follow-on PRs; NOT in this PR's tasks)

One PR per subsystem, each through review, ship and merge before the next starts. Before each, re-run `gh pr list --state open`.

| Item | PR boundary (subsystem) | Status vs this PR |
|---|---|---|
| **A3** (new, from this plan) | the four replace-class files (21 hits): `cloud-init-{registry,inngest,git-data}.yml`, `git-data-bootstrap.sh` | Gated: rides the first PR that already needs a maintenance-window `apply_target` dispatch for those hosts; its row is deleted there. Not a standalone lint PR |
| **B** | Wave B test harness (~800 hits: `tests/*`, `plugins/soleur/test/*`, `apps/web-platform/*.test.sh`, `scripts/*.test.sh`, `.claude/*.test.sh`, `plugins/soleur/*.test.sh`, 4 small rows) plus the producer-side join (28 production pipes into stubbable verbs; live instance `cutover-inngest-workflow.test.sh:1335`) | The first wave that needs the scratch transformer commits it; this PR uses sed-by-hand and commits nothing |
| **D** | live-verify rail budget (#8022, #7969, #7215, #5634) | Owned by draft #9576; coordinate, do not duplicate |
| **E** | `scripts/lint-infra-no-human-steps.py` finding on lint-bot-statuses (run 37428625225 failed this job on 2026-10-06 07:16 UTC) | separate PR; evidence already on #9482 |
| **F** | guard blind spots: wrappers, flag order, head-N pipes, split-line pipes, multi-line awk, reader behind a variable or function, `.md` fences (29), `.ts` (2), knowledge-base scripts (13) | separate PR on `.claude/hooks/grep-q-pipe-guard.test.sh` |
| **G** | `--ratchets` selector in `scripts/test-all.sh` | machinery file, arms the full battery; batch the push |
| **H** | cheaper CI path for edits touching only the affected-paths index | Owned by draft #9552 (`scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`); no file overlap with this plan |
| **I** | measure whether JOBS=1 (#7432, `main-health-monitor.yml` lines 342 and 369) can go | window opened 2026-10-06 09:32 UTC; not before enough merge-queue runs exist |
| **C** | evidence comment on #9167 only | **In this PR** as a comment (no code), see T5.2 |

## Implementation Phases

Forms (T-rules). Every transform is checked per site against the guard's `PATTERN_V2` after the edit.

- **F1 (default; dialect-neutral; byte-exact).** `PRODUCER | grep -<flags> ARGS` where the flag cluster contains `q`: replace `q` with `c` and append `>/dev/null` after the last argument, before `||`, `&&`, `;`, `)` or `then`. Exit status is identical (`grep -c` exits 0 iff at least one line was selected; verified on bash and dash: match=0 miss=1 empty-with-`-v`=1 for both `-q` and `-c`), it reads the whole stream so the producer never takes EPIPE, it adds no newline (a here-string would turn `printf '' | grep -qv x` from rc 1 into rc 0), and it is valid in `/bin/sh`, Terraform inline strings and YAML `runcmd`. `>/dev/null` carries no `$`, `"` or `%{`, so it needs no HCL or templatefile escaping.
- **F2 (output-bearing `-m1`, bash-only contexts, 3 sites).** `printf '%s' "$out" | grep -m1 P | cut ...` becomes `grep -m1 P <<<"$out" | cut ...` (the extra newline is harmless: the value is a non-empty multi-line `key=value` block). `reusable-release.yml:294` (`git tag --list ... | { grep -m1 -E P || [ $? -eq 1 ]; }`): the existing comment claims `-m1` avoids SIGPIPE, which is false (the producer is the one that takes it, and `git tag` is the producer); restructure to `tags=$(git tag --list ...) || tags=""` then `LATEST_TAG=$(grep -m1 -E "..." <<<"$tags" || [ $? -eq 1 ])` and correct the comment. The step runs under plain `bash -e` with no pipefail, so a failing `git tag` used to fall through to the `0.0.0` fallback; the `|| tags=""` keeps exactly that behaviour (property P3: no behaviour change). Making it fail loud is a separate decision, not taken here.
- **F3 (intentional demos).** `scripts/sigpipe-triage-feasibility.sh` lines 273, 291, 325 exist to show the shape (the script is a SIGPIPE feasibility probe): append `# sigpipe-demo: intentional`. Not converted.
- **F4 (prompt literal).** `drain-labeled-backlog.workflow.js:181,184` are instructions the LLM executes in bash: rewrite to `grep -Fxc "${safeMilestone}" >/dev/null` / `grep -Fxc "${safeLabel}" >/dev/null`, keeping template-literal escaping; the SKILL.md prose at `:84` mentions `grep -Fxq` and is updated to match.

### Phase 0 — Preflight and census (no edits)

- [ ] T0.1 `gh pr list --state open --json number,title,headRefName`; `git fetch origin main && git merge-base --is-ancestor origin/main HEAD`. Comment on #9529 (seven shared files: `ci-deploy.sh`, `cloud-init.yml`, `cron-egress-enforce-probe.sh`, `cron-egress-resolve.sh`, `server.tf`, `soleur-host-bootstrap.sh`, `rule-audit.yml`) and on #9571 (`workspaces-luks-verify.yml`): state the zero rule and the overlap so they use the safe forms. Other drafts are handled by the T5.5 rebase. No comment on #9552 or #9576 (no shared file).
- [ ] T0.2 Regenerate the 140-line list with the guard's `PATTERN_V2` (the same `git grep` as `scan_sweep`, comments and markers dropped) into the scratchpad; for each hit record dialect (shebang; `inline`/`runcmd`/`write_files`; GHA `shell:` and `set -o pipefail` in the step), pipefail ON/OFF, deploy class (H/W/C/CI). Put the table in the PR body. For each producer also record that it TERMINATES: `grep -c` waits for the producer to finish where `-q` did not. Measured 2026-10-06 over the 140 lines: no streaming producer (`tail -f`, `journalctl -f`, `docker logs -f`, `--follow`, `watch`, `yes`, `ping`); the producers are `printf`/`echo` of a variable, `docker ps`, `nft list`, `ip addr`, `systemctl show`, `ss -ltn`, `findmnt`, `git diff`/`git tag`, `tar -tvf`, `gh api`/`gh label list`, `journalctl --header`.
- [ ] T0.3 Pin census, escape-aware: for each hit, search every `*.test.sh`, `*.test.ts` and `scripts/check-*` for the line text with `\\n`, `\"`, `\$` variants, not only the literal. Known pins: `ci-deploy.test.sh:9697-9701` (mutation rows replace the literal `*) if printf '%s\\n' \"\$2\" | grep -qxE ...` line of `ci-deploy.sh:2741`); the `GAK_BOTH` rows of `ci-deploy.test.sh` (the `_gak_ref_ok` line in `ci-deploy.sh` and its copy in `soleur-host-bootstrap.sh` are tied only by that mutation battery, not by `scripts/check-deploy-script-parity.sh`, which does not mention it); `scripts/skill-security-scan-step-body.test.sh` (`pr-quality-guards.yml:760` and `skill-security-scan-postmerge.yml:119`); `.github/scripts/test/test-check-pr-body-vs-diff.sh` (`check-pr-body-vs-diff.sh:65-66`); `web-private-nic-guard.test.sh`; the twin `*-userdata-budget.sh` pair. Output: the list of suites to run per file.
- [ ] T0.4 Confirm each glob and path this plan names resolves (`git ls-files | grep -E`), in particular the four gated paths and the `.github/scripts/check-*.sh` pair. Assert the carve-out premise mechanically instead of from the line citations: `grep -n 'ignore_changes' apps/web-platform/infra/inngest-host.tf apps/web-platform/infra/zot-registry.tf apps/web-platform/infra/git-data.tf` must show no `user_data` entry inside the `lifecycle` block of `hcloud_server.inngest`, `hcloud_server.registry` and `hcloud_server.git_data` (read each block; the comments name the absence, the block is the authority).

### Phase 1 — RED first: the guard table and real-table probe rows

- [ ] T1.1 Reproduce J before fixing it (the RED the work phase sees), from `apps/web-platform/infra/scripts`, and record both `miss=N` figures:

  ```bash
  GEN=gen-github-egress-cidr.sh; set -o pipefail
  P='^[[:space:]]*meta_json="\$\(curl -fsS --max-time 30 "\$META_URL"\)"'
  miss=0; for ((i=0;i<3000;i++)); do grep -vE '^[[:space:]]*#' "$GEN" | grep -qE "$P" || miss=$((miss+1)); done; echo "default SIGPIPE miss=$miss/3000"
  miss=0; for ((i=0;i<3000;i++)); do (trap '' PIPE; grep -vE '^[[:space:]]*#' "$GEN" | grep -qE "$P") 2>/dev/null || miss=$((miss+1)); done; echo "ignored SIGPIPE miss=$miss/3000"
  ```

- [ ] T1.2 Edit `SWEEP_DEFERRALS` (`.claude/hooks/grep-q-pipe-guard.test.sh:420`): delete `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`, `.github/*`, `lefthook.yml`; replace `apps/web-platform/infra/* | = | 92` with four rows ABOVE nothing broader (they are file-exact): `apps/web-platform/infra/cloud-init-registry.yml | = | 13 | #9217`, `.../cloud-init-inngest.yml | = | 4 | #9217`, `.../cloud-init-git-data.yml | = | 3 | #9217`, `.../git-data-bootstrap.sh | = | 1 | #9217`, with a comment naming the reason (`user_data` is ForceNew on these hosts and they carry no `ignore_changes`; ADR-100, ADR-169) and that the rows go in the PR that already schedules a maintenance-window dispatch for them. Lower `apps/web-platform/*.test.sh` from 188 to 183 after T2.1. Do not touch `.github/scripts/test/*`.
- [ ] T1.3 Add the `_vp_real` helper and checks for the PERMANENT mutation rows 1 and 6 and harness rows H1 and H3 (above; rows 2, 3, 4 and 7 are run once by hand, because the `=` arithmetic is already probed on synthetic tables and rows 3 and 7 name rows that A3 deletes); bump `SWEEP_PROBE_CHECKS` and `V2_GOOD_LINES` literals. Run the suite: it MUST be red (undeferred hits) until Phases 2-4 land.
- [ ] T1.4 Extend the header's "THE FORMS" table with the F1 row ("POSIX sh, Terraform inline, runcmd, or input that may be empty: `grep -cE P >/dev/null`; exit status equals `grep -q`, reads all input") and update the STATED LIMITS counts only if re-measured. Also update the FAIL-message "Rewrite" block in `sweep_verdict` (the text a developer sees when the guard fails, `echo "  Rewrite: ...` lines) with the same F1 line, and state when F2 is allowed (output-bearing `-m1`, bash only, value never empty-capable).

### Phase 2 — Class J and class C (no deployed artefact)

- [ ] T2.1 `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh`: convert `:265`, `:305`, `:312`, `:615`, `:779` (F1). Keep the `no "..."` message strings. Re-run the loop: `miss=0/3000` in both SIGPIPE modes. Run the suite itself 20 times.
- [ ] T2.2 Class C (21 hits): `inngest-userdata-budget.sh`, `registry-userdata-budget.sh`, `git-data-userdata-budget.sh`, `zot-image-oci-archive.sh`, `inngest-luks-cutover.sh`, `audit-bwrap-uid.sh` (F1); `scripts/sigpipe-triage-feasibility.sh` (F3). Owning suites: `registry-userdata-budget.test.sh`, `plugins/soleur/test/cloud-init-user-data-size.test.ts` (reads the budget scripts and `soleur-host-bootstrap.sh`, carries `WEB_GZIP_BUDGET`), `inngest-luks-cutover.test.sh`, `zot-image-oci-archive.test.sh`, `audit-bwrap-uid` tests, `sigpipe-triage-feasibility` tests (found by T0.3). `inngest-` and `registry-userdata-budget.sh` are twins: convert identically.

### Phase 3 — CI: `.github/*`, `lefthook.yml`, drain prompt

- [ ] T3.1 `.github/workflows/*.yml` (42 lines in 18 files) and the two `.github/scripts/check-pr-body-vs-diff.sh` and `check-sweep-completeness.sh` (3 lines): F1 everywhere; F2 for `scheduled-supabase-advisor-scan.yml:122-123` and `reusable-release.yml:294`. Lockstep: `pr-quality-guards.yml:760` and `skill-security-scan-postmerge.yml:119` change in one commit (run `scripts/skill-security-scan-step-body.test.sh`). Multi-line sites (`pr-quality-guards.yml:535-536` with `\` continuations, `workspaces-luks-verify.yml:292`, `tests` on `tenant-integration.yml:106` and `vendor-pin-verify.yml:89`) get `>/dev/null` before the continuation or `then`, never inside the pattern.
- [ ] T3.2 `lefthook.yml:449` (F1; lefthook runs `run:` through `sh`).
- [ ] T3.3 `drain-labeled-backlog.workflow.js:181,184` (F4) and `SKILL.md:84`. Syntax-check by wrapping the body in an async `new Function(...)` (a top-level `await`/`return` makes `node --check` false-flag); run the drain tests under `plugins/soleur/test/`.
- [ ] T3.4 Validate each touched workflow: `actionlint` if present, and the path-gated batteries it arms (`plugins/soleur/test/ci-path-gating.test.sh`, `lint-bot-*` tests, `pr-fanout-ledger.test.sh`).

### Phase 4 — Class W (web-host deploy artefacts; auto-applied on merge)

- [ ] T4.1 `ci-deploy.sh` (15, F1; pipefail ON): the producers are small, but under `set -euo pipefail` every one is a live instance. `:4126` (`docker ps ... | grep -q .`) F1. Convert the `_gak_ref_ok` line identically in `ci-deploy.sh` and `soleur-host-bootstrap.sh` (the `GAK_BOTH` rows of `ci-deploy.test.sh` tie the two copies and replace the literal line), update that literal if (and only if) the pin text moves, and prove the mutation still applies (the mutation row must report a RED when the pin is restored to the broken form, not "no-op").
- [ ] T4.2 `soleur-host-bootstrap.sh` (5; `#!/bin/sh`), `web-private-nic-guard.sh` (4), `cron-egress-postapply-assert.sh` (12), `cron-egress-enforce-probe.sh` (2), `cron-egress-resolve.sh` (1), `cloud-init.yml:511` (1): F1. `cron-egress-postapply-assert.sh` lines 111 and 122 are very long single lines: edit only the `grep` token and append the redirect.
- [ ] T4.3 `server.tf` (9) and `workspaces-luks.tf:253`: F1 inside the `inline = [ ... ]` strings (`sh`). Confirm with `terraform fmt -check` and `terraform validate` in `apps/web-platform/infra`, and that no `triggers_replace` hashes these inline strings (read each resource's `triggers_replace`; none of the nine is expected to) so no extra resource is queued. Enumerate EVERY workflow that can apply an edited `.tf` (not only the intended one): `apply-web-platform-infra.yml` fires on any `apps/web-platform/infra/**` merge, `apply-deploy-pipeline-fix.yml` on its listed trigger files, `infra-validation.yml` runs the PR `plan`; for each, read the plan or `paths:` line and record it in the PR body. The PR's infra `plan` job comment must show zero `hcloud_server.*` changes and no new `terraform_data` replace beyond the expected `deploy_pipeline_fix` and cron-egress families.
- [ ] T4.4 Run, by name: `ci-deploy.test.sh`, `cat-deploy-state.test.sh`, `scripts/check-deploy-script-parity.test.sh`, `cron-egress-firewall.test.sh`, `cron-egress-enforce-probe.test.sh`, `soleur-host-bootstrap-observability.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `cron-egress-self-heal.test.sh`, `cron-egress-nftables.test.sh`, `web-private-nic-guard.test.sh`, `fresh-boot-parity.test.sh`, `doppler-injection-bound.test.sh`, `workspaces-luks.test.sh`; plus `bash -n` and `shellcheck` (if present) on every edited script.

### Phase 5 — Verify, evidence, push (one batched push)

- [ ] T5.0 Ratchets, before every push: `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh` then run each by name; `bash scripts/test-affected-kb-consumers.test.sh` (regenerate with `--write-baseline` only if a knowledge-base file this PR adds changes the baseline); `bash scripts/pre-push-ratchet-lane.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py` (its own default walk) and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation, not a hand-listed path set), and `npx markdownlint-cli2` over the plan and `tasks.md`. `bash scripts/test-all.sh --affected` is refused (rc 4) while a sibling holds the gate: fall back to the named suites and say so in the PR.
- [ ] T5.1 Evidence comment on **#9217**: J finding (artifact lines, the 19/3000 and 11/3000 numbers with their command, verdict real), A2 progress per row (before/after counts with the guard command), the replace-class carve-out with the ADR-100/ADR-169 citations and why the rows are exact-count, and the form decision (F1). Also one line on #7376 (the `*.test.sh` flake class gains this instance) and #6601/#7005 (population per class). No new issue.
- [ ] T5.2 Evidence comment on **#9167**: merge-queue `ci.yml` `e2e` job outcomes, command: `gh run list --workflow ci.yml --event merge_group --limit 60 --json databaseId,createdAt` then `gh run view <id> --json jobs` per run, redirecting stdin from `/dev/null` (a bare `read` loop swallows it). Pre-measured today: before the font-vendoring merge (2026-10-04 00:00 to 2026-10-05 17:38 UTC) 43 merge-group runs, 4 `e2e` failures, 39 success; after it (12 runs) 11 success, 1 cancelled, 0 failure. State that 0/12 is consistent with the fix but not proof (at the prior 9.3% rate the chance of 0/12 is about 31%), that no `Signups not allowed for otp` evidence was found in these (per the 2026-10-05 comment, that string is mock-server noise), and that the issue stays open for the 30-run reassessment. Re-measure at work time; do not reopen the two closed sibling flake issues.
- [ ] T5.3 Learnings (two, under `knowledge-base/project/learnings/test-failures/`, topic names only): (1) which files feed `user_data` with no `ignore_changes` decides whether a "mechanical" edit is a host replace, and the deferral table must say so; (2) J: a source-text pin over a file is a pipe into `grep -q` with a producer longer than a pipe chunk, so a suite that pins its own subject is in the class even when it never touches a stub. The `-c` form rationale lives in the guard header (T1.4), not in a third learning.
- [ ] T5.4 PR body: `Ref #9217`, `Ref #7005`, `Ref #6601`, `Ref #7376`, `Ref #9482`; the T0.2 table; a "Not fixed" section: the 21 replace-class hits (and why), items B, D, E, F, G, H, I (owners), and the accepted gaps (403 secondary rate limit not retried; late run on a congested runner pool not detected).
- [ ] T5.5 `git fetch origin main`, rebase, re-run the guard (`bash .claude/hooks/grep-q-pipe-guard.test.sh`), then ONE push. Mark ready, `gh pr merge --squash --auto`, then `soleur:postmerge`.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Here-string / process substitution everywhere (the brief's wording) | Invalid in `#!/bin/sh`, Terraform `inline` and cloud-init `runcmd`; a here-string turns an empty value into one empty line, flipping `-v` results; used only for the 3 output-bearing `-m1` sites |
| Mark every remaining line `# sigpipe-demo: intentional` | Hides the defect class the guard exists to catch; the marker is for lines that must show the shape (3 sites) |
| Convert the four replace-class files in this PR | Changes `user_data` (ForceNew) on the sole scheduler, the sole pull path and the git-data host; plants a replace for the next full apply and reds the drift check (ADR-100, ADR-169) |
| Keep one broad `apps/web-platform/infra/* \| = \| 21` row for the gated files | A glob can swallow a new production file's hits into slack-free but wrong ownership; file-exact rows make each of the four an explicit, individually reviewable claim |
| Split into two PRs (CI+C, then W) | Declined with reasons in the Split Assessment; kept as the descope valve |
| Fix J by reading `$GEN` once into a variable | Equivalent; F1 is one token and keeps each assertion self-contained |

Deferral tracking: the only deferral (class H, roadmap A3) is tracked by the four rows themselves, each of which names #9217; per the net-issue-flow gate no new issue is filed.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the failure surface is a CI or deploy-pipeline break (a mis-edited `ci-deploy.sh` would stall deploys, a mis-edited workflow step would eject merge-queue entries).
- **If this leaks, the user's data is exposed via:** no exposure vector: the edit rewrites read-only predicate pipelines, adds no secret, log line, network call or permission.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** aggregate-pattern would apply if a host replace were possible; the replace-class files are carved out and AC3 mechanically proves it, so no host replace is queued and a single user cannot be hit.

`threshold: none, reason: the touched infra paths are read-only grep predicates inside deploy scripts and CI steps, behaviour-identical by construction (exit status of grep -c equals grep -q, verified on bash and dash), and the four host-replacing files are not edited.`

## Observability

```yaml
liveness_signal:
  what: the pipe-guard suite runs inside the required CI test jobs on every PR and merge-queue entry; apply-deploy-pipeline-fix.yml reports the deploy-pipeline apply for class W
  cadence: per PR / per merge-queue entry / per push to main touching the trigger files
  alert_target: red required check on the PR; notify-main-failure and main-health-monitor.yml for main
  configured_in: .claude/hooks/grep-q-pipe-guard.test.sh; .github/workflows/apply-deploy-pipeline-fix.yml

error_reporting:
  destination: GitHub Actions workflow run log (layer 6, no Sentry path exists for CI steps)
  fail_loud: "FAIL: pipe-into-early-exit-grep outside the deferral table", "FAIL: deferral ceiling exceeded", "FAIL: stale deferral" from the guard; "::error::" lines from the apply workflow

failure_modes:
  - mode: a new early-exit pipe lands in a zeroed subtree (.github, lefthook.yml, drain prompt, or any non-gated infra file)
    detection: guard prints the file:line list and exits 1 (workflow run log)
    alert_route: required check red on the PR, so it cannot merge
  - mode: one of the four replace-class files is edited, so a host replace is planned
    detection: the exact-count row fails when a hit moves (workflow run log); the infra-validation `plan` job comment shows an hcloud_server replace; scheduled-terraform-drift.yml reports it (workflow run log)
    alert_route: required check red on the PR; the scheduled drift run opens its tracker
  - mode: a converted host script has a syntax or logic slip
    detection: bash -n and ci-deploy.test.sh pre-merge; post-merge the apply-deploy-pipeline-fix workflow run log
    alert_route: red run on main, notify-main-failure
  - mode: the converted pipeline misses where the old one matched
    detection: the owning *.test.sh suite for each file (named per task) plus the parity checks
    alert_route: required check red

logs:
  where: GitHub Actions run logs (gh run view --log)
  retention: 90 days default; the infra suite artefacts 14 days (upload-artifact retention-days: 14)

discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: "PASS: grep-q-zero-sweep-pass"
```

(Check 10 fit, argued rather than waived: the command matches deepen-plan's suite-shaped detection only because the guard lives in a `*.test.sh` file; it is one file, measured at `real 0m2.932s`, well inside the 15 s cap, and its own `PASS:` line is the signal, so no smaller command prints it. First token `bash` is on the probe-verb allowlist, and the command contains no `ssh`.)

## Architecture Decision (ADR/C4)

Not triggered: no ownership boundary, substrate, resolver or trust boundary changes, and no ADR is
reversed. ADR-100 and ADR-169 are read and cited for the carve-out, not amended. C4: the model files
describe actors, systems and containers; this change adds none and touches no access relationship
(checked against `model.c4`, `views.c4`, `spec.c4`: no element is named after a guard, a deferral table or a
CI predicate). The cardinality gate `plugins/soleur/test/c4-count-parity.test.sh` is run in Phase 5 as the
backstop rather than reasoned about.

## Encryption Posture

```yaml
# Not triggered. This change introduces no persistent store and no new cross-component connection:
# it rewrites read-only grep predicates inside existing scripts and CI steps. The `.tf` and cloud-init
# paths in the file list match the detection regex only because inline shell strings sit inside them;
# no resource, volume, bucket, queue, endpoint or TLS setting is added or altered.
at_rest: []
in_transit: []
```

## Guard Contract

### Guard 1 — SWEEP_DEFERRALS table after A2 (zero rows plus four exact-count rows)

**Property.** After this PR, a pipe-fed early-exit `grep` in `.github/**`, `lefthook.yml`, the drain
workflow, or any `apps/web-platform/infra` file other than the four named replace-class files turns the
guard red, and each of those four files is held at its exact count.

**Assembly.** The population is `scan_sweep` (`git grep --no-index --exclude-standard` over
`SWEEP_PATHSPEC`, minus comments and `# sigpipe-demo: intentional` lines) fed to `sweep_verdict`, which
assigns each hit to the FIRST matching row of `SWEEP_DEFERRALS` (bash `[[ == ]]`, where `*` crosses
`/`). Chokepoints, all of which must hold: (a) the table rows and their ORDER (the row
`apps/web-platform/*.test.sh` owns every `.test.sh` under `infra/` because it sits above the infra rows;
the new infra rows must be file-exact so no glob can swallow a production file); (b) the pathspec (so a
new extension or directory is in the population); (c) `PATTERN_V2` (so the rewritten form does not match
itself); (d) the `FILES_*` carve-out; (e) the per-row arithmetic (`=` stale, loose, exceeded). The
probe rows below drive (a), (c) and (e) against the real table, not a synthetic one.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | PERMANENT check. Plant `printf '%s' "$x" \| grep -q p` as real files in a scratch root at `.github/workflows/zz.yml`, `lefthook.yml`, `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js` and `apps/web-platform/infra/zz-new.sh` (plus one file under each existing canary root), run `scan_sweep` on the root (so `SWEEP_PATHSPEC` and `PATTERN_V2` are exercised, not only the verdict) and feed the output to `sweep_verdict` over the REAL table | RED: each of the four paths appears under "outside the deferral table"; a scratch edit adding `':(exclude).github'` to the pathspec turns the check RED (the floor of 1400 has ~260 files of slack, so the floor alone would not) |
| 2 | ONE-OFF (run by hand, recorded in the PR body). Restore a deleted row (add back `.github/* \| = \| 45 \| #9217`) and rerun the real-table probe | RED: row 1's "outside the deferral table" assertion fails because the restored row now owns the planted path (proves the probe reads the real table, not a copy) |
| 3 | ONE-OFF. Add a SECOND hit after a compliant first: `cloud-init-registry.yml` at 14 hits, `cloud-init-inngest.yml` at 5, plus a file with one `grep -cE p >/dev/null` line followed by one `grep -q p` pipe | RED: "ceiling exceeded" for the gated rows; the mixed file reports its one bad line (a check that stops at the first member is itself the defect) |
| 4 | ONE-OFF. Drop one gated row (delete the `cloud-init-git-data.yml` row) with the tree unchanged | RED: its 3 hits fall to "outside the deferral table" |
| 5 | Truncate the population: scratch root with no file under one canary root, floor unchanged | RED (UNRESOLVED, rc 3): the existing canary and floor rows hold, so the guard's own dispatch cannot report "0 checked" and pass. No `.github/` canary is added: `SWEEP_CANARIES` is pinned at 4 and changing it is item F |
| 6 | PERMANENT check. Insert a broad `apps/web-platform/infra/* \| <= \| 99 \| #9217` row BELOW the gated rows (above them it would steal their hits and red the live scan by "stale deferral", masking the assertion under test) | RED: the new assertion that every `<=` row's glob is test-shaped (each glob matches only `*.test.sh`, a `test/` or `tests/` directory, or a `test-*` basename; derived from the real table's rows, not from a sampled list of production paths) fails |
| 7 | ONE-OFF. Raise a gated row's ceiling without a matching hit (e.g. `cloud-init-inngest.yml \| = \| 5`) | RED: "ceiling is loose" (mode `=`) |

This is not an ORDER or LIFETIME property: ownership is first-match-wins and nothing is read across time,
so the reorder hazard (a broad row inserted above the file-exact rows, or the `apps/web-platform/*.test.sh`
row pushed below it) is covered by row 6 rather than by a delete-only row.

**Harness rows (edits to the SUITE, not the guard).**
H1: replace the real table with an empty array inside the new `_vp_real` helper and plant a path that
the real table owns: the helper must report it undeferred (a helper that always returned 0 would pass
the permanent rows vacuously; the existing `vp-negative` control at `:821` is the model, and a second negative
control for `_vp_real` is added). H2: the must-PASS inputs are NOT the canonical: add to
`good-v2.sh` the F1 forms `x | grep -cE p >/dev/null`, `x | grep -cvx p >/dev/null`,
`x | grep -cwF -- "$E" >/dev/null` (bump `V2_GOOD_LINES` from 11 by exactly the number added) and a
`bad-v2.sh` line is NOT changed; this holds the remediation's own text against the classifier
(the #8299 class: the mechanism validated against the tree its remediation produces).
H3: `SWEEP_PROBE_CHECKS` (literal, `:893`) is raised by exactly the number of new
`sweep_probe_fail+=(` checks, and an AC counts them independently.

**Anchor.** The stored values (ceilings, row set) live in the same file the diff edits, so one commit
can weaken both. What sits outside the commit: the merge-base diff of the table that the reviewer reads, and the
guard's own `=` rows plus row 6, which fail when a gated count moves or a
production-shaped glob is made loose. A `>= N` floor survives any
substitution that keeps N, so gated rows are `=` (set identity per file), not `<=`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "THIS branch ships ONLY the first subsystem: item A (Wave A2, infra/CI early-exit pipes: apps/web-platform/infra/\*, .github/\*, lefthook.yml, drain-labeled-backlog.workflow.js" | Phases 2-4 (classes C, CI, W); Phase 1 (guard table) | mapped, except class H: descoped — justification: its edit changes `user_data` (ForceNew, no `ignore_changes`) on the sole scheduler and the sole pull path (ADR-100, ADR-169), planting a host replace for the next full apply; rows kept with reason, roadmap item A3 |
| 2 | "plus lowering/deleting SWEEP_DEFERRALS rows in .claude/hooks/grep-q-pipe-guard.test.sh with mutation-checked rows" | Phase 1 (T1.2-T1.4) | mapped |
| 3 | "Also fold item J (gen-github-egress-cidr.test.sh red on run 37426931446: read artifact log via gh, decide flake vs real; if real and in the infra subtree, fix it here; record the finding on #9217)" | T2.1 (fix), T5.1 (comment) | mapped |
| 4 | "item C evidence comment on #9167 only as evidence comments (no code)" | T5.2 | mapped |
| 5 | "The plan must still contain a short \"Program roadmap\" section listing the remaining items (B, D, E, F, G, H, I)" | Program roadmap | mapped |
| 6 | "Do not duplicate draft #9552 (item H) or draft #9576 (item D)" | Phase 0 T0.1 (re-check, comment), Program roadmap | mapped |
| 7 | "Do not change merge-queue ruleset parameters (infra/github/ruleset-ci-required.tf)" | AC13 (diff does not touch `infra/github/`) | mapped |
| 8 | "Editing scripts/lib/test-affected-paths.sh arms the full battery (~2,900 s per push) ... BATCH PUSHES" | AC12 (file not in diff), Phase 5 one batched push | mapped |
| 9 | "Before every push run every ratchet: `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh`, plus scripts/test-affected-kb-consumers.test.sh" | T5.0 | mapped |
| 10 | "PR bodies use `Ref #N`, never `Closes #9482`" | AC11 | mapped |
| 11 | "a learning per non-obvious finding" | T5.3 (three learnings) | mapped |
| 12 | "Say plainly which items were not fixed." | PR body "Not fixed" section (T5.4) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Class H carve-out rows | ask 1 ("DELETE or lower the row") — the brief assumed every row can go | inferred — justification: converting those files changes `user_data` on hosts with no `ignore_changes`, which plants a host replace in the next full apply and reds the scheduled terraform drift check |
| F1 `-c >/dev/null` default over here-string | ask 1 ("Convert with here-string / process substitution") | inferred — justification: here-string/procsub are invalid in `#!/bin/sh`, Terraform inline and `runcmd`, and a here-string flips empty-input semantics; the guard header already lists `grep -c` as a safe form |
| Real-table owner probe rows and the "no `<=` row owns production-shaped paths" row | ask 2 ("mutation-checked rows") | asked (the second is the header's stated invariant at `:414-416`, currently unenforced; inferred justification: without it a future broad `<=` row re-hides production code) |
| T2.1 fix of the five sites in `gen-github-egress-cidr.test.sh` | ask 3 | asked |
| Lockstep parity edits (`ci-deploy.sh`/`soleur-host-bootstrap.sh`, `pr-quality-guards.yml`/`skill-security-scan-postmerge.yml`) | ask 1 | inferred — justification: `scripts/check-deploy-script-parity.sh` and `scripts/skill-security-scan-step-body.test.sh` fail if one side changes alone |
| Coordination comments on #9529 and #9571 (T0.1) | ask 6 ("Coordinate with them ... comment on the draft") | inferred — justification: ask 6 names #9552 and #9576, which share no file; #9529 shares seven files and #9571 shares `workspaces-luks-verify.yml`, so these are the drafts whose rebase this PR can break |
| One-line evidence comments on #7376, #6601, #7005 (T5.1) | the brief's "Trackers: #9217 (main), also #7005, #6601, #7376" | asked |
| Pin census (Phase 0) | ask 1 | inferred — justification: `ci-deploy.test.sh:9697-9701` pins literal source lines of `ci-deploy.sh` in mutation rows; an edit that ignores the pin turns a mutation into a no-op |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `.github`, `plugins/soleur`, `.claude`, `lefthook.yml` (first-segment roots)
- Planned files: ~48 (23 CI: 18 workflows, 2 `.github/scripts`, `lefthook.yml`, the drain workflow and its SKILL.md; 17 infra: 9 class W, 7 class C, the J test; the guard test; plan, tasks and learnings) | Estimated changed lines: ~170 (one line per hit, plus ~60 in the guard test)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR, split declined with reasons.** The two thresholds exceeded are file count and root count; the failure mode the gate targets (invented scope, 800+ lines) is absent: one mechanical rewrite, ~170 lines, one table edit. The real risk axis is deploy class, not file count, and it is handled by commit order and a descope valve: commits are ordered J, C, CI, then W; if W is blocked (a sibling merge conflict in `ci-deploy.sh`, or a parity gate that cannot be satisfied), ship the first three commits and lower the rows accordingly, moving W to a follow-on "A2b" PR with its 50-hit row intact.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0; output has no `DEFERRED:` line for `.github/*`, `lefthook.yml` or the drain workflow, and exactly four infra lines (13, 4, 3, 1 hits, `mode =`, `slack 0`).
- [ ] AC2 The T0.2 census, re-run at the end, returns 0 hits for every converted path, and exactly 21 for the four gated files.
- [ ] AC3 `git diff --name-only origin/main...HEAD | grep -cE '^apps/web-platform/infra/(cloud-init-(inngest|registry|git-data)\.yml|git-data-bootstrap\.sh)$' || true` prints `0`; the PR's infra-validation `plan` job comment shows no `hcloud_server.*` replace.
- [ ] AC4 `gen-github-egress-cidr.test.sh` has 0 pipe-fed early-exit hits; the 3,000-iteration reproduction of its `:779` assertion prints `miss=0` in both SIGPIPE modes; the suite passes.
- [ ] AC5 Every owning suite named in Phases 2-4 passes, and `scripts/check-deploy-script-parity.test.sh` and `scripts/skill-security-scan-step-body.test.sh` pass.
- [ ] AC6 `SWEEP_PROBE_CHECKS` equals `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -c 'sweep_probe_fail+='` (read its value first: 28 before this PR), and the two permanent real-table checks (mutation rows 1 and 6) were each driven RED once by a scratch edit, the one-off mutations (rows 2, 3, 4, 7) likewise, all recorded as a table in the PR body.
- [ ] AC7 The rewritten forms are held: `good-v2.sh` carries the three F1 fixtures and the guard matches none of them.
- [ ] AC8 Every edited shell script passes `bash -n` (and `sh -n` for the `#!/bin/sh` and inline-`sh` ones); `terraform fmt -check` and `terraform validate` pass in `apps/web-platform/infra`; each edited workflow parses.
- [ ] AC9 All ratchets from T5.0 pass; no ratchet baseline is edited to make a number fit.
- [ ] AC11 The PR closes nothing: `gh pr view <N> --json closingIssuesReferences -q '.closingIssuesReferences | length'` prints `0`, and the body carries `Ref #9217` (asserting the absence of the literal text would false-fail on the body's own prohibition line).
- [ ] AC12 `git diff --name-only origin/main...HEAD | grep -cE '^scripts/(lib/test-affected-paths|test-all)\.sh$' || true` prints `0` (merge-base form, so a sibling merge cannot flip it).
- [ ] AC13 `git diff --name-only origin/main...HEAD | grep -c '^infra/github/' || true` prints `0` (ruleset parameters unchanged), and no ADR file is in the diff.
- [ ] AC14 Evidence comments exist on #9217 and #9167 (URLs in the PR body); three learnings exist.

### Post-merge (automated, run by `soleur:postmerge`)

- [ ] AC15 Post-merge (via `soleur:postmerge`): the `apply-deploy-pipeline-fix.yml` run triggered by the merge SHA concludes `success` (class W), the `apply-web-platform-infra.yml` push run for the same SHA concludes `success` with no `::error::`, the merge-queue and main `ci.yml` runs are green, and `bash .claude/hooks/grep-q-pipe-guard.test.sh` is green on the merged main.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI hygiene, no user-facing
surface, no regulated-data surface: no schema, migration, auth or API route is touched, so the GDPR
gate does not fire). Engineering-internal specialists are covered by the Plan Review panel.

## Test Scenarios

- Given a scratch file `apps/web-platform/infra/zz-new.sh` containing `printf '%s' "$x" | grep -q p`, when `sweep_verdict` runs over the real table, then it reports the path under "outside the deferral table".
- Given `cloud-init-registry.yml` with a 14th hit, when the guard runs, then "ceiling exceeded" names it (mode `=`).
- Given `printf '' | grep -qv x` and its F1 rewrite `printf '' | grep -cv x >/dev/null`, when both run under bash and dash, then both exit 1 (a here-string rewrite exits 0).
- Given the `gen-github-egress-cidr.test.sh:779` pipeline in its F1 form, when run 3,000 times with default and ignored SIGPIPE, then it never misses.
- Given the `_gak_ref_ok` line of `ci-deploy.sh` and its copy in `soleur-host-bootstrap.sh` rewritten identically, when the `GAK_BOTH` rows of `ci-deploy.test.sh` run, then they pass and each mutation still applies; rewritten in only one file, then the battery reports the divergence.
- Given `reusable-release.yml` with a tag list over 64 KiB, when `LATEST_TAG` is computed by the F2 form under `set -o pipefail`, then it is the first matching tag (no producer EPIPE).
- Regression: the guard's named passes (`FILES_7024`, `FILES_8664`, `FILES_8855`, `FILES_7376`) still pass; the existing 28 probe checks still pass.
- **API verify / browser:** none (no external service).
- **Cleanup:** none; no state is written outside the worktree.

## Dependencies & Risks

- **R1 Host replace by accident.** Mitigation: the four files are exact-count rows (AC1), AC3 greps the diff, the PR `plan` job comment must show zero `hcloud_server.*` changes, and `scheduled-terraform-drift.yml` is the later backstop. The per-merge apply does not plan these hosts, so it is NOT a barrier: do not rely on it.
- **R2 Source-text pins.** A rewrite can turn a mutation row into a no-op (`ci-deploy.test.sh:9697-9701`). Mitigation: T0.3 census, T4.1 proves the mutation still applies.
- **R3 Parity pairs edited alone.** Mitigation: lockstep tasks and AC5.
- **R4 Sibling merge conflicts and sibling hits.** #9529 touches seven of the same files; a sibling that adds an early-exit pipe to a zeroed subtree reds the guard until it uses a safe form. Mitigation: T0.1 comments, rebase before push (T5.5), descope valve (Split Assessment). Class W is the piece that slips if #9529 lands first.
- **R5 Merge-queue and CI cost.** `.github/workflows/**` and `apps/web-platform/infra/**` edits arm path-gated batteries (`deploy-script-tests` x4 shards, `infra-validate`, the PR-quality guards); this PR does not edit `scripts/lib/test-affected-paths.sh`, so the ~2,900 s full battery is not armed by it. Mitigation: one batched push.
- **R6 Local blind spot.** `--affected` does not select the guard for `.github/` or `lefthook.yml` edits (the guard's path list at `scripts/lib/test-affected-paths.sh:1415` names `.claude/hooks/`, `plugins/.`, `apps/web-platform/infra/` and four suites). Mitigation: run the guard by name; widening the index is machinery (item H/G territory), not this PR.
- **R7 Post-merge prod effect (class W).** `apply-deploy-pipeline-fix.yml` pushes the new `ci-deploy.sh` and siblings to web hosts over the CF tunnel and the SSH bridge; a mis-edit stalls deploys. Mitigation: `ci-deploy.test.sh`, `bash -n`, the apply run log read by `soleur:postmerge`, and revert-ready single-purpose commits.
- **R9 Cron-egress re-provision on merge.** `cron-egress-*.sh` (`server.tf` cron-egress `triggers_replace`) and `web-private-nic-guard.sh` (hashed into `terraform_data.private_nic_guard_install.triggers_replace`, owning suite `web-private-nic-guard.test.sh`) are hashed into `terraform_data` `triggers_replace`, and `apply-web-platform-infra.yml` fires on any `apps/web-platform/infra/**` merge, so editing them re-runs the nft install and `cron-egress-postapply-assert.sh` on the web hosts. This is the designed path for any edit to those files, not a side effect, but a slip in the 12 converted assertion lines fails the apply. A second consideration: #8945 records that `nft -f` does not replace a ruleset atomically, so the re-install can open a short egress-policy window on the web host while it runs. That is the existing behaviour of every edit to these files, not new, and this PR changes only grep predicates inside the assert script, not the ruleset. Mitigation: `cron-egress-firewall.test.sh`, `cron-egress-self-heal.test.sh`, `cron-egress-nftables.test.sh`, and AC15 reads the apply run.
- **R8 Image-coherence chain.** Editing host scripts moves `host_scripts_content_hash` away from the baked pin used by `web-host-create` until the next release; this is the same effect as every routine edit to these files and is accepted, not mitigated here.
- **Accepted gaps (unchanged):** 403 secondary rate limit not retried; late run on a congested runner pool not detected.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path reason line.
- The guard counts a hit by `PATTERN_V2` on one line: after F1 the line contains `grep -cE ... >/dev/null`; never write `-cm`/`-cq` clusters or the rewritten line re-matches (H2 holds this).
- `*` crosses `/` in the table globs: `apps/web-platform/*.test.sh` already owns every `.test.sh` under `infra/`, which is why J's five hits are lowered from that row, not from an infra row.
- A `.tf` hit is Terraform source, not shell: edit only the shell token inside the string, keep `\"` escapes, and let `terraform fmt -check` prove the string still parses.
- Do not use `[skip-deploy-fix-apply]`: skipping leaves the repo text and the host copy different, and the 12 h drift cron then reds. The merge is the authorization (`apply-deploy-pipeline-fix.yml` header).
- Counts in this plan carry the command that produced them and rot; re-measure before quoting in the PR body.
