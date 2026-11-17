---
title: "feat(engineering): orchestrator-side security scan gate — scan runs and is verified before review seats read the diff"
type: feat
date: 2026-11-10
slug: feat-orchestrator-security-scan-gate
branch: feat-12530-orchestrator-scan-gate
issue: 12530
closes: 12530
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

The review phase can report a diff as security-clean from a seat's own account of a scan. This plan makes the review orchestrator run the deterministic scanner, print a one-line receipt of what it read, and refuse a zero-finding SAST claim when that receipt is missing or shows the scanner did not examine the diff.

## Problem Statement / Motivation

Issue #12530 is open. In `soleur:review`, `security-sentinel` is an always-on LLM review. `semgrep-sast` is a later seat, and only when the diff has source. That seat's own protocol tells it to run semgrep and, on a quiet result, report "0 findings across N files". `ensure-semgrep.sh` only checks that `semgrep --version` runs. Nothing in the orchestrator reads a scan. A skipped scan and a finished scan can look the same in the seat's prose.

The issue names HephaestusNG as the peer that runs a scan before the security-review agent. Its public description does not say it rejects an unread clean result. This plan does not copy that project. The property comes from the hole in `soleur:review` and from in-repo learnings about vacuous cleans.

A blanket stop of `security-sentinel` would also block docs, lockfile, and deletion reviews, where SAST must not run. The gate is the scan receipt. The architectural seat still runs.

## Proposed Solution

Add `plugins/soleur/skills/review/scripts/review-scan-gate.sh`. `plugins/soleur/skills/review/SKILL.md` runs it before every review seat, including the design-validity pass and a `--fix-round` re-entry. The skill passes the path list for the range it is about to judge. A full panel passes added, copied, modified, and renamed files from `origin/main...HEAD`. A fix-round passes the fix range the skill already uses. Deletions are not targets.

The script prints one status line and exits.

```text
SOLEUR_REVIEW_SCAN_GATE <ok|skip|refuse> engine=<semgrep|shellcheck|mixed|none> files=<n> rules=<n> findings=<n>
```

`--probe` also exits 0. The phase continues only when the status token parses as `ok` or `skip`. `refuse` exits 1. `probe` is not a scan. When `findings` is greater than zero, the following stdout lines are `<file>:<line> <rule-id>` and nothing else. No matched source, no secret value, no findings file, no `--json-output`. `files` is the classified source-and-shell target count. A lockfile or a deletion in the list does not increment `files`. A zero-finding claim matches that classified count.

- `engine=semgrep` when the list has source and no shell. `engine=shellcheck` when it is shell only (`.sh`, `.bash`, `.zsh`). `engine=mixed` when it has both. `engine=none` when it has neither.
- `ok` on `semgrep` or `mixed` requires semgrep's own summary line, `Ran N rule on M files` or `Ran N rules on M files`, with N greater than zero, and JSON `paths.scanned` mapped back to the source targets. The 1.181.0 measurement printed the singular (`Ran 1 rule on 2 files`). A substring anywhere in stderr is not that line. A unit fixture whose stderr is `Ran 1 rule on 2 files`, with both targets scanned, receipts `ok`.
- `ok` on `engine=shellcheck` requires shellcheck to have run with every shell target on its argv. A missing binary, or a shell target it did not read, is `refuse`. `rules=0` is legal only after that execution. Printing `ok engine=shellcheck rules=0 findings=0` without running shellcheck is `refuse`. Findings stay `<file>:<line> <rule-id>` and do not stop the phase.
- A target the skill passed and the scanner did not examine is `refuse`. That includes a file omitted from the argv and a `test/` path semgrep skipped. Apply the existing workaround (a directory that holds only those test files, `--no-git-ignore`, an empty `.semgrepignore`). After that copy, `paths.scanned` names the copied paths. Match them to the paths that invocation was given and map them back to the original targets before comparing. String equality against the original `test/` paths refuses every test-directory source review. A scanned set that is still short of those targets is `refuse`. One fixture passes a single `test/` source file and receipts `ok` after the mapping.
- On `io_uring_queue_init: Cannot allocate memory`, retry once with `EIO_BACKEND=posix` and `semgrep -j 1`. A second empty result is `refuse`.
- Call `ensure-semgrep.sh` only on the semgrep path. Do not reimplement install. A failed bootstrap is `refuse`.
- Semgrep configs stay the seat's current set, hardcoded in the script and run from the repo root: `--config=auto`, `--config=p/javascript`, `--config=p/typescript`, `--config=p/owasp-top-ten`, `--config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml`, `--json`, `--error`. Do not add a runtime branch that refuses `p/js` or `p/ts`. Those slugs are unreachable once the script owns the list. A missing config still refuses: semgrep exits 7 and prints no summary.
- `skip` prints `engine=none files=0 rules=0 findings=0`. The panel continues. `skip` does not authorize a SAST-clean claim.
- The phase continues only on a parsed `ok` or `skip`. `probe`, `refuse`, any other token, a non-zero exit, or a missing receipt stops the phase before any seat.
- `findings` greater than zero does not stop the phase. `security-sentinel` still reviews docs, lockfiles, and deletions.
- `semgrep-sast` does not invoke semgrep. On `ok` it reports the receipt and the finding lines. On `skip` it is not spawned.

