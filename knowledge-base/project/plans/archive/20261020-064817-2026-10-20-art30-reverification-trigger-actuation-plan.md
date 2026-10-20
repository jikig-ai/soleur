---
title: "legal(gdpr): a closed Art. 30 re-verification trigger list has no mechanical actuation — Art. 5(2) defect in the control"
type: fix
date: 2026-10-20
slug: art30-reverification-trigger-actuation
branch: feat-7893-art30-trigger-actuation
issue: 7893
priority: p2-medium
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# legal(gdpr): a closed Art. 30 re-verification trigger list has no mechanical actuation — Art. 5(2) defect in the control

This plan closes no issue. The implementation pull request tracks #7893 and must not use a GitHub closing keyword for it. Detail level is MORE.

## Overview

The first slice makes re-verification triggers 2, 4, and 5 fail a pull request when an in-scope anchor moves and the same diff does not add a dated review hunk in the Article 30 compliance register PA-8 section (f) cell. Triggers 1, 3, 6, and 7 stay class unactuated on open issue 7893, and the compliance-posture row stays open. The check is one new script plus one machine-readable manifest, invoked as a new step of the already-required `enforce` job. The review words are the whitespace tokens POSIX `diff` marks added on that one-line cell. A bold id counts only when `diff` marks that token added. The manifest is the hit predicate. The script refuses a manifest that is not the approved shape, so a manifest edit cannot authorize its own narrowing. Numbered enumerations stay equal on the id set {1..7}. The review hunk is a shape check. It does not grade the legal conclusion.

CPO sign-off required at plan time before work begins. The product assessment in the 2026-10-20 brainstorm is that sign-off. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Research Insights

### Premise Validation

Checked 2026-10-20 before the research fan-out. Issue #7893 is OPEN. Pull request #7881 is MERGED at 2026-09-07T17:18:39Z, so the prose repair is landed and the residual is missing actuation. Issue #7892 is OPEN and stays a separate tracker. Issue #10623 is OPEN and does not carry triggers 1, 3, 6, or 7. Issue #6474 is CLOSED. The compliance-posture Active Items cell still describes the control as prose with no mechanical actuation and still points at #7893. That row is not edited. Cited paths exist: `apps/web-platform/infra/cloud-init.yml`, `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/journald-soleur.conf`, and `scripts/lint-legal-registers.sh`. No UI claim. ADR-026 rejects auto-write of legal conclusions and keeps the gdpr-gate skill advisory. This slice does not auto-write a conclusion and does not turn that skill into a verdict. ADR-032 records `enforce` as an accepted required check. No ADR rejected-alternatives table rejects a born-blocking diff of the two app-container files plus `journald-soleur.conf`. The network-outage gate does not apply. Stack signatures found no flutter, rust, elixir, go, swift, kotlin, or php project, so community agent-finder was skipped.

### Property List

1. A pull request that changes an in-scope app-container log flag in `apps/web-platform/infra/cloud-init.yml` or `apps/web-platform/infra/ci-deploy.sh`, or any change of `apps/web-platform/infra/journald-soleur.conf`, fails unless the same diff adds whitespace tokens on the PA-8 section (f) cell that POSIX `diff` marks as added: a new ISO date, every fired id, and a letter-word. A bold id counts only when `diff` marks that token added.
2. The seven ids cannot disappear from either numbered enumeration without the check failing. The prose check is id-set equality of {1..7} only.
3. The check's claim stays partial. It does not mark triggers 1, 3, 6, or 7 actuated and it does not close #7893.
4. One manifest is the predicate the diff walker executes. A manifest that drops a watched site, points trigger 2 or 4 at `daemon.json`, changes a token-to-id group, or marks 1, 3, 6, or 7 actuated fails even when a review hunk is present.

### Cut List

- Vendor poll and calendar cron. They would buy properties for triggers 6, 7, and 1. Those triggers stay on open #7893. No existing writer amends PA-8 on a schedule.
- Parsing runbook or register prose as the hit predicate. The two copies disagree on items 3 and 4. Id-set equality is the only prose check.
- Advisory-then-promote. Advisory-to-blocking has not happened in this repo. The check is born blocking.
- Extending `scripts/lint-legal-registers.sh` or the other legal-corpus linters named in the spec. Those predicates are register integrity, not this anchor diff.
- Adding these anchors to the DSAR `surface_patterns` list inside `enforce`. That list stays the DSAR list.
- A new ruleset context. It is not branch-required until `apply-github-infra.yml` applies after merge. The blocking producer is a new step on the existing `enforce` job.
- Watching all of `ci-deploy.sh`, zot in `cloud-init-registry.yml`, `egress-gateway-bootstrap.sh`, `vector.toml`, or every `--log-driver` in the repo.
- Replacing `apps/web-platform/infra/lib/docker-run-tuple.py` or `apps/web-platform/infra/journald-config.test.sh`. They pin current values. Updating the pin in the same pull request goes green without a PA-8 hunk, so they do not buy the review property.
- A repo-wide grammar denylist.
- Auto-writing the review entry, marking FIRED, or advancing next due.
- A third prose copy of the trigger sentences. compliance-posture stays numbered and is not edited.
- Calling the closed list actuated, or closing #7893, on this slice.
- Enrolling the 2026-12-07 re-assess in the follow-through sweeper. That date stays on the issue. The sweeper is the wrong shape.

### Research Reconciliation

