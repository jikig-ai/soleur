# Tasks — git-data boot-diagnostics: T-2, T-3, T-1

Derived from
[`2026-08-11-feat-git-data-boot-diagnostics-t1-t4-plan.md`](../../plans/2026-08-11-feat-git-data-boot-diagnostics-t1-t4-plan.md)
after plan-review (6 reviewers) and the operator's rulings on
[`decision-challenges.md`](./decision-challenges.md).

**T-4 is out of scope for this branch** — deferred to #7460.

Suite floors: luks ≥133 · runcmd rehearsal ≥44 (**detached, poll an rc file** — ~13 min
exceeds the 600 s tool ceiling) · rung-2 rehearsal ≥71 · evidence-capture ≥33.
No predicate may use `producer | grep -q` (SIGPIPE fails open under `set -uo pipefail`, #7005)
— use herestrings.

## Phase 0 — Trapdoor check (before any code)

- [ ] 0.1 Verify `SENTRY_ISSUE_RO_TOKEN` resolves under `doppler run -p soleur -c prd_terraform`
      — the config `git-data-rung2-rehearsal.yml:317` actually uses. It currently lives in
      `soleur/prd`. If absent, T-1 is a dead read.
- [ ] 0.2 If absent, provision it into `prd_terraform` before writing any Phase 3 code.

## Phase 1 — T-2: strip the cloud-init template

- [ ] 1.1 RED: assert the rendered `user_data` **starts with** `#cloud-config`; assert every
      shebang in the unstripped render survives; assert `stripped_bytes > 0`. Confirm each goes
      RED against the payload expression.
- [ ] 1.2 Add `git_data_template_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"` as a
      **second** local in `modules/git-data-userdata/main.tf`, mirroring `zot-registry.tf:405`.
      **Leave `git_data_rationale_strip` byte-unchanged.**
- [ ] 1.3 Wrap the render: `replace(templatefile(…), local.git_data_template_rationale_strip, "")`,
      mirroring `zot-registry.tf:520`/`:563`. Verify both invariants: no brace in the literal,
      and every templatefile map entry stays on one physical line.
- [ ] 1.4 Mirror the new local in `git-data-userdata-budget.sh`; emit `stripped_bytes`; emit both
      stripped and unstripped renders.
- [ ] 1.5 Extend `git-data-render-strip-parity.test.sh` to compare the **second** expression too.
- [ ] 1.6 Harden B1's extractor (`git-data-runcmd-rehearsal.test.sh:212`) to skip comment lines.
      Write **no** `# was: …` comment naming an expression until this lands.
- [ ] 1.7 Fix `.github/scripts/validate-infra-templates.sh` so `cloud-init schema -c` runs
      against the **stripped** render (today it renders the bare `templatefile()` at `:558`).
- [ ] 1.8 Add the per-entry byte-diff assertion: each `write_files` entry and each `runcmd`
      element differs only by lines matching the strip regex.
- [ ] 1.9 Add the interpolation-site assertion: every `${…}` in `cloud-init-git-data.yml` is
      preceded on its line by a non-newline character.
- [ ] 1.10 Keep at least one rehearsal arm reading the **unstripped** render so R1 (`:757`,
      `:762`), B2 (`:442`) and S1 (`:669`) do not degenerate once the render is comment-free.
- [ ] 1.11 Update the stale `main.tf` comment ("cloud-init-git-data.yml itself is NOT stripped").
- [ ] 1.12 Write the **ADR-152 addendum** (no new ordinal) with the measured bytes; correct
      ADR-152's standing statement about git-data. Evaluate `templatestring()` (A3) in its
      alternatives — if rejected, reject on cost, not impossibility.
- [ ] 1.13 Re-run `git-data-userdata-budget.sh`; record stored/headroom.
- [ ] 1.14 GREEN: budget · parity · `validate-infra-templates.sh` · luks ≥133 · runcmd
      rehearsal ≥44 (detached).

## Phase 2 — T-3: close the vacuity hole

- [ ] 2.1 RED: an empty `runcmd-all.code.sh` must fail the suite (today its four arms pass
      vacuously).
- [ ] 2.2 Add the mirrored non-vacuity assert at `git-data-runcmd-rehearsal.test.sh:122-123`,
      matching `luks-stage.code.sh`'s `assert "mkfs.ext4" in _code`. Pick a sentinel present in
      the concatenated runcmd that is not comment-only text.
- [ ] 2.3 **No shared bash library** (UC-A, operator-resolved — two of three call sites are
      Python inside a `python3 <<PY` heredoc).
- [ ] 2.4 GREEN: runcmd rehearsal ≥44 (detached).

## Phase 3 — T-1: Sentry arm on the evidence-capture script

- [ ] 3.1 RED: extend `tests/scripts/test-git-data-rung2-evidence-capture.sh` with three arms —
      fatal present ⇒ `FAIL`; fatal absent with a live source ⇒ prior verdict; non-200 / rc≠0 /
      unparseable ⇒ `TRANSIENT`.
- [ ] 3.2 Add the Sentry query at the `boot_complete`-missing branch (`:306`) — the #7116 fix,
      where Better Stack is live but silent because parent-shell stages reach Sentry only.
- [ ] 3.3 Add it to the two TRANSIENT exit paths as well — transport rc≠0 (`:252`) and zero-row
      anchor (`:271`) — which return **before** `host_out` is queried.
- [ ] 3.4 Query `GET /api/0/organizations/jikigai-eu/issues/?query=…` scoped by `host_name:` and
      `stage:`, **bounded by the same `WINDOW`** as the Better Stack SQL (Sentry issues
      aggregate across occurrences; unbounded, an earlier boot of a reused `host_name` would
      flip a genuine PASS to FAIL).
- [ ] 3.5 Fail closed: non-200 / rc≠0 / unparseable ⇒ `TRANSIENT` with an explicit no-verdict
      line, mirroring `:253`/`:282`. Anchor on field shape (`"id":"…"`), never a bare token.
- [ ] 3.6 State the precedence rule in the script: **FAIL from either sink wins; TRANSIENT only
      when both are silent-and-live.**
- [ ] 3.7 Update the now-false operator message at `:307-312` and the header note at `:45-52`
      ("#7116 owns that work; do not do it here") — this is that work.
- [ ] 3.8 Add a runbook line for "Sentry FAIL, Better Stack silent".
- [ ] 3.9 GREEN: evidence-capture ≥33.

## Phase 4 — Reconciliation

- [ ] 4.1 Re-sync measured byte figures across the ADR-152 addendum and the acceptance record so
      all match the budget artifact.
- [ ] 4.2 Confirm `git_data_rationale_strip` is byte-identical to `origin/main`.
- [ ] 4.3 Full floors: luks ≥133 · runcmd rehearsal ≥44 (detached) · rung-2 rehearsal ≥71 ·
      evidence-capture ≥33 · `lint-encryption-posture.py --repo-sweep` PASS ·
      `validate-infra-templates.sh` rc=0 · `check-adr-ordinals.sh` rc=0.
- [ ] 4.4 Confirm `git-data-rung2-boot-evidence.env` is still absent and no
      `git-data-rung2-rehearsal.yml` dispatch occurred.
- [ ] 4.5 Add the ordering prerequisite to #6977: the first birth must dispatch the rung-2
      rehearsal **after** this merge (the evidence hash covers `main.tf`).