`--probe` prints `SOLEUR_REVIEW_SCAN_GATE probe` and exits 0 without scanning. That token does not continue the phase.

The skill's prose is not the evidence. The receipt in the script's stdout is the read. The seat's report is commentary on that receipt.

## Technical Considerations

- **Architecture.** This is a trust boundary inside the review skill: who may assert that a scan ran. ADR-324 records it. The C4 model already has the review skill, the founder, and the harnesses that load the plugin. No new actor, vendor, or store.
- **Performance.** One semgrep invocation per source review, plus one shellcheck invocation when the range has shell files. The same work the seat already does, moved earlier. One io_uring retry at most.
- **Security.** Raw scanner JSON stays inside the script's process. Stdout carries the receipt and `file:line` plus rule id. A temp file, if the script needs one to parse JSON, lives outside the worktree and is removed before every return, including `refuse` and a signal. `prepush-secret-scan.sh` is unchanged, including its rule that exit 43 continues.
- **NFR register.** NFR-023 and NFR-024 are Cloudflare, tunnel, and RLS controls on the running platform. This gate does not change them. NFR-039 is container-image scanning. The register entry this work meets is NFR-011 (automated functional testability): a hermetic shell suite drives the receipt.
- **Attack surface.** The ways a review can still assert a clean scan:
  1. `SKILL.md` spawns seats without the script. The suite reads the skill and requires the script to run first.
  2. The script prints `ok` with `files` not equal to the classified source-and-shell count, or without semgrep's own `Ran N rule` or `Ran N rules` summary and a full mapped `paths.scanned`. The suite treats that as `refuse`.
  3. On a fix-round the skill passes `origin/main...HEAD` instead of the fix range it already uses (`PANEL_SHA` / `--since`). The script scans only the argv it is given, so an `ok` on the full range is that wrong list.
  4. `plugins/soleur/skills/review/workflows/review.workflow.js` still lets the seat run semgrep. `workflows/README.md` says the skill is the authority. This plan does not port the gate. The skill does not spend its byte headroom on a sentence that a workflow run is not a review verdict.
  5. A rule pack with N greater than zero that cannot see the language. Accepted residual. The known-bad sample stays out of this gate.
  6. `ensure-semgrep.sh` and `prepush-secret-scan.sh` are different checks. They are not this receipt.
  7. The seat prints `SOLEUR_REVIEW_SCAN_GATE ok` itself. The suite requires the script's own tool result, and a copy of the line in the seat's report does not satisfy it.
  8. A target file contains `Ran 99 rules on 99 files` and semgrep copies file text onto stderr. The rule count is taken from semgrep's summary line only. Writers of that channel are the semgrep process and any file text it quotes. The PR author controls the files.

## Research Insights

**Premise.** The orchestrator does not run semgrep or shellcheck. It proves the semgrep binary can print a version, then trusts the seat.

**Property List.** A zero-finding SAST claim is valid only when the orchestrator's own tool output contains `SOLEUR_REVIEW_SCAN_GATE ok` with `findings=0`, `files` equal to the classified source-and-shell target count, and, for `semgrep` or `mixed`, `rules` greater than zero backed by semgrep's own summary line (`Ran N rule on M files` or `Ran N rules on M files`) and a `paths.scanned` set mapped back to the source targets. For `engine=shellcheck`, shellcheck ran with every shell target on its argv.

**Kept.** One script. One stdout receipt. Fail closed when the receipt is missing, the status token is not `ok` or `skip`, or the scan did not cover the classified targets. Shell-only ranges use shellcheck, and `ok` on that engine requires the binary to have read every shell target. Docs, lockfiles, and deletions skip the scan and still get `security-sentinel`. Findings stay inline and do not stop the phase. No committed scan output. No AGPL source.

**Cut List.** A second semgrep run by the seat. A findings file or a later read-back of one. Any change to the gitleaks 0/43 contract. A new gitleaks runner inside review. An LLM-decided skip. A phase abort on `findings` greater than zero. The known-bad pack control. A port into `review.workflow.js`. Copying HephaestusNG. A ceiling raise for `review/SKILL.md`. Paging every clean review.