| Spec claim | Reality | Plan response |
|---|---|---|
| Nothing fails when an anchor changes without a dated review entry | `docker-run-tuple.py` rejects a `--log-driver` outside `{journald}` and treats `--log-opt` as an unknown option. `journald-config.test.sh` pins `SystemMaxUse=1G`, `SystemKeepFree=2G`, and `RuntimeMaxUse=200M`. Neither demands a PA-8 hunk. A pull request that updates the pin goes green. A comment-only edit of `journald-soleur.conf` passes the pin suite. | Keep both pins. The new script is the review-hunk gate. It fires on any diff of `journald-soleur.conf`, including a comment. |
| `legal_resolve_base` hard-fails an empty `MERGE_GROUP_BASE_SHA` | An empty value fails the `-n` test and falls through. The hard failure lives in the `enforce` step and exits 1. Other undecidable bases exit 2 from the resolver. | The new step exits 1 when `EVENT_NAME` is `merge_group` and the base SHA is empty, then calls `legal_resolve_base` and maps any other non-zero to exit 2. |
| A new required check needs its own ruleset context on day one | A new context string is not live-required until Terraform apply. `enforce` is already required. Bot synthetic greens for `enforce` can only be earned for `knowledge-base/project/weakness-digest.md`. | A new step of `enforce`, after the legal-doc step and the backstop step. No new name in `scripts/required-checks.txt`, the canonical JSON, or `infra/github/ruleset-ci-required.tf`. No `if:` on the job or the step. |
| No machine-readable copy of the trigger list exists | Confirmed. The phrase is only in Markdown. | New manifest `knowledge-base/legal/art30-reverification-triggers.yml`. |
| The two prose copies disagree on items 3 and 4 | Confirmed. Runbook item 3 is shipper introduction. The register item 3 is any change to `vector.toml`. Runbook item 4 names the three CLI flags. Register item 4 is a restart-policy change affecting the log path. | Id-set equality only. The gate does not pick item 3's predicate. |

### Institutional learnings the plan honors

- Watch both app-container files. `cloud-init.yml` runs at host birth. `ci-deploy.sh` starts the live container. Sibling `--log-driver journald` invocations that this slice does not watch, confirmed in tree: `apps/web-platform/infra/cloud-init-registry.yml` (zot) and `apps/web-platform/infra/egress-gateway-bootstrap.sh`. Comments in `soleur-host-bootstrap.sh` are not invocations.
- Born blocking. A skipped job reports success on a required check.
- Id-set equality is a closed curated check, not a crawl of every log flag.
- The manifest is not an integrity hash of itself. The script's approved shape is what makes a narrowing fail. The merge-base copy cannot do that on the birth pull request, because there is no parent manifest.
- Comment lines whose first non-whitespace character is `#` do not match flags. The review note is not added to `cloud-init.yml`.
- The register locator is PA-8 and `(f)` together. Bold markers `**(1)**` through `**(7)**` appear once each in that cell. Bare parentheses do not count. Runbook ids are the `1.` through `7.` markers under `### Re-verification triggers`.
- The PA-8 (f) cell is one physical line and already contains bold ids 1 through 7 and existing ISO dates. Line-level added-minus-removed treats that whole line as new. Net-new tokens are the whitespace-delimited words POSIX `diff` marks added. The date token must occur zero times on the removed side. A pre-existing bold id does not satisfy a fired id. One added token must contain a letter and must not be a date.
- Malformed, missing, or unparseable manifest exits 1. The script does not print success for an empty decision.
- Fixtures are synthesized git repositories. The must-pass fixture is not a copy of the live infra files.

### External research

Data privacy is in scope, so external sources were checked. None of them changes the ruled design. A same-change human note is how the record is updated. A machine check that the note is present and dated is not the Article 5(2) demonstration.

- CNIL, Le registre des activités de traitement, <https://www.cnil.fr/fr/RGPD-le-registre-des-activites-de-traitement> — a change to retention conditions is written into the register by the controller.
- CNIL, Les durées de conservation des données, 2 April 2026, <https://www.cnil.fr/fr/passer-laction/les-durees-de-conservation-des-donnees> — a departure from a recommended period is the controller's documented choice.
- ICO, Guide to accountability and governance, <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/accountability-and-governance/guide-to-accountability-and-governance/> — document what changed and why. Accountability is not a box-ticking exercise.
- ICO, Storage limitation, <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/data-protection-principles/a-guide-to-the-data-protection-principles/storage-limitation/> — an automated system may flag records for review. The justification stays with the controller.
- EDPB-EDPS Joint Opinion 01/2025, 8 July 2025, paragraph 18, <https://www.edpb.europa.eu/system/files/2025-07/edpb_edps_jointopinion_202501_proposalsimplification_en.pdf> — the record of processing is a means to demonstrate compliance under the accountability principle.

GitHub's current docs: on `merge_group`, the base commit is `github.event.merge_group.base_sha`. A skipped required check reports success. The diff of files a pull request introduces is three-dot (`git diff A...B`). Source: <https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks> and <https://docs.github.com/en/pull-requests/reference/branches>.

Functional discovery found no community skill that can stand in for this in-repo check. Nothing was installed.

### Conventions

Shell scripts in this lane use `set -euo pipefail`. A step that reads `$?` clears errexit around that read, or the error line never runs. `::error::` names a cause the script measured: the watched path and the fired ids on a fire, or the resolver or diff failure on those paths. It does not echo a diff line or other file text. The script strips CR and LF from the annotation text before printing it. Fixtures follow `cq-test-fixtures-synthesized-only`. "Register" in this plan means `knowledge-base/legal/article-30-register.md`. "Re-verification trigger" means one numbered item on the closed list.

## Problem Statement / Motivation

PA-8 section (f) recorded a container log-retention mechanism the app container stopped using on 2026-06-02. The prose was corrected on 2026-09-07. The control was not. Every re-verification trigger is still a paragraph plus a register cell, so an anchor can move with no dated review entry and nothing fails. Trigger 2 used to watch the `daemon.json` block, so the `docker run --log-driver` change could not fire. Trigger 4 covered that change in principle and was marked FIRED only on 2026-09-06. The published privacy policy carried the old retention account until the prose repair.

The product outcome is still the whole closed list, including triggers 1, 3, 6, and 7, and the published retention sentences. This pull request is allowed to land first only while #7893 and the posture row stay open and the slice is not called done.

## Proposed Solution

Add `scripts/lint-art30-reverification.sh` and `knowledge-base/legal/art30-reverification-triggers.yml`. Invoke the script as a new step of the `enforce` job in `.github/workflows/pr-quality-guards.yml`, after the legal-doc step and the backstop step. Register only the unit suite in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`. Add one pointer sentence to the runbook section `### Re-verification triggers`. Do not edit the register's trigger sentences, the compliance-posture row, the DSAR `surface_patterns` array, or the value-pin suites.

