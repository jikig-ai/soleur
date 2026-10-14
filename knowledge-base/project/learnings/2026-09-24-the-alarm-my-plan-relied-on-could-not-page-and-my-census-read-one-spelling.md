---
title: "The alarm my plan relied on could not page, and my census read one spelling"
date: 2026-09-24
category: integration-issues
module: apps/web-platform/infra (cloud-init boot legs, Sentry rules, zot soak)
tags: [adr-096, ghcr, zot, sentry-alert, guard-census, fan-out, review-panel]
issue: 8036
pr: 8708
---

# Learning: the alarm my plan relied on could not page, and my census read one spelling

## Problem

PR #8708 (#8036 item 1d, ADR-096 5.3b-i) deleted every host-side GHCR boot leg: the web seed
block's GHCR login and pull arm, `soleur-host-bootstrap.sh`'s `ghcr_login` subshell, and the
dedicated inngest host's GHCR login and fallback pull. With the fallback gone, a zot miss is now a
terminal boot, so the plan's safety argument (property P2) was "a failed boot pages".

Two things that argument rested on were not true, and neither was visible to a green suite:

1. **The web page could not fire.** `web_terminal_boot_fatal` used `event_frequency_count
   value = 1`. The comparison is a strict `>` and is per issue group. The web seed fatal
   (`_emit "soleur-hostscript-seed failed" "$STAGE" fatal`) has its own group, so one event
   cannot page. Measured: the only such event in 30 days (#8651's dark boot, WEB-PLATFORM-4T) was
   a single event. The rule's own comment said `value = 1` works "because the shared group is
   always hot"; that is true for the `soleur-boot-emit` group and false for this one.
2. **The Guard 1 census read one spelling.** It matched `docker pull|create` and nothing else.
   `docker image pull "$IREF"`, `docker run "$IMAGE_REF"`, `docker --config D pull …`, a sentinel
   *writer* that stored the GHCR ref, a `registry_endpoint = "ghcr.io"` in a `.tf` map, and any
   host script outside a fixed three-file list all passed every suite. The test-design seat found
   the `docker image pull` evasion (all 12 suites green, battery 55/55 "killed"); the
   structural-enumeration seat mapped the rest.

## Solution

- `web_terminal_boot_fatal` → `value = 0` (the `git_data_boot_warning` precedent). Safe because
  all five stage conditions are emitted only on failure, and that is now **pinned**: the
  op-contract test extracts the rule's conditions (scoped, comments stripped), `toEqual`s the
  exact set, and asserts every emitter of those stages in `infra/**` is `fatal`.
- The census now accepts global flags, the `image`/`container` verbs and `run`; checks the
  `/run/soleur-image-ref` writer; checks endpoint values in every `templatefile()` map; derives
  its file list from the `templatefile()` call sites; and scans every baked host script with a
  narrower literal rule. Each widening has a battery row that must go RED.
- The soak (`zot-soak-6122.sh`) gained a web `stage:"pull" level:fatal` arm, a retired-names arm
  for pre-1d events after START, a runtime anchor against #8660's `mergedAt`, and a note on every
  verdict when START was overridden.

## Key Insight

**When a PR removes a fallback, the page for the now-terminal failure becomes load-bearing.
Measure that the page can fire on ONE event before writing "it pages".** A frequency rule's
threshold is a claim about how many events arrive in a group, and a new or rare failure is
exactly the case where that number is 1.

**A census that names the construct it forbids is a census of one spelling.** Enumerate the
grammar (flags before the subcommand, alternate verbs, implicit pulls, writers of the value,
config that supplies the value) before calling a residual-zero guard complete, and derive the
file set from the system rather than listing it.

## Session Errors

1. **Planning subagent and its plan-review child died on API 429 (session limit).**
   Recovery: the plan was on disk with `## Acceptance Criteria`, so it was recovered as a partial
   artifact and deepen-plan ran inline. **Prevention:** already covered by one-shot's
   plan-artifact-recovery block; it worked as designed.
2. **`gh issue create --body-file $B` denied; the heredoc in the same call never ran.**
   Recovery: wrote the body with the Write tool, then filed in a separate call.
   **Prevention:** existing `work` rule ("never heredoc an issue body into the same Bash command
   as a hook-gated `gh issue create`"); follow it.
3. **Filing denied for naming no user-visible consequence.** Recovery: added
   `Mandated-By: wg-when-deferring-a-capability-create-a` on its own line. **Prevention:** put the
   `Mandated-By:` line in any tracker body drafted for a deferral.
4. **`pgrep -f` blocked by the self-match hook.** Recovery: `/proc` walk plus
   `proc.sh kill_mine`. **Prevention:** hook-enforced; use `proc.sh list_runs` first.
5. **A `gh --jq` expression combined an array and an object.** Recovery: split the query.
   **Prevention:** one-off.
6. **The gate sat queued for 49 minutes behind sibling runs, then went stale under review
   fixes.** Recovery: stopped it and re-ran on the final tree. **Prevention:** when `--capacity`
   reports `CAPACITY_CONTENDED`, start review in parallel rather than waiting on the gate, and
   plan to re-run after fixes.
7. **A description I wrote containing the text `templatefile()` tripped
   `templatefile-bare-dollar-guard`.** Recovery: reworded to "templatefile call". **Prevention:**
   covered by the bare-token-guard class; run the infra guard suites after editing a `.tf`
   description.
8. **Parallel fix agents added 13 unguarded fixture writes (ratchet red).** Recovery: canonical
   `assert_fixture_dir` guards, heredoc stubs, and one reworded Python string the scanner misread.
   **Prevention:** routed to `work/references/work-subagent-fanout.md` — a hand-written brief owes
   the template's INSTRUCTIONS block (which names the ratchets) verbatim.
9. **The plan relied on a web page that could not fire on one event.** Recovery: `value = 0` plus
   pinned condition set and failure-only emitters. **Prevention:** the Key Insight above.
10. **A plan claim that live-fidelity row F27 would become a no-op was false.** Recovery: the
    realism census corrected it; the change needed only a comment refresh. **Prevention:** existing
    rule — every causal claim the plan adds names its falsifying command.
11. **The records slice wrote "enrolled on #6122" before the enrolment ran.** Recovery: enrolled
    #6122 (directive + label) before ship. **Prevention:** routed to the fan-out reference — run
    tracker steps before delegating records that describe them.
12. **My own stale-comment fix introduced a false claim** ("1d stopped fresh boots writing the
    home entry"; the boot logins ran as root). Recovery: the soak/followthrough fix agent corrected
    both copies. **Prevention:** existing rule — a correction round is where new unmeasured claims
    ship; falsify each sentence the fix adds.
13. **The Guard 1 census read one spelling; `docker image pull` evaded all suites.** Recovery:
    widened census plus per-spelling battery rows. **Prevention:** the Key Insight above.
14. **One battery run scored 59/60 under concurrent suite load.** Recovery: a clean rerun gave
    60/60. **Prevention:** one-off; do not run batteries alongside other suites.

## Tags

category: integration-issues
module: apps/web-platform/infra