**Repo.** `SKILL.md` is the authority. The workflow file is a prototype. `security-sentinel` does not run a scanner. `semgrep-sast` does, after the always-on seats. `fix-round-seats.sh` names seats and does not scan. No `security: clean` token exists. Clean is the seat's "0 findings" sentence or an empty findings list. Gate 2b of the skill continues when any other seat returns.

**Learnings.** A missing semgrep pack exits 7 with findings 0 (`2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`). `Ran N rules on 0 files` is void (`2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md`). Semgrep exit 2 with an empty log is void (`2026-10-29-stopping-one-alert-rule-does-not-stop-the-vendor-default-channel.md`). `command -v` is not a live binary (`test-failures/2026-10-11-a-unit-file-content-pin-must-model-systemds-parser-not-the-files-bytes.md`). An indeterminate result fails closed (`2026-07-24-a-security-gate-detector-nearly-shipped-the-false-green-it-was-built-to-prevent.md`). A count nobody reads does not close the hole (`2026-07-25-i-added-the-field-that-closes-the-gap-and-nothing-read-it.md`). Do not commit findings (`2026-02-16-inline-only-output-for-security-agents.md`). Re-running gitleaks on an allowlisted sample is a fabricated green (`security-issues/2026-07-05-fabricated-green-content-gate-ceiling-and-verification-sentinel.md`).

**Functional discovery.** Nothing in the skill registries implements this receipt. HephaestusNG is AGPL-3.0 and was not read. `wshobson/agents` security-scanning (MIT) and Anthropic `claude-security` (Apache-2.0) configure or tally scanners and do not gate a review verdict on evidence the orchestrator read. They were not installed.

**Measurement.** Semgrep 1.181.0 with an empty rules file, `--json --error`, exited 0, `paths.scanned` was empty, stderr said `Nothing to scan`, and the JSON had no rule-count field. That run did not print a `Ran` summary. The same binary with one rule exited 1 and printed `Ran 1 rule on 2 files` on stderr. A missing `--config` exited 7 and printed no summary. A crash, a signal, or a retry that still has no summary is the same class: `refuse`. Exit 0 is not a scan. JSON alone cannot prove `rules` greater than zero. The CLI reference at `https://docs.semgrep.dev/cli-reference` (retrieved 2026-11-10) matches this: without `--error`, findings still exit 0. Stubs replay these captured shapes, including `Nothing to scan`, not an exit code alone.

## Research Reconciliation

The issue's tool list says semgrep and gitleaks, per the `semgrep-sast` toolset. That seat runs semgrep only. Gitleaks is the ship push preamble. The issue's peer story is stronger than the peer's public description. The receipt is justified by the Soleur hole, the learnings above, and the semgrep measurement, not by a verified competitor behavior.

Best-practices and framework-docs agents were not spawned. The exit-code page and the in-repo learnings already pin vacuous-clean, fail-closed on an indeterminate result, and inline-only output. A restatement would not change the receipt.

## Files to Create