The manifest is YAML with ids {1, 2, 3, 4, 5, 6, 7}. Ids 1, 3, 6, and 7 are class `unactuated` and carry no tokens. One `path-token` site lists exactly `apps/web-platform/infra/cloud-init.yml` and `apps/web-platform/infra/ci-deploy.sh`. Its groups are `--log-driver` and `--log-opt` firing {2, 4}, and `--restart` firing {4}. One `file` site lists exactly `apps/web-platform/infra/journald-soleur.conf` and fires {5}. The script rejects any other shape, including a path that contains `daemon.json`, a dropped path, an extra path, or an actuated class on 1, 3, 6, or 7. That rejection stands when a review hunk is also present. The diff walker reads tokens and paths from the manifest only. It does not parse the runbook or the register to decide which line fires.

The script:

1. Uses `set -euo pipefail`.
2. If `${EVENT_NAME:-}` is `merge_group` and `${MERGE_GROUP_BASE_SHA:-}` is empty, prints `::error::` and exits 1. It does not skip. An unset variable is not an empty merge-group base. Under `set -u`, a bare `$EVENT_NAME` on a unit row that does not export it aborts before this test.
3. Sources `scripts/lib/legal-base-ref.sh` and calls `legal_resolve_base` with an empty explicit argument. Capture the status in the main shell the way `scripts/lint-legal-scope-block-placement.sh` does: set `base_rc=0` first, then `base_out=$(legal_resolve_base "") || base_rc=$?`. The initializer is required. Under `set -u`, an unset `base_rc` makes `(( base_rc != 0 ))` fail before a resolved base can exit 0. Do not use `local var=$(...)`, which can hide a non-zero status under `set -e`. Any non-zero exits 2. Split the tab-separated fields. `MERGE_BASE` is the second field. An empty second field exits 2. An empty argument lets a pull request use `GITHUB_BASE_REF` (the function prefixes `origin/`) and a merge group use `MERGE_GROUP_BASE_SHA`. Do not pass the legal-doc step's bare `BASE_REF`: that value has no `origin/` prefix, and this job's checkout has `origin/main` and no local `main`. It does not source `scripts/lib/legal-normalise.sh`.
4. Diffs with `git diff --no-ext-diff --no-color "${MERGE_BASE}"...HEAD` (three-dot) and does not pass `--exit-code`. Plain `git diff` returns 0 when it prints a diff. A non-zero status exits 2 before any filter. Capture a filter status in the main shell (`filter_rc=0; … || filter_rc=$?`). An unguarded `grep` that exits 1 aborts the script under `set -e`, so a non-flag edit could not pass. A filter status of 1 is an empty fire only after `git diff` itself returned 0 and no binary line matched. Do not map that 1 to script exit 1 or 2. A binary report is a line of that diff that begins with the words Binary files, then a space, and ends with a space and the word differ. The paths sit between those words, and the prefixes are not stable. `grep -F 'Binary files differ'` does not match. Measured 2026-10-20 on git 2.56.0: a NUL in a watched file makes `git diff` exit 0 and print `Binary files i/flag.sh and w/flag.sh differ`. That line exits 1 before the empty-fire branch. `--no-ext-diff` stops a `diff.external` driver from replacing the body and exiting 0.
5. Parses the manifest once with a loader that rejects duplicate keys. The shape check and the diff walker both use that parsed document. A comment that names a path is not a path. A last-key-wins load is a failure. A duplicate key is still a failure when the last value is the approved shape, because a shape check of the effective document would not see it. Exits 1 when the manifest is missing, unparseable, or not the approved shape. The approved shape includes the token-to-id groups: `--log-driver` and `--log-opt` fire {2, 4}, `--restart` fires {4}, and `journald-soleur.conf` fires {5}.
6. Collects runbook ids from lines matching `^[0-9]+\.` under `### Re-verification triggers` until the next `###` heading. The pointer sentence is not an id line. The suite asserts that exact sentence on its own. Deleting it does not fail the id census. Collects register ids from bold `**(N)**` markers inside the PA-8 `(f) Retention` cell only, from `## Processing Activity 8 — Operational Telemetry` until `## Processing Activity 9`. Bare `(N)` does not count. The three sets must equal {1, 2, 3, 4, 5, 6, 7}. A missing section exits 1.
7. Compares the merge-base blob of each path-token file with the HEAD blob and reads added and removed line text from that comparison. A removed `--log-driver` line is content. In unified diff it is displayed as `---log-driver` with no space after the third dash, so a parser must not treat every `^---` line as a file header. A header is `---` or `+++` followed by a space. One fixture deletes a non-comment `--log-driver` line and expects exit 1. Ignores a line whose first non-whitespace character is `#`. Matches a CLI token only when `--log-driver`, `--log-opt`, or `--restart` is bounded on the left by start, whitespace, or a single `'` or `"`, and on the right by end, `=`, whitespace, or a single `'` or `"`. `--restart-policy` does not match. `--log-driver` or `--log-opt` adds {2, 4}. `--restart` adds {4}. A `"log-driver"` JSON key does not match.
8. Adds {5} when `git diff --name-status --no-renames "${MERGE_BASE}"...HEAD -- apps/web-platform/infra/journald-soleur.conf` prints any non-empty status row for that path, including `A`, `D`, `M`, and `T`. `M` includes a comment-only change. `D` includes a delete and a rename away. `T` is a regular file replaced by a symlink. Measured 2026-10-20 on git 2.56.0: that replacement prints `T`, and `--no-renames` records a rename-away as `D`. Do not grep a whole-tree name list: a rename lists only the new path there. A pathspec `--name-only` also lists the old path on this git.
9. When the fired set is non-empty, reads the removed text and the added text of the PA-8 `(f)` cell. Split each side on whitespace first, one token per line. Do not diff the cell as a single line: POSIX `diff` is line-based, so a one-line rewrite would mark the whole cell added and the old bold ids would count. Net-new tokens are the words that token-per-line `diff` marks added. Record the status in the main shell: `diff_rc=0; diff "$removed_tokens" "$added_tokens" || diff_rc=$?`. Under `set -e`, an unguarded `diff` that exits 1 aborts before the added tokens are read, so a valid hunk cannot exit 0. Read the added tokens only when `diff_rc` is 1. Exit 2 only when `diff_rc` is 2. Do not treat exit 2 as a clean token list, and do not map exit 1 to script exit 2. Measured 2026-10-20: POSIX `diff` exits 1 when two token files differ, 0 when they match, and 2 when an input file is missing. A reorder that breaks alignment can mark a bold id that was already in the cell as added. That pass stays green. It is the ruled algorithm. Do not switch to set subtraction. One added token must match an ISO date, and that exact date string must occur zero times in the removed cell text, including when the date is only a substring of another token. Each fired id must appear inside an added token as a decimal bounded by non-digits. A pre-existing `**(N)**` that `diff` aligns to the removed line does not count. One added token must contain a letter and must not be a date token. Otherwise exit 1. A date-only bump fails. A fixture where `diff` exits 2 expects script exit 2.
10. When the fired set is empty, exits 0 after the shape and id-set checks. The birth pull request, which adds the manifest and does not change an anchor, passes without a review hunk.
11. Writes nothing, reads no log body, does not open `docs/legal/`, and does not call a vendor API. Every `::error::` annotation names a measured cause only: the watched path and the fired ids on a fire, or the resolver or diff failure on those paths. It does not echo a diff line or other file text. The script strips CR and LF from the annotation text before printing it, because a newline inside the annotation can forge a later workflow command.

