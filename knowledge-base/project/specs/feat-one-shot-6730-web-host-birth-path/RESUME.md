# Resume — #6730 web-host birth path (ship the remaining steps)

Paste the block below into a fresh session. Everything above the fence is context for a
human; the fence is the prompt.

---

```text
Resume shipping #6730 (web-host birth path). Implementation and multi-agent review are
DONE; what remains is /compound, /ship, and one post-merge dispatch.

WHERE
  worktree: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6730-web-host-birth-path
  branch:   feat-one-shot-6730-web-host-birth-path
  PR:       #6953 (OPEN, DRAFT, placeholder title "WIP: feat-one-shot-...", body is 73
            chars of boilerplate, no labels)
  issue:    #6730 (OPEN, milestone "Phase 4: Validate + Scale")
  plan:     knowledge-base/project/plans/2026-07-25-feat-web-host-birth-path-plan.md
  tasks:    knowledge-base/project/specs/feat-one-shot-6730-web-host-birth-path/tasks.md

STATE AT HANDOFF (verified, not remembered)
  13 commits ahead of origin/main, 0 unpushed, working tree clean.
  Behind main by 1 docs-only commit (c5f9fc19c) — probed, NO conflicts. Rebase anyway.
  Plan phases 0-4 complete and checked off. Phase 5 (5.1-5.3) is post-merge, unchecked.

  Gates last run green at 345b7ddc2:
    bash scripts/test-all.sh                       -> 226/226, EXIT=0
    all 70 registered infra suites                 -> none red
    tests/scripts/test-web-host-birth-gate.sh      -> 34/0
    plugins/soleur/test/terraform-target-parity    -> 67/0
    soleur-host-bootstrap-observability.test.sh    -> 94/0
    actionlint, terraform validate/fmt, shellcheck, check-adr-ordinals,
    lint-infra-no-human-steps --changed            -> clean

DO THIS
  1. git fetch origin main && git rebase origin/main   (re-run the gates after)
  2. skill: soleur:compound
  3. skill: soleur:ship

FIVE THINGS THAT WILL BITE YOU IF YOU SKIP THEM

  (a) scripts/test-all.sh does NOT cover apps/web-platform/infra/. Those 70 suites are
      registered ONLY in .github/workflows/infra-validation.yml. A green test-all is NOT
      evidence for this PR — a required check (web-1-swap-concurrency-parity) was already
      RED behind a 223/223 green during this work. Run them explicitly:
        for t in $(grep -oE 'run: bash apps/web-platform/infra/[a-z0-9.-]+\.test\.sh' \
          .github/workflows/infra-validation.yml | sed 's/run: bash //' | sort -u); do
          bash "$t" >/dev/null 2>&1 || echo "RED: $t"; done

  (b) If you run `terraform init` in apps/web-platform/infra, DELETE the .terraform/ dir
      afterwards. It is 162 MB, gitignored, and credential-persist-home-guard.test.sh
      copies the infra dir into the shared 4 GiB /tmp tmpfs — it fails with "No space left
      on device" and looks exactly like a regression. Verify any such failure against
      origin/main before believing it.

  (c) USE `Ref #6730`, NOT `Closes #6730`, in the PR body. The plan's acceptance criteria
      are split "Pre-merge (PR)" / "Post-merge (dispatch-verified, automated)" — AC13/AC14
      can only be proven by the Phase 5 dispatch, which runs AFTER merge. Auto-close on
      merge would close the issue before its own ACs are demonstrated. Close it manually
      after 5.2 goes green, with the run URL.

  (d) The PR needs a real title, a real body, and a semver label. Suggested title:
        feat(6730): digest-pinned automated web-host birth path
      The body must carry the review disposition (below) — the review found and fixed
      several P1s, and that is the most useful thing in the PR for a future reader.

  (e) Force-push needs --force-with-lease: this branch was rebased twice, so the remote's
      pre-rebase SHAs are unreachable. Before any force-push, confirm nothing is lost:
        git fetch origin <branch> && git cherry HEAD origin/<branch> | grep '^+'
      Two flagged entries are EXPECTED (pre-rebase versions of the same commits, whose
      patch-ids changed during conflict resolution). Verify by SUBJECT, not patch-id.