- `plugins/soleur/skills/review/scripts/review-scan-gate.sh` — the scan and the receipt. Emit the status with `echo "` so the drift guard's `SENTINEL_RE` (`echo "` or `printf '`) sees `SOLEUR_REVIEW_SCAN_GATE`. A `printf '%s'` form is invisible to that guard.
- `plugins/soleur/skills/review/test/review-scan-gate.test.sh` — hermetic suite. Stub `semgrep` and `shellcheck` on `PATH`. No network. Written before the script, modeled on `ensure-semgrep.test.sh`. The same directory is already registered: `scripts/test-all.sh` `SUITE_GLOBS` includes `plugins/soleur/skills/*/test/*.test.sh`. Do not add an `AFFECTED_*_PATHS` row. This suite is not a workflow-YAML subject.
- `knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md` — provisional ordinal. Renumber sweeps this plan, the tasks file, and the acceptance criteria if a sibling claims 324.

## Files to Edit

- `plugins/soleur/skills/review/SKILL.md` — replace the seat-runs-semgrep instructions with the script gate. Do not append. Measured 2026-11-10: the file is 475901 bytes and `plugins/soleur/test/skill-body-budget.json` key `review` is 475921, so the headroom is 20 bytes. `scripts/lint-skill-body-budget.py` compares `stat` size with the merge-base ceiling, and this PR does not raise that ceiling. Take the bytes from the step-14 recipe the script now owns (the bootstrap paragraph, the config list, the slug warning, and the seat's own summary-line check) and from the later paragraph that begins "The registry slugs are `p/javascript` / `p/typescript`" and tells the reviewer to trust semgrep's own `Ran N rules` line and to run shellcheck. That paragraph is a second evidence channel. The remaining prose runs the script before any seat, including the design-validity pass and `--fix-round`, continues only on a parsed `ok` or `skip`, stops on `probe`, `refuse`, any other token, a non-zero exit, or a missing receipt, and accepts a zero-finding SAST claim only from the script's own `ok` with `findings=0` and `files` equal to the classified source-and-shell count. The shellcheck seat named by `fix-round-seats.sh` has no agent file. The skill tells that seat to quote the receipt and not invoke shellcheck. Do not spend bytes on a sentence that a `review.workflow.js` run is not a review verdict. If those clauses do not fit, move the retired how-to into `plugins/soleur/skills/review/references/` behind a Read line that fires only on the scan step, and keep the fail-closed clauses in the skill. The post-edit size stays at or under 475921. Do not change the skill's `description:` frontmatter.
- `plugins/soleur/agents/engineering/review/semgrep-sast.md` — change the description and the body. The description today says the caller bootstraps semgrep via `ensure-semgrep.sh` and the agent runs the scan. The seat reports the receipt and the finding lines. It does not invoke semgrep, shellcheck, or the known-bad sample. The cursor and opencode copies of that description are separate files. `plugins/soleur/scripts/sync-grok-agent-compat.ts` does not write them.
- `plugins/soleur/agents/engineering/review/security-sentinel.md` — a zero-finding SAST claim requires the `ok` receipt with `findings=0`. Docs, lockfile, and deletion reviews still run. `skip` is not a clean scan.
- `plugins/soleur/cursor/agents/soleur-engineering-review-semgrep-sast.md` and `plugins/soleur/opencode/agents/engineering/review/semgrep-sast.md` — description sentence only, so the harness no longer says the seat runs semgrep. Bodies that only point at the canonical file stay pointers.
- `plugins/soleur/.claude-plugin/agents.manifest.json` and `.grok/agents/soleur-engineering-review-semgrep-sast.md` — regenerate with `cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts` after the canonical description changes. Do not hand-edit either file. `grok-fidelity-gate.sh` runs that script with `--check`.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — add `SOLEUR_REVIEW_SCAN_GATE` to `MARKER_RE` only, with a MIRRORED-NOT-PAGED comment. The extractor is the agent PostToolUse hook, not a hosted cron's captured stderr. Do not add the marker to `WEDGE_RE`. `ok` and `skip` are the common path and must not page. `refuse` shares the token, so it is mirrored with them, and the review session stays the alert. Land this in the same change as the script's `echo "`.

Do not edit `ensure-semgrep.sh`, `prepush-secret-scan.sh`, `review.workflow.js`, `roadmap.md`, or `plugins/soleur/test/skill-body-budget.json`. Do not hand-edit the generated manifest or the grok agent stub.

## Architecture Decision (ADR/C4)

### ADR

Create ADR-324. Decision: the review orchestrator's stdout receipt is the only evidence the review SAST scan ran. `prepush-secret-scan.sh` remains a separate deterministic scan and is not this receipt. A zero-finding SAST claim requires `SOLEUR_REVIEW_SCAN_GATE ok` with `findings=0` and `files` equal to the classified source-and-shell target count (and, for semgrep or mixed, a non-zero rule count). A missing receipt, a `refuse`, a `probe` token, or any token other than `ok` or `skip` stops the phase before seats. Findings do not stop the phase.

Record the rejected alternatives in the ADR: exit-code-only, a seat-printed marker, a findings file the orchestrator reads later, folding gitleaks into this script, aborting the phase on any finding, the known-bad pack control, and porting the gate into `review.workflow.js`.

The ordinal is provisional until the file is added, and again until merge. Probed 2026-11-10 after `git fetch origin`: 153 `refs/remotes/origin` trees, `git ls-tree` of `knowledge-base/engineering/architecture/decisions/`, highest ordinal 323, `ADR-324` in none. Re-run that probe immediately before creating the file and again before merge. A check of `origin/main` alone does not say whether a sibling branch holds the number.

### C4 views

No C4 edit.

Checked against `model.c4`, `views.c4`, and `spec.c4` on 2026-11-10:

- **Actors.** `founder` already invokes the review skill. `emailSender`, `betaContact`, `contributor`, `publicReader`, and `supportUser` do not send or receive this receipt. No access edge changes. The review component description (panel scales to the risk tier, fix commits get targeted seats, ADR-267) stays true.
- **External systems.** Semgrep is the local CLI the seat already runs, including its existing fetch of public rule packs. This plan adds no vendor, webhook, account, or API. `spec.c4` defines element kinds only.
- **Stores.** No database, bucket, volume, or log sink. A parse temp file outside the worktree is deleted before return.
- **Views.** `platform.plugin.review` is already included in the component view.

`plugins/soleur/test/c4-count-parity.test.sh` passed on this worktree: 13 passed, 0 failed. No embedded cardinality in `model.c4` changes.

### Sequencing

The ADR is true when the script and the skill land. It ships in this change. Status is accepted, not a later issue.

The script's receipt line is the contract. The failing suite comes first, then the script, then the skill and the agent text that read the receipt. `MARKER_RE` lands in the same change as the first `echo "SOLEUR_REVIEW_SCAN_GATE`, because the drift guard walks `skills/*/scripts/*.sh` and a script-only commit reds the webplat shard.

## User-Brand Impact

- **If this lands broken, the user experiences:** a review verdict the founder merges that says the scan was clean when the orchestrator never read a scan, so a vulnerability reaches that founder's customer deployment.
- **If this leaks, the user's source is exposed via:** a committed scanner report, or a session line that includes matched source or a secret value.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one trusted false clean is enough to ship a vulnerability into one customer deployment. That is a single incident, not an aggregate dip in review quality.

CPO sign-off is recorded at plan time (`requires_cpo_signoff: true`). `soleur:engineering:review:user-impact-reviewer` runs at review time because the threshold is `single-user incident`.

No page, badge, certificate, or raw-log UI.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_REVIEW_SCAN_GATE ok|skip|refuse printed to the review session on every run that reaches seat spawn"
  cadence: per review run
  alert_target: "the same review session; refuse stops the phase before seats spawn"
  configured_in: plugins/soleur/skills/review/scripts/review-scan-gate.sh
error_reporting:
  destination: "review session stdout; this gate does not run in the web app and has no Sentry project"
  fail_loud: "SOLEUR_REVIEW_SCAN_GATE refuse and exit 1"
failure_modes:
  - mode: "missing binary, semgrep exit 2 or 7, crash, rules 0 on a semgrep run, paths.scanned short, unreadable output, second io_uring retry still empty"
    detection: "SOLEUR_REVIEW_SCAN_GATE refuse and exit 1"
    alert_route: "review phase stops in that session before any seat"
  - mode: "range has no added or modified source or shell"
    detection: "SOLEUR_REVIEW_SCAN_GATE skip engine=none files=0 rules=0 findings=0"
    alert_route: "session stdout; architectural seats continue; skip is not a SAST-clean claim"
logs:
  where: "review session transcript; raw scanner JSON is not written into the repo"
  retention: "the session transcript's ordinary retention; the raw JSON is not kept"
discoverability_test:
  command: bash plugins/soleur/skills/review/scripts/review-scan-gate.sh --probe
  expected_output: "SOLEUR_REVIEW_SCAN_GATE probe"
```

## Guard Contract

### Guard 1 — review scan receipt

**Property.** A zero-finding SAST claim is valid only when the orchestrator's own tool output contains `SOLEUR_REVIEW_SCAN_GATE ok` with `findings=0`, `files` equal to the classified source-and-shell target count for the range under review, and, for engine `semgrep` or `mixed`, `rules` greater than zero taken from semgrep's own summary line (`Ran N rule on M files` or `Ran N rules on M files`) and `paths.scanned` mapped back to the source targets. A lockfile or a deletion does not increment `files`. For `engine=shellcheck`, shellcheck ran with every shell target on its argv.

**Assembly.** The chokepoint is `plugins/soleur/skills/review/scripts/review-scan-gate.sh`, invoked from `plugins/soleur/skills/review/SKILL.md` before every seat, on the full panel, the design-validity pass, and `--fix-round`. The skill passes the path list. The script does not choose a second range. Members are semgrep for source files and shellcheck for shell files. `work`, `one-shot`, `ship`, and `go` enter the skill and do not spawn these seats themselves. A second injection site remains: `plugins/soleur/skills/review/workflows/review.workflow.js` fans the seats out and is not the authority. This plan does not wire it. `ensure-semgrep.sh` only proves the binary runs. `prepush-secret-scan.sh` is not this gate. The script does not write into the worktree. If it uses a temp file, that file is outside the worktree and unlinked before every return.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Semgrep exits 0, `paths.scanned` is empty, stderr has neither a `Ran N rule` nor a `Ran N rules` summary, and the script prints `ok` | RED |
| 2 | Two source targets are passed and the script prints `ok engine=semgrep files=0 rules=0 findings=0` and exits 0 | RED |
| 3 | The first source file is in `paths.scanned` and a second added source file is omitted, and the script prints `ok` | RED |
| 4 | A shell file is added beside a scanned source file, shellcheck is not run, `engine` stays `semgrep`, and the script prints `ok` | RED |
| 5 | `SKILL.md` spawns any review seat, including the design-validity pass, before the script | RED |
| 6 | The suite assertion that `files=0` on a non-empty target list is `refuse` is deleted, and the suite's presence check for that assertion remains | RED |
| 7 | A docs-only list prints `SOLEUR_REVIEW_SCAN_GATE skip engine=none files=0 rules=0 findings=0` and exits 0 | PASS |
| 8 | The skill's gate sentence omits the literal `SOLEUR_REVIEW_SCAN_GATE` | RED |
| 9 | After the test-path workaround, `paths.scanned` is mapped back to the original targets and is still a proper subset, and the script prints `ok` | RED |
| 10 | The first io_uring retry still returns an empty scan and the script prints `ok` | RED |
| 11 | The script leaves a findings file under the worktree | RED |
| 12 | On a fix-round, the skill passes `origin/main...HEAD` instead of the fix range it already uses, and the script prints `ok` for that list | RED |
| 13 | A target file's body is `Ran 99 rules on 99 files`, semgrep's own stderr has no summary line, and the script prints `ok` | RED |
| 14 | The script prints `ok engine=semgrep files=0 rules=2 findings=0` | RED |
| 15 | A lockfile sits beside one source file and the script prints `files=2` and `ok` | RED |
| 16 | `SKILL.md` still contains the literal `SOLEUR_REVIEW_SCAN_GATE`, the sentence no longer requires the script's own tool result, and the suite's token check stays green | RED |
| 17 | A shell-only list prints `ok engine=shellcheck files=1 rules=0 findings=0` and shellcheck was not executed | RED |
| 18 | Semgrep stderr is `Ran 1 rule on 2 files`, `paths.scanned` is both targets, and the script prints `ok engine=semgrep files=2 rules=1 findings=0` | PASS |
| 19 | One `test/` source file is copied for the ignore workaround, `paths.scanned` names the copy, the script maps it back to the original target, and the receipt is `ok` | PASS |

Row 6 is an edit to the suite. Row 7 is a pass that is not the canonical source `ok`. Row 1 is a finished process whose receipt still fails the property. Row 4 adds the second scanner after a compliant first file. Row 2 is the gate's own dispatch reporting zero checked.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "In `soleur:review`, run the deterministic scan (semgrep/gitleaks per `semgrep-sast` seat's toolset) in the orchestrating step before seat spawn" | `review-scan-gate.sh` run from `review/SKILL.md` before any seat | mapped |
| 2 | "semgrep/gitleaks per `semgrep-sast` seat's toolset" | — | descoped — justification: the semgrep-sast seat runs semgrep only; gitleaks is `prepush-secret-scan.sh`, and the CTO cut any change to its 0/43 contract |
| 3 | "gate `security-sentinel`'s verdict on a read-back of scan output" | a zero-finding SAST claim is valid only from the `ok` receipt with `findings=0` in the script's stdout | mapped |
| 4 | "the check fails closed if they can't be read, so a skipped or silently-lost scan blocks the phase." | `refuse`, exit 1, or a missing receipt stops the phase before seats | mapped |
| 5 | "clean re-implementation" | no HephaestusNG source, prompts, tests, comments, or layout | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `review-scan-gate.sh` | "run the deterministic scan (semgrep/gitleaks per `semgrep-sast` seat's toolset) in the orchestrating step before seat spawn" | asked |
| `review/SKILL.md` | "before seat spawn" | asked |
| `semgrep-sast.md` | "the seat's self-report is the evidence" | asked |
| `security-sentinel.md` | "gate `security-sentinel`'s verdict on a read-back of scan output" | asked |
| `review-scan-gate.test.sh` | — | inferred — justification: the guard contract requires a suite that goes red on a vacuous `ok`, and a script-only change can print `files=0` and exit 0 |
| ADR-324 | — | inferred — justification: the plan changes who may assert a fail-closed scan result, and that decision is recorded with the change |
| cursor and opencode semgrep-sast description lines | — | inferred — justification: those descriptions say the seat runs semgrep, which re-opens the second scan the receipt exists to close |
| canonical `semgrep-sast.md` description | — | inferred — justification: that description says the seat runs semgrep, and the cursor and opencode copies are not the only copy |
| generated grok agent stub and agents manifest | — | inferred — justification: `sync-grok-agent-compat.ts` writes both from the canonical description, and the fidelity check fails when the stub lags |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `knowledge-base`, `apps/web-platform`, `.grok`
- Planned files: 11 | Estimated changed lines: 760
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the fourth root is the generated `.grok/agents` stub, which must land with the canonical description or the fidelity check fails, and the marker registration must land in the same change as the script's first status-line echo

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] `review-scan-gate.sh --probe` prints `SOLEUR_REVIEW_SCAN_GATE probe` and exits 0.
- [ ] The suite asserts, from command order in `review/SKILL.md` and the agent files, that the script runs before any seat, including the design-validity pass and `--fix-round`, and that the skill passes the path list for the range under review.
- [ ] The status line is `SOLEUR_REVIEW_SCAN_GATE <ok|skip|refuse> engine=<semgrep|shellcheck|mixed|none> files=<n> rules=<n> findings=<n>`. `--probe` also exits 0. The phase continues only on a parsed `ok` or `skip`. `probe` is not a scan. `refuse` exits 1. `files` is the classified source-and-shell count, and a lockfile or a deletion does not increment it.
- [ ] The suite asserts that `ok` for `semgrep` or `mixed` requires semgrep's own summary line, `Ran N rule on M files` or `Ran N rules on M files`, with N greater than zero, and `paths.scanned` mapped back to the source targets. `rules=0` is valid only for `engine=shellcheck` after shellcheck ran with every shell target on its argv. A file body that contains that sentence does not supply `rules`.
- [ ] A target missing from the scanner argv or from `paths.scanned` is `refuse`, including a `test/` path still skipped after the existing ignore workaround.
- [ ] One `EIO_BACKEND=posix semgrep -j 1` retry, then `refuse`. `ensure-semgrep.sh` is called only on the semgrep path and is not reimplemented.
- [ ] The suite asserts that `skip` is `engine=none` and all counts 0, the panel continues, and `skip` is not a SAST-clean claim, and that `security-sentinel` still runs for docs, lockfiles, and deletions.
- [ ] The suite asserts that `findings` greater than zero does not stop the phase. Extra stdout lines are `<file>:<line> <rule-id>` only. The worktree gains no findings file.
- [ ] The suite asserts that `semgrep-sast` does not invoke semgrep and that a zero-finding SAST claim is valid only when the receipt is `ok` and `findings=0`.
- [ ] `ensure-semgrep.sh` and `prepush-secret-scan.sh` keep their current contracts, including continue-on-43. `review.workflow.js` is not wired. No HephaestusNG source is added.
- [ ] `review-scan-gate.test.sh` fails on every RED row in Guard 1, passes the docs-only `skip` row, passes the singular `Ran 1 rule on 2 files` fixture, and passes the mapped `test/` source fixture.
- [ ] The ADR file records the receipt decision. `scripts/check-adr-ordinals.sh` exits 0. This change cites that same file, and a second `ADR-324-*.md` makes the checker exit 1. A collision renumbers the file and every citation in this change in that same commit.
- [ ] After the skill edit, `plugins/soleur/skills/review/SKILL.md` is at or under 475921 bytes and its `description:` frontmatter is unchanged.
- [ ] `SOLEUR_REVIEW_SCAN_GATE` is an alternation in `MARKER_RE`, absent from `WEDGE_RE`, with a MIRRORED-NOT-PAGED comment that names the agent PostToolUse hook. `apps/web-platform/test/git-lock-marker-telemetry.test.ts` passes.

## Domain Review

**Domains relevant:** Engineering, Legal

**Brainstorm-recommended specialists:** none — no brainstorm document.

Product was not relevant. The files are a review script, skill text, agent text, and an ADR. The UI-surface glob does not match. No Product/UX Gate subsection.

### Engineering

**Status:** reviewed
**Assessment:** The CTO kept one script and one stdout receipt. `review-scan-gate.sh` runs before every seat and prints `SOLEUR_REVIEW_SCAN_GATE <ok|skip|refuse> engine=<semgrep|shellcheck|mixed|none> files=<n> rules=<n> findings=<n>`. `--probe` also exits 0. The phase continues only on a parsed `ok` or `skip`. `probe` is not a scan. A zero-finding SAST claim requires `ok` with `findings=0` and `files` equal to the classified source-and-shell target count. A lockfile or a deletion does not increment `files`. `ok` on semgrep or mixed requires the stderr summary `Ran N rule` or `Ran N rules` with N greater than zero and `paths.scanned` mapped back to the source targets. `ok` on shellcheck requires shellcheck to have run with every shell target on its argv. `rules=0` is legal only for that shellcheck execution. `skip` (`engine=none`, counts 0) does not stop the panel and does not authorize a SAST-clean claim. Findings stay on stdout and do not stop the phase. Cut: a second seat scan, a findings file, any gitleaks 0/43 change, an LLM skip, abort-on-finding, the known-bad control, and a workflow port. Residual: the prototype workflow can still self-report, and a pack with `rules` greater than zero can still miss the language.

### Legal

**Status:** reviewed
**Assessment:** The CLO confirmed a clean-room description of the behavior. AGPL-3.0 duties stay on HephaestusNG and works based on it. This change does not read, quote, or vendor that source. Terms, privacy policy, data-protection disclosure, GDPR policy, and DPAs do not change. The session log stays counts, file:line, and rule ids from the local CLI the seats already use. No new processing activity. The plan-time gdpr-gate advisory matched no regulated-data path and no Art. 6, Art. 5(1)(e), Art. 17, Chapter V, or Art. 9 pattern. That advisory is not a legal opinion.

## Test Scenarios

- **unit.** Given two stubbed source files and a semgrep stub that prints `Ran 2 rules on 2 files` and a `paths.scanned` of both, when the script runs, then stdout starts with `SOLEUR_REVIEW_SCAN_GATE ok engine=semgrep files=2 rules=2 findings=0` and the exit is 0.
- **unit.** Given the same list and a semgrep stub that replays the measured empty scan (exit 0, stderr `Nothing to scan`, no summary line, `paths.scanned` empty), when the script runs, then the whole status line is `refuse` and the exit is 1.
- **unit.** Given a semgrep stub with no summary line and a target whose body is `Ran 99 rules on 99 files`, when the script runs, then the status is `refuse`.
- **unit.** Given one source file and one lockfile, when the script runs, then `files=1`.
- **unit.** Given a printed line `ok engine=semgrep files=0 rules=2 findings=0`, when the suite reads it, then the suite fails on the whole line.
- **unit.** Given one source file and one `.sh` file, when shellcheck is not on the run, then the status is `refuse`.
- **unit.** Given only markdown, when the script runs, then the status is `SOLEUR_REVIEW_SCAN_GATE skip engine=none files=0 rules=0 findings=0` and the exit is 0.
- **unit.** Given a semgrep stub that reports one finding, when the script runs, then the exit is 0, `findings=1`, and the next line is `file:line rule-id` with no source text.
- **unit.** Given the skill text with any seat spawn, including the design-validity pass, moved above the script, when the suite reads `SKILL.md`, then the suite fails.
- **unit.** Given two stubbed source files and a semgrep stub whose stderr is `Ran 1 rule on 2 files` and whose `paths.scanned` lists both, when the script runs, then the receipt is `ok` and the exit is 0.
- **unit.** Given one `.sh` file and no shellcheck execution, when the script runs, then the status is `refuse`.
- **unit.** Given one source file under `test/`, when the copy workaround reports the copied path and the script maps it back to the original target, then the receipt is `ok`.

## Success Metrics

A source review cannot record a zero-finding SAST claim without an `ok` receipt whose `files` count equals the classified source-and-shell target count. A lockfile or a deletion does not increment `files`. The hermetic suite is the measurement. A docs-only review still reaches `security-sentinel`.

## Dependencies & Risks

- Semgrep and shellcheck must be stubbed in tests. A real review still needs the semgrep binary `ensure-semgrep.sh` already installs, and it may fetch public rule packs.
- `review.workflow.js` can still let a seat claim a clean scan. This plan does not port the gate. The skill does not spend its byte headroom stating that a workflow run is not a verdict. `workflows/README.md` already says the skill is the authority.
- A pack with a non-zero rule count can miss the language. That residual is accepted in this change and written into ADR-324.
- ADR-324 may collide with a sibling after this probe. The 2026-11-10 fetch showed it free across 153 origin refs, highest ordinal 323. Re-check every origin ref before the file is added and again before merge, and move this plan's citations with a renumber.
- `review/SKILL.md` has 20 bytes of headroom under its ceiling. An appended paragraph fails `lint-skill-body-budget.py` and a later compression can drop a fail-closed clause while the marker token survives. The edit replaces the retired recipe.
- The probe command was run on 2026-11-10 before the script existed and exited 127. The acceptance check is the same command after the file lands.
- A foreign `test-all.sh` is already running in another worktree. This change's fast suite is `review-scan-gate.test.sh`. Do not start a second full `test-all.sh`. The webplat marker test is a separate fast check and is not that full battery.

## References & Research

- Issue #12530, draft PR #12566, branch `feat-12530-orchestrator-scan-gate`.
- `plugins/soleur/skills/review/SKILL.md` change-classification and semgrep gate.
- `plugins/soleur/agents/engineering/review/semgrep-sast.md` execution protocol.
- `plugins/soleur/skills/review/scripts/ensure-semgrep.sh`.
- `plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh`.
- `plugins/soleur/skills/review/workflows/README.md` (skill is the authority).
- Semgrep CLI reference: `https://docs.semgrep.dev/cli-reference`.
- CPO sign-off: single-user incident stands. CLO: no document update, no new processing activity. CTO: script plus one receipt.