The runbook pointer, which does not restate item predicates and does not choose item 3, is: `The check executes knowledge-base/legal/art30-reverification-triggers.yml. This list stays numbered 1 through 7. That file is the predicate.`

### Implementation sequence

1. Write `scripts/lint-art30-reverification.test.sh` first. The suite fails because the script does not exist yet.
2. Add the script, the manifest, the `enforce` step, and the `run_suite` registration until the suite passes.
3. Add the runbook pointer sentence. Confirm id-set equality still passes on the real tree via the unit fixture's census of the marker lines, not by copying the legal cell into the fixture.

## Files to Create

- `scripts/lint-art30-reverification.sh` — the check.
- `scripts/lint-art30-reverification.test.sh` — synthesized-repo mutation battery.
- `knowledge-base/legal/art30-reverification-triggers.yml` — the hit predicate.

## Files to Edit

- `.github/workflows/pr-quality-guards.yml` — a new step on job `enforce`, after the legal-doc step and the backstop step. Do not insert this check into the legal-doc `run:` block: that block exits 0 when no DSAR surface is touched. No `if:` on the job or the new step. Set `EVENT_NAME` and `MERGE_GROUP_BASE_SHA` in the step env. The script calls `legal_resolve_base` with an empty explicit argument. Do not add paths to `surface_patterns`.
- `scripts/test-all.sh` — one `run_suite` for the unit test, beside the legal-scope-block unit registration. Do not add a live `run_suite` of the script against the real tree. That run would use `origin/main` inside `test-scripts`, which does not export `MERGE_GROUP_BASE_SHA`, and would be a second producer with a different base.
- `scripts/lib/test-affected-paths.sh` — register the new suite the same way `scripts/lint-legal-scope-block-placement-unit` is registered.
- `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md` — the pointer sentence under `### Re-verification triggers`. The numbered items stay as written.

## Technical Considerations

- The blocking chokepoint is the `enforce` step. The unit suite proves the script. `docker-run-tuple.py` and `journald-config.test.sh` stay as value pins and are not this chokepoint.
- `scripts/lint-orphan-test-suites.sh` `REQUIRED_RUNNERS` is the live-corpus list. This script is not added there. A live `run_suite` from `test-scripts` would diff `origin/main` and would be a second producer. The unit file is registered, so an unregistered `*.test.sh` is still an orphan. Row 23 of the matrix is what goes red if the workflow step disappears.
- Spec-flow on 2026-10-20 named eight edges. The one-line cell uses the CTO token diff, not set subtraction. The deleted-flag display, the rename pathspec, the binary-diff fail-closed, the main-shell resolver capture, the empty `legal_resolve_base` argument, the quote boundary, and the single parsed manifest are in the script steps above. Empty merge-group base, birth pull request, and comment-stripping were already closed.
- Advisor consult on 2026-10-20 (semantic tier `advisor`). Applied: split the cell into tokens before `diff`, so a one-line rewrite is not treated as entirely new, and detect trigger 5 with pathspec `--name-status --no-renames`. Not applied: replacing the token diff with set subtraction. The CTO had just confirmed token-per-line `diff`, and a pathspec name-only diff of a rename was measured non-empty on git 2.56.0.
- Bot pull requests that receive a synthetic green `enforce` may stage only `knowledge-base/project/weakness-digest.md`. That path is disjoint from the manifest, the register, the runbook, and the three infra files.
- A pull request can still edit the script and the suite together. The merge verdict is then consistency of that pair, not an external seal. The harness row below makes an `exit 0` stub fail the suite. It cannot stop a pull request that rewrites both.
- Item 2's runbook sentence still says the flag fires at three sites. The gate watches two files, and `ci-deploy.sh` contains two invocations. A new file that launches `soleur-web-platform` with `--log-driver journald` will not fire. The unwatched launcher, the zot invocation in `apps/web-platform/infra/cloud-init-registry.yml`, and the egress-gateway invocation in `apps/web-platform/infra/egress-gateway-bootstrap.sh` stay on open #7893. That is a ruled remainder of the closed list, not a dropped second entry. The brand-survival threshold stays `single-user incident`. This slice does not widen the gate to those files and it does not crawl the repo.
- A comment-stripped match inside the two watched files can fire on a later non-app `--restart` in those files.
- Id-set equality stays green when both enumerations share the same wrong anchor. That is why it is the closure check only.
- The human entry still carries the date of this review, who reviewed and in what role, which id fired and which anchor moved, the retention-relevant before and after (including whether the published privacy-policy retention sentences still match), the Art. 30(1)(f) conclusion, and whether the cell was amended or confirmed. The script does not search for those clauses.
- NFR register: no new store, credential, vendor, or runtime process. No NFR row changes. The failure signal is a red `enforce` check on the pull request.
- No SKILL.md `description:` edit, so the skill-description budget check does not apply.
- No new infrastructure, so there is no Terraform change and no host apply. Merging this pull request alone does not mutate production hosts. The birth diff does not edit `cloud-init.yml`, `ci-deploy.sh`, `journald-soleur.conf`, or a workflow that runs `terraform apply`. The implementation pull request's first body line states that.
- The gate fails a pull-request diff. `--log-driver` lines already on main are not a diff, so there is nothing to grandfather.
- A syntax check of `.github/workflows/pr-quality-guards.yml` uses `actionlint`. `bash -n` is not a check of YAML. `bash -n` applies only to an extracted `run:` snippet.
- No new persistent store and no new network connection, so there is no encryption-posture block.
- No production server, infra, or plugin-script path is edited. The formal observability block is not required. Discoverability of this control is the `enforce` check on the pull request.
- No ownership, tenancy, substrate, or C4 actor changes. An engineer reading the existing ADRs is not misled: ADR-026 stays an advisory skill, and this script is a different check. No ADR and no C4 edit.