PHASE 5 — POST-MERGE, AFTER CI IS GREEN ON MAIN
  This is the point of the whole PR: web-2 is declared in var.web_hosts but does not
  exist, so EVERY merge to main currently HALTs on the host_creates tripwire. The dispatch
  is the unwedge.

    gh workflow run apply-web-platform-infra.yml \
      -f apply_target=web-host-create \
      -f web_host_key=web-2 \
      -f confirm=BIRTH-web-2 \
      -f reason='unwedge main — birth web-2 per #6730 Phase 5'

  It pauses on the `web-platform-infra-apply` environment for reviewer approval before its
  first step. Approve it in the Actions UI.

  Do NOT pass -f image_tag for web-2 — the pin resolves from web-1's live /health, which is
  correct while web-1 is serving. image_tag is ONLY for birthing web-1 (or any birth while
  the fleet is down), where that read is circular by construction.

  Then: 5.2 confirm soleur-web-2 exists via the Hetzner API and the run's step summary
  shows cloud_init_complete with no fatal; 5.3 confirm the next merge to main no longer
  HALTs. Tick 5.1-5.3 in tasks.md and close #6730 with the run URL.

THREE KNOWN-OPEN FINDINGS (P2/P3, deliberately not fixed — decide, do not rediscover)
  1. hcloud_volume_attachment.workspaces_luks is web-1-bound (workspaces-luks.tf,
     server_id = hcloud_server.web["web-1"].id) and is NOT in the birth fan-out. Harmless
     for a web-2 birth. On a web-1 REbirth it leaves the LUKS attachment pointing at a
     destroyed server id — today that silently drops the backup copy; after the ADR-119
     cutover flips /mnt/data to the LUKS device it would drop the LIVE copy. Worth an
     issue before that cutover lands.
  2. The runbook's break-glass appendix lost its "verify the boot" step in this PR's
     rewrite. Break-glass is used exactly when the dispatch is unavailable, so it should
     not be the path with no boot verification.
  3. soleur-host-bootstrap-observability.test.sh's awk block extractor over-collects into
     the FOLLOWING job's comment preamble (it closes on `^  <job>:` but not on the comment
     block before it). Fail-safe in direction — negative assertions would false-FAIL, not
     false-PASS — but it weakens the job-scoping property the file's own header claims.

WHAT REVIEW FOUND (for the PR body — nine agents, four fix commits, all pr-introduced)
  P1  The gate had no REQUIREMENT arm — measured rc=0 on a plan whose only entry was the
      server create, i.e. it passed the exact #6416 shape it exists to prevent. Five
      prohibition arms constrain what a plan may ALSO do, never what it must do. Added a
      requirement arm (NIC + volume attachment must each create — the two members the
      server's own creation entails), mutation-proven, and deleted the post-apply loop it
      superseded.
  P1  web-host-birth-environment.tf would have DELETED a live security control. The
      environment carries two protection rules; the reviewers-only declaration serialises
      deployment_branch_policy as null, removing the main-only pin that stops a dispatch
      running a feature branch's gate against production. Both halves now declared.
  P1  R2 read Sentry ~15 min before its signal could exist (cloud_init_complete is the last
      line of runcmd; the host's own window is 900s), so it printed "genuinely emitted
      nothing" on a HEALTHY boot — byte-identical to a dark one. Now polls to a terminal
      state and fails the run on a dark boot, which makes the plan's declared alert_route
      true rather than fabricated.
  P1  web-1 could not be born at all: the pin source is web-1's own /health. Added
      -f image_tag, shape-validated; still digest-pinned and coherence-preflighted.
  P1  A web-1 birth would have stranded DNS — cloudflare_record.app is a DEPENDENT of the
      server and -target is upstream-transitive only. Added to the fan-out.
  P1  Three of the five restored ADR-128 assertions were VACUOUS (R5 satisfied by a sibling
      step and then by its own comment; R4's negative evadable by the unbraced spelling;
      AC14 satisfiable by a comment). Each re-anchored and mutation-proven 94/0 -> 93/1.
  Blocker  web-1-swap-concurrency-parity was RED (5th member, never enrolled).
  P2  Restored the amd64 runner gate the deleted predecessor had; corrected three false
      claims in stock-preflight-gate.sh; collapsed the fan-out from four copies to one with
      a gate<->workflow parity binding; masked SENTRY_AUTH_TOKEN; swept four live surfaces
      still asserting "no automated path can birth a web host" (one was a runtime ::error::
      contradicting its own sibling).

  The honest through-line, worth one line in the PR body: nearly every defect was a
  property ASSERTED rather than measured, in a PR whose own gate comments say "MEASURED,
  not assumed."
```