### Attack surface

The script's only inputs are the git diff, the manifest, and the two enumeration texts. It does not receive log lines, request bodies, or vendor payloads. The unchecked siblings are the zot invocation and the egress-gateway invocation, recorded above as out of this slice, not as a silent miss inside the watched files.

## User-Brand Impact

- **Artifact:** the Article 30 compliance register's PA-8 section (f) re-verification control, and the published privacy-policy retention sentences a data subject reads (`docs/legal/privacy-policy.md`, the operational-log retention bullet that states journald `SystemMaxUse=1G` and Better Stack 90 days).
- **Vector:** silent failure. The statutory record and the published policy can show a log-retention mechanism the product no longer uses, so one data subject, a regulator, or the operator relies on a false account.
- **If this lands broken, the user experiences:** a privacy-policy retention sentence, and the Article 30 cell behind it, that describe a log-retention mechanism the running container no longer uses.
- **If this leaks, the user's data is exposed via:** no new collection. The harm is a false retention account. The gate reads git diffs of named config files. It does not read log bodies.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one data subject shown a false retention period is enough. The historical miss (#4786, 2026-06-02, corrected 2026-09-07) left the published sentences wrong for about three months.

## Guard Contract

### Guard 1 — Art. 30 re-verification triggers 2, 4, and 5

**Property.** A pull request that changes an approved app-container log flag in the two named files, or any change of `journald-soleur.conf`, is rejected unless the whitespace tokens POSIX `diff` marks added inside the PA-8 section (f) cell contain a new ISO date, every fired id, and a letter-word. A bold id counts only when `diff` marks that token added. A reorder that breaks alignment can mark an old bold id added, and that pass stays green. A manifest that narrows the approved shape, including a token-to-id group, is rejected even when those added tokens are present.

**Assembly.** The only blocking producer is a new step of job `enforce` in `.github/workflows/pr-quality-guards.yml`, outside the legal-doc `run:` block. The unit suite is not a second producer. The diff walker executes paths and tokens from `knowledge-base/legal/art30-reverification-triggers.yml` and from nowhere else. The approved shape (the two paths, the token-to-id groups, the journald file, and unactuated ids 1, 3, 6, and 7) lives in the script so the manifest cannot certify a narrower copy of itself. Members of the path-token site are every added or removed non-comment line in those two files. The file-class member is any non-empty status row, including `T`, from `git diff --name-status --no-renames` pathspec'd to `journald-soleur.conf`. The review region is the PA-8 `(f) Retention` cell, not a bare `(f)` and not another processing activity. Net-new tokens are the whitespace-delimited words POSIX `diff` marks added on that cell. `docker-run-tuple.py` and `journald-config.test.sh` are outside this assembly.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a non-comment `--log-opt max-size=1m` line in a synthesized `ci-deploy.sh` and do not add a PA-8 (f) hunk | RED |
| 2 | Replace the script body with `exit 0` and re-run the row-1 fixture through the suite helper | RED |
| 3 | Satisfy row 1 with added tokens for ids 2 and 4, then also touch synthesized `journald-soleur.conf` while the added tokens do not include id 5 | RED |
| 4 | Mark id 1 `actuated` in the manifest and include a hunk that names id 1 with a date and a statement | RED |
| 5 | Drop `ci-deploy.sh` from the manifest paths and include a perfect hunk | RED |
| 6 | Point a path-token path at `daemon.json` | RED |
| 7 | Delete id 7 from the runbook `7.` marker and leave the manifest and the register intact | RED |
| 8 | Remove the bold `**(5)**` marker from a synthesized PA-8 (f) cell | RED |
| 9 | Put the date, the ids, and the statement in a synthesized PA-2 `(f)` cell only | RED |
| 10 | Rewrite the PA-8 (f) line so the only new ISO date already occurs in the removed cell text, including as a substring of another token | RED |
| 11 | Add a date and the fired ids with no further word | RED |
| 12 | Fire `--restart` alone and name only id 2 in the hunk | RED |
| 13 | Omit the manifest file | RED |
| 14 | Feed the script unparseable YAML | RED |
| 15 | Set `EVENT_NAME=merge_group` and an empty `MERGE_GROUP_BASE_SHA` | RED exit 1 |
| 16 | Make `legal_resolve_base` unable to resolve and confirm the script exits 2 rather than 0 | RED |
| 17 | Add a comment line whose first non-whitespace character is `#` and whose text contains `--log-driver journald` | PASS |
| 18 | Change the `"log-driver": "json-file"` key inside a synthesized daemon.json block and change no CLI flag | PASS |
| 19 | Change a non-flag line in synthesized `cloud-init.yml` | PASS |
| 20 | Change only a comment in synthesized `journald-soleur.conf` and add a hunk that names id 5 with a new date and a statement | PASS |
| 21 | Birth-shaped diff: add a valid manifest and the script, change no anchor, add no review hunk | PASS |
| 22 | Fire `--log-driver` and append a new date token, id tokens 2 and 4, and a letter-word | PASS |
| 23 | Remove the script invocation from a synthesized copy of the workflow step and run the dispatch assertion | RED |
| 24 | Start from a synthesized (f) cell that already contains bold ids 1 through 7, an old ISO date, and a letter-word, then change only an unrelated token | RED |
| 25 | On that same pre-filled cell, append a new date token, the fired id tokens, and a new letter-word | PASS |
| 26 | Delete a non-comment `--log-driver` line and add no review tokens | RED |
| 27 | Rename `journald-soleur.conf` and add no id-5 token | RED |
| 28 | Put a NUL in a watched flag file and run a real `git diff`. The report begins with the words Binary files, then a space, and ends with a space and the word differ, and `git diff` exits 0 | RED |
| 29 | Give the manifest a duplicate key whose last value drops a watched path, or mention a watched path only in a comment, or give it a duplicate key whose last value is still the approved shape | RED |
| 30 | Make the token-file `diff` exit 2 | RED exit 2 |
| 31 | Delete the exact pointer sentence while leaving the heading and markers `1.` through `7.`. The suite assertion on that sentence fails. The id census stays green | RED |
| 32 | Replace `journald-soleur.conf` with a symlink and add no id-5 token | RED |
| 33 | Keep both paths and leave ids 1, 3, 6, and 7 unactuated, set the `--log-driver` group to fire {4} only, and add a hunk that satisfies that narrowed set | RED |
| 34 | Reorder existing bold ids so `diff` marks an old fired id added, and append a new date and a letter-word, with no new id token | PASS |

**Anchor.** Row 31 is a suite assertion on the exact pointer sentence. It is not the id census. The runbook pin is that sentence, including `That file is the predicate.`, not only the heading `### Re-verification triggers`. The approved shape in the script is what stops one diff from weakening the manifest and the walker together. It is not a hash of the manifest. The unit suite calls the real script on synthesized repositories. A pull request that rewrites the script and the suite in the same commit can still go green. That limit is named here so the slice is not described as an integrity seal. A short cell that does not already contain the bold ids hides the one-line false green. Rows 24 and 25 are the fixture that already contains them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Nothing fails when a trigger's anchor file changes without a corresponding dated review entry." | Guard 1 and `scripts/lint-art30-reverification.sh` | mapped |
| 2 | "The trigger list would need a machine-readable form" | `knowledge-base/legal/art30-reverification-triggers.yml` | mapped |
| 3 | "a gate can fail when a trigger's anchor file changes in a PR without a dated review entry landing in the same PR." | the `enforce` step | mapped |
| 4 | "Every trigger in the list is still prose in a runbook plus a cell in a register, with no mechanical actuation." | partial actuation of triggers 2, 4, and 5; triggers 1, 3, 6, and 7 stay on open #7893 with class unactuated | mapped |
| 5 | "If not fixed by **2026-12-07**, re-assess" | — | descoped — justification: that date is the issue's own re-assess, and this pull request does not enroll a sweeper |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `scripts/lint-art30-reverification.sh` | "Nothing fails when a trigger's anchor file changes without a corresponding dated review entry." | asked |
| `knowledge-base/legal/art30-reverification-triggers.yml` | "The trigger list would need a machine-readable form" | asked |
| `.github/workflows/pr-quality-guards.yml` | "a gate can fail when a trigger's anchor file changes in a PR without a dated review entry landing in the same PR." | asked |
| `scripts/lint-art30-reverification.test.sh` | "Nothing fails when a trigger's anchor file changes without a corresponding dated review entry." | inferred — justification: a guard that cannot be driven red does not buy the asked failure |
| `scripts/test-all.sh` | "a gate can fail when a trigger's anchor file changes in a PR without a dated review entry landing in the same PR." | inferred — justification: an unregistered `*.test.sh` is an orphan and the battery would not run |
| `scripts/lib/test-affected-paths.sh` | "a gate can fail when a trigger's anchor file changes in a PR without a dated review entry landing in the same PR." | inferred — justification: the affected-path map is how the unit suite is selected; omitting it leaves the battery off the path that runs it |
| runbook pointer sentence | "The trigger list would need a machine-readable form" | inferred — justification: without a pointer the prose list stays the only copy a reader executes, which recreates the unactuated control |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `.github`, `knowledge-base`
- Planned files: 7 | Estimated changed lines: 1000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the line estimate crosses 800 because the mutation battery is most of the diff; splitting the battery from the script would ship a check the suite cannot redden

## Open Code-Review Overlap

- #3829 (`pr-quality-guards.yml`, Sentry monitor carve-out). Acknowledge: this plan adds one step to `enforce` and does not change that carve-out.
- #8659 (`scripts/test-all.sh`, EXIT trap composition). Acknowledge: this plan adds one `run_suite` line and does not change trap composition.
- #7942 (`scripts/test-all.sh`, unregistered `*.mutation.sh` batteries). Acknowledge: the new battery is `scripts/lint-art30-reverification.test.sh` and is registered with `run_suite`. It is not a `*.mutation.sh` file.
- #8800 (`scripts/lib/test-affected-paths.sh`, fixture inode sharing). Acknowledge: this plan adds a suite path string and does not change the sandbox fixture.

No open code-review issue names the runbook, the Article 30 compliance register, `cloud-init.yml`, `ci-deploy.sh`, `journald-soleur.conf`, or `scripts/lint-legal-registers.sh`.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations

**Brainstorm-recommended specialists:** none

Marketing, Sales, Finance, and Support were assessed in the brainstorm and omitted. No campaign, pipeline motion, support surface, or new spend.

### Product

**Status:** reviewed
**Assessment:** Carry-forward from the 2026-10-20 brainstorm. Done is the whole closed list, including triggers 1, 6, and 7, and trigger 3 is part of that outcome. The published privacy-policy sentences are part of the shown answer. This slice may land first only while #7893 and the posture row stay open and the slice is not called done. Product/UX tier is none: the files to create and edit contain no page, component, or mail template. No wireframe.

### Legal

**Status:** reviewed
**Assessment:** Plan-time CLO review on 2026-10-20 found no contradiction with the 2026-10-20 ruling. This plan is an internal draft, not an attestation. A new date, every fired id, and one further word are a shape check. That shape is not an Art. 5(2) demonstration. The script does not grade who, role, before/after, or the Art. 30(1)(f) conclusion, and it does not write the entry, mark FIRED, or advance next due. The honest claim is partial actuation of triggers 2, 4, and 5. Ids 1, 3, 6, and 7 stay unactuated. The posture row is not edited. The copies still disagree on items 3 and 4, and the plan does not pick item 3. Log bodies are not read. `NOT RECORDED` is not replaced with a computed duration.

### Engineering

**Status:** reviewed
**Assessment:** Plan-time CTO review on 2026-10-20 found one contradiction, on the review-hunk algorithm only. Items A, B, and D stand. The live PA-8 (f) cell is one line and already holds bold ids 1 through 7 and existing ISO dates, so line-level added-minus-removed lets any edit satisfy a fired id and a further word. The CTO confirmed the replacement: net-new tokens are the whitespace tokens POSIX `diff` marks added, the date string must be absent from the removed cell, and a pre-existing bold id does not count. No other contradiction. The manifest is what the walker executes. The script holds the approved shape so a manifest edit that drops a site fails. The blocking producer is a new step on the existing `enforce` job, outside the legal-doc run block, because that block exits 0 when no DSAR path changed and a new ruleset context is not required until a later Terraform apply. `legal_resolve_base` is called with an empty explicit argument. The value-pin suites stay in place and do not satisfy the review hunk.

### Operations

**Status:** reviewed
**Assessment:** Plan-time COO review on 2026-10-20 found no operational objection. No new vendor, credential, poll, cron, host, or Better Stack call. Book nothing on the ledger. The cost is delay on the infra pull request that changes an in-scope anchor, until the PA-8 section (f) hunk is in that same diff. The check does not grade whether the note is a real before/after. A later new file that starts the app container with those flags does not fire. Triggers 1, 6, and 7 stay unactuated. The 2026-12-07 re-assess stays unenrolled. The follow-through sweeper is unused. Watching all of `ci-deploy.sh` is out of scope.

## GDPR Gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

The canonical path regex does not match this plan's files. The gate still ran because the brand-survival threshold is `single-user incident`.

### `GDPR-Art-30` — shape check is not the accountability demonstration

**Severity:** Suggestion
**Article:** Art. 5(2), Art. 30
**Location:** plan section Guard Contract
**Pattern matched:** dated review hunk required on an anchor diff
**Why this matters:** A present date shows the diff carried a note. It does not show that the controller demonstrated compliance.
**What to do:** Keep the claim at partial actuation of triggers 2, 4, and 5. Do not edit the posture row to actuated. Do not auto-write the cell. Already the plan.

No Art. 9 column, no new schema, no new foreign key, no new non-EEA vendor, and no new processing activity. No Critical finding. No compliance-posture write.

## Acceptance Criteria

- [ ] `scripts/lint-art30-reverification.sh` exits 1 when a synthesized non-comment `--log-driver`, `--log-opt`, or `--restart` line is added or removed in either watched file and the PA-8 section (f) added tokens lack a new ISO date, a fired id, or a letter-word.
- [ ] Added tokens are the whitespace-delimited words POSIX `diff` marks added on that cell. A bold id counts as new only when `diff` marks that token added. A reorder that breaks alignment can do that, and the check stays green. The ISO date string occurs zero times in the removed cell text, including as a substring of another token.
- [ ] A synthesized (f) cell that already contains bold ids 1 through 7, an old ISO date, and a letter-word fails when the only edit is an unrelated token, and passes when the edit appends a new date, the fired id tokens, and a new letter-word.
- [ ] `--log-driver` or `--log-opt` requires ids 2 and 4 in those added tokens. `--restart` alone requires id 4 and does not require id 2.
- [ ] Any non-empty status from `git diff --name-status --no-renames` of `journald-soleur.conf`, including a comment-only `M` and a symlink replacement `T`, requires id 5 in those added tokens.
- [ ] A comment line, a `"log-driver"` JSON key, and a non-flag line do not fire. A hunk in a different processing activity does not satisfy a fire. A single quote or double quote immediately beside the token is a boundary. `--restart-policy` does not fire.
- [ ] Deleting a non-comment `--log-driver` line fires. The unified-diff display `---log-driver` with no space is content, not a file header.
- [ ] A rename or delete of `journald-soleur.conf` fires trigger 5. The name check is `git diff --name-status --no-renames` pathspec'd to that path, not a grep of the whole-tree name list.
- [ ] A watched-file diff line that begins with the words Binary files, then a space, and ends with a space and the word differ exits 1 even when `git diff` exited 0. A duplicate YAML key, including one whose last value is still the approved shape, or a watched path that appears only in a comment, exits 1.
- [ ] Resolver status is taken in the main shell with `base_rc=0` before the capture. An empty merge-base field exits 2. `git diff` without `--exit-code` returning non-zero exits 2. A filter status of 1 is captured the same way and is an empty fire only after that diff returned 0 and no binary line matched. POSIX `diff` of the token files is captured as `diff_rc`. Exit 1 means the token files differ and the added tokens are read. Exit 2 is script exit 2. An unset `EVENT_NAME` is not an empty merge-group base.
- [ ] A missing, unparseable, or shape-violating manifest exits 1 even when the hunk is present. Shape violations include a dropped watched path, an extra watched path, a `daemon.json` path, class `actuated` on id 1, 3, 6, or 7, and a token-to-id group other than the approved groups.
- [ ] Id-set equality fails when any of the manifest, the runbook `N.` markers, or the PA-8 `(f)` bold `**(N)**` markers is not exactly {1, 2, 3, 4, 5, 6, 7}.
- [ ] `EVENT_NAME=merge_group` with an empty `MERGE_GROUP_BASE_SHA` exits 1. An undecidable base from `legal_resolve_base` exits 2.
- [ ] The birth fixture (valid manifest, no anchor diff, no review hunk) exits 0.
- [ ] The suite goes red when the script body is replaced with `exit 0`.
- [ ] Job `enforce` runs the script with no `if:` on the job or the step, and `surface_patterns` is unchanged.
- [ ] The unit suite is registered in `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`. There is no live `run_suite` of the script against the real tree.
- [ ] The suite asserts the exact runbook pointer sentence, and the runbook still has markers `1.` through `7.`. Deleting the sentence does not fail the id census. The register trigger sentences and the compliance-posture row are unchanged.
- [ ] In-repo text this change adds says partial actuation of re-verification triggers 2, 4, and 5 and does not say the closed list is actuated. The suite does not read GitHub issue or pull-request state.
- [ ] Fixtures are synthesized. No production log body is copied into the suite.
- [ ] An `::error::` annotation names the watched path and the fired ids on a fire, or the measured resolver or diff failure. The message contains no diff line, no other file text, and no CR or LF.

## Test Scenarios

- Given a synthesized repo whose `ci-deploy.sh` gains a non-comment `--log-opt max-size=1m` line, when the script runs, then it exits 1. Layer: unit.
- Given the same diff plus appended PA-8 (f) tokens `2026-10-20 2 4 reviewed`, on a cell that already contains bold ids 1 through 7, when the script runs, then it exits 0. Layer: unit.
- Given that same pre-filled cell and a flag diff whose only cell edit changes an unrelated token, when the script runs, then it exits 1. Layer: unit.
- Given only a non-comment `--restart unless-stopped` change and a hunk that names id 2, when the script runs, then it exits 1. Layer: unit.
- Given a comment-only change to synthesized `journald-soleur.conf` and no hunk, when the script runs, then it exits 1. Layer: unit.
- Given a `"log-driver": "json-file"` line change and no CLI flag change, when the script runs, then it exits 0. Layer: unit.
- Given a manifest that marks id 6 actuated, when the script runs, then it exits 1. Layer: unit.
- Given `EVENT_NAME=merge_group` and an empty base SHA, when the script runs, then it exits 1 and the message after `::error::` names the empty base, contains no diff line, and contains no carriage return or extra line feed. Layer: unit.
- Given the token-file `diff` cannot open an input and exits 2, when the script runs, then it exits 2 and does not treat the token list as empty. Layer: unit.
- Given a NUL byte in a synthesized watched flag file, when the script runs a real `git diff`, then it exits 1 even though `git diff` exits 0. Layer: unit.
- Given the real workflow file, when the unit suite greps job `enforce`, then the script path is present and the step has no `if:`. Layer: unit.
- Given the script body replaced with `exit 0`, when the row-1 assertion runs against that stub, then the suite records a failure. Layer: unit.

No browser scenario and no external API call. `soleur:qa` has no UI flow on this change.

## Success Metrics

- On this branch, the unit suite passes, and the birth-shaped tree (manifest added, anchors unchanged) exits 0.
- A later pull request that changes an in-scope flag without the hunk is red on `enforce` before merge.
- The compliance-posture cell still describes the list as not fully actuated, because this change does not edit that row. Ship text for the pull request does not use a closing keyword for #7893. The suite does not query GitHub to prove the issue is open.

## Dependencies & Risks

- The script and the suite can be rewritten in the same pull request. Review is what catches that pair. The harness row catches only an `exit 0` stub left beside an honest suite.
- Trigger 3 stays disagreed between the two prose copies. A later control on #7893 has to pick the predicate in the manifest and the script shape together. This slice does not pick it.
- Triggers 1, 6, and 7 are not visible to a git diff. They stay on #7893.
- A new launcher file under `apps/web-platform/infra` will not fire until the approved shape is edited on purpose.
- `docker-run-tuple.py` may also fail the same flag edit. Both failures are correct. Updating the tuple pin does not satisfy this gate.
- The runbook pointer is a sentence in a statutory-adjacent runbook. It does not restate retention periods and it does not edit `docs/legal/`. The spec says the pointer is drafted when this section is edited. Plan review asked to delete it. That cut is not applied.
- The implementation pull request body, written at ship, says merging this change does not mutate production hosts and does not use a closing keyword for #7893. That body is not an acceptance criterion. A body-only edit can rerun `enforce` without a tree change.
- Plan review on 2026-10-20 also asked to drop the duplicate-key loader when the last value is still the approved shape. That cut is not applied. Item B requires the loader to reject the duplicate. The token-per-line diff is unchanged. A reorder that breaks alignment stays green.

## References & Research

- Spec: `knowledge-base/project/specs/feat-7893-art30-trigger-actuation/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-10-20-art30-trigger-actuation-brainstorm.md`
- Decisions: `knowledge-base/project/specs/feat-7893-art30-trigger-actuation/decision-challenges.md`
- Issue #7893, draft pull request #10620, follow-up #10623, tracker #7892
- Pattern for base resolution: `scripts/lib/legal-base-ref.sh` and `scripts/lint-legal-scope-block-placement.sh`
- Pattern for the empty queue base and three-dot diff: job `enforce` in `.github/workflows/pr-quality-guards.yml`
- Value pins that do not buy this property: `apps/web-platform/infra/lib/docker-run-tuple.py`, `apps/web-platform/infra/journald-config.test.sh`
- ADR-026 (advisory gdpr-gate, no auto-write) and ADR-032 (`enforce` as a required context)

## Sharp Edges

- A plan whose User-Brand Impact section is empty fails deepen-plan. This plan's section is filled from the brainstorm.
- The completion predicate is the Acceptance Criteria heading. There is no progress key.
- Founder-stated check: this run is the pipeline path, so no founder-check block is written.
- Do not describe the shape check as Article 5(2) demonstrated.
- A line-level diff of the one-line PA-8 (f) cell counts the old bold ids as new. The plan uses POSIX `diff` on whitespace tokens.
- Exit-gate recommendation, not an invocation: the brand-survival threshold is `single-user incident` and deepen-plan has not run. Plan-review does not replace the substance pass inside deepen-plan. This sentence records that recommendation. It does not start a second research pass. Items A, B, C, D, and the C2 token-per-line ruling stay closed.
- Cited `knowledge-base/` and `docs/legal/` paths were checked on 2026-10-20. Each existing citation resolves. `knowledge-base/legal/art30-reverification-triggers.yml`, `scripts/lint-art30-reverification.sh`, and `scripts/lint-art30-reverification.test.sh` are files this plan creates.
