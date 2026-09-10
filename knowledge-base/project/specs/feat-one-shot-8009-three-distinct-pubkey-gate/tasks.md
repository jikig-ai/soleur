---
title: "Tasks — the authorization-map gate + birth-dispatch disclosure"
branch: feat-one-shot-8009-three-distinct-pubkey-gate
plan: knowledge-base/project/plans/2026-09-10-chore-git-data-three-distinct-pubkey-gate-plan.md
lane: cross-domain
issue: 8009
---

# Tasks

Derived from the plan. Phase order is load-bearing: failing tests before the gate
(`cq-write-failing-tests-before`), the gate wired before the disclosure that describes it, and the
binding-hash re-check gating the push.

**Standing constraints.** Never edit any of the 13 hash-bound files — the cloud-init template,
`modules/git-data-userdata/{main,outputs,variables}.tf`, and the nine `file()`-bound payloads
including `git-data-bootstrap.sh`. Never edit `git-data-rung2-boot-evidence.env` for any reason. If
the hash moves, revert the edit that moved it; never adjust the evidence to match.

**The one sentence to keep in mind throughout:** a collapse never changes the left-hand side. Every
assertion extracts, normalises and de-duplicates the *right*-hand side.

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm the binding hash reads `3a2392fb…c1725`.
- [ ] 0.2 Baseline `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → `80 passed, 0 failed`.
- [ ] 0.3 Re-measure the `web-platform-infra-apply` protection rule; record field, scope and date.
- [ ] 0.4 Read `git-data-luks.test.sh`'s `assert_holds`/`assert_mutation`. They are the precedent, but
      they operate on one file in place while this gate reads a root directory plus a template and a
      module — a copy-then-sed tree wrapper is needed.
- [ ] 0.5 Re-run the write-boundary sweep for the justification phrase; confirm D4's table holds.
- [ ] 0.6 Read the suite header's "synthesized fixtures only" rule and arm A1's amendment — the model
      for the live-tree arm's narrowing.

## Phase 1 — RED: fixture, helper, then failing arms

- [ ] 1.1 Build the **five-link synthetic root fixture**: a template with three `command=` slots, a
      module `main.tf` argument map, and root `.tf` files carrying the module call, the pubkey locals,
      three `tls_private_key` blocks and three `doppler_secret` blocks. The existing R2 tree has none
      of links 3–5 and cannot be reused.
- [ ] 1.2 Build the assert-helper pair: it invokes the **new** gate (not
      `git_data_rung2_user_data_sha256` — `_a_abort` is hardwired to that and reusing it would mean
      parameterising ~17 call sites), **pins an exact rc**, and distinguishes ABORT from HOLD by
      leading token. An "any non-zero" helper makes RED theatre: an undefined function returns 127.
- [ ] 1.3 Add the collapse arms: M1 (all three on one var), M2 (two collapse, one distinct), M3
      (module map), M4 (module call), M5 (root local), M6 (fourth slot reusing a var), M9 (alias /
      whitespace / intermediate-local partial extraction), M10 (`var.` with a default), M11 (named
      resource absent), **M12 (transport secret publishes the erase key)**, **M13 (the mirror)**, M15
      (second module instance consumed), plus a **deletion** row (one `command=` line removed → two
      slots, two distinct keys must still red) and a **sibling-file** row (a pubkey local moved to a
      new `.tf` in the same root).
- [ ] 1.4 Add the instrument arms: M7 (zero extraction), M8 (missing/unreadable root via **dangling
      symlink**, not `chmod 000`), M14 (`*override.tf` present), and an unparseable `//` comment.
- [ ] 1.5 Add the must-PASS arms H3 (three distinct but differently *named* vars threaded through all
      five links) and H4 (whitespace/comment noise).
- [ ] 1.6 Add the **live-tree arm** against the real production root on A1's shape, and amend the
      suite header rule in the same commit with its stated justification.
- [ ] 1.7 **Run the suite and confirm it FAILS.** Record the text. Any new arm that passes here is
      testing nothing — rewrite it before proceeding.

## Phase 2 — GREEN: the gate

- [ ] 2.1 Add `_git_data_hcl_nocomment` and **back-port the existing naive HCL stripper onto it**
      (preserving its comment-*blanking* behaviour, which is load-bearing for line numbers). Leave the
      quote-aware YAML stripper alone. If the back-port is not done, cut the helper and inline the sed
      — otherwise this ships a third copy. Do not justify it by DC-2 (recorded "NOT SATISFIABLE AS
      WRITTEN").
- [ ] 2.2 Add `git_data_authorization_map_distinct_gate <production-root>`, fail-closed on a missing
      or unreadable argument, reading `*.tf` + `*.tf.json` across the **root directory** and deriving
      template and module from `dirname`.
- [ ] 2.3 Implement as **one resolution walk + four predicates**, not five per-link assertions:
      exact cardinality 3 at every link; every terminal a `tls_private_key.<name>` address (never a
      `var.`); every named resource block present; the private-half map an exact bijection onto
      `GIT_{TRANSPORT,PROVISION,REMOVE}_SSH_PRIVATE_KEY`. Assert **set equality** on the `command=`
      script names, not membership. ABORT when extracted-address count < slot count.
- [ ] 2.4 ABORT on any `//` or `/*` in the HCL read, and on any `*override.tf` / `*override.tf.json`.
- [ ] 2.5 Assert exactly one `module` block with `source = "./modules/git-data-userdata"`, and that
      `hcloud_server.git_data.user_data` names that label.
- [ ] 2.6 Put the literal `3` in one named constant with the ADR-068 citation inline.
- [ ] 2.7 HOLD message: name the consequence (the transport identity would gain erase authority), end
      with a remedy and "nothing has been planned or created". Do not label the gap "Art. 17" — it is
      Art. 32(1)(d).
- [ ] 2.8 RELEASED message: state exactly what it proves, including that rendered key material is not
      compared.
- [ ] 2.9 Raise the anti-vacuity floor, itemised in the file's convention, counting **verdicts**.
- [ ] 2.10 Run the suite green.

## Phase 3 — Allowlist justification

- [ ] 3.1 **Add** the capability sentence to the comment block, plus the rehearsal-collapse sentence
      (replacing cut Guard 2) and the note naming the surviving hash-bound divergence with its issue.
- [ ] 3.2 **Minimally generalise** the HOLD message. Do **not** delete the phrase — it is accurate for
      five of the eight tokens.
- [ ] 3.3 Leave the token list and all **six** consumers byte-identical, and prove it.

## Phase 4 — Wiring

- [ ] 4.1 Third interlock step in `git_data_host_create`, after the rung-2 step, before
      `Terraform init`, wrapped in an `::error::` matching the siblings.
- [ ] 4.2 Interlock in `git_data_host_replace` — no human approver there, and after birth it is the
      only path a collapse can travel.
- [ ] 4.3 Extend `plugins/soleur/test/terraform-target-parity.test.ts`'s job↔gate pairing block so 4.1
      and 4.2 cannot be silently skipped.

## Phase 5 — C2 disclosure

- [ ] 5.1 Add the `git_data_birth_disclosure` job — same `if:`, **no `environment:`** — writing the
      three statements to `$GITHUB_STEP_SUMMARY`; add `needs:` to `git_data_host_create`. This is what
      puts the text on the run page while the gated job waits.
- [ ] 5.2 Add the three statements to `## Before you dispatch` (the primary surface — read before
      approval).
- [ ] 5.3 Statement (a): quote the AC30 wording via the `WORDING PINNED (AC30)` anchor; say the
      **repositories** are not encrypted at rest; do not compress to "LUKS is not in place".
- [ ] 5.4 Statement (b): field, scope and date from 0.3; do not generalise beyond that environment.
- [ ] 5.5 Statement (c): final stage reached without tripping the named `FATAL` gates; the four
      literals are the channel, not measurements; exactly one boolean (`nft_metadata_drop`) measured,
      read `yes`, in neither committed artifact. Neither overclaim nor "proves nothing".
- [ ] 5.6 Correct the stale `apply_target` clause claiming the route is held and a dispatch exits 1.
- [ ] 5.7 Fix `## What the job does, in order` — it omits the rung-2 interlock and would now omit the
      third.
- [ ] 5.8 Leave the DO-NOT-DISPATCH banner byte-identical.

## Phase 6 — Architecture record

- [ ] 6.1 ADR-149 release-checklist item 10, inserted after item 9's closing sentence and before the
      `### Disposition — #6982 (2026-07-27)` heading.
- [ ] 6.2 Add its **disposition row marked DONE**, so #7025's banner-clearing precondition is not
      silently extended.

## Phase 7 — Trackers

- [ ] 7.1 File F1 (`domain/legal`), F3 (`type/security`), F6 (`type/chore` + `domain/engineering`).
- [ ] 7.2 Link all three in the PR body.

## Phase 8 — Verification before push

- [ ] 8.1 **Re-run the hash; confirm `3a2392fb…c1725` unchanged.** If it moved, revert the edit.
- [ ] 8.2 Confirm diff ∩ (13 hash-bound paths) is empty and the evidence file is absent from the diff.
- [ ] 8.3 Confirm `modules/git-data-userdata/variables.tf`'s `identity-shaped` line is byte-identical.
- [ ] 8.4 Run the suite green at its raised floor.
- [ ] 8.5 Run `plugins/soleur/test/c4-count-parity.test.sh` and
      `plugins/soleur/test/terraform-target-parity.test.ts`.
- [ ] 8.6 Confirm the four birth-target registration sites are byte-identical and no `-target=` flag
      moved (`git diff -U0` over the workflow and gate libs, path-scoped — the runbook renumbering
      legitimately touches a step-list item quoting `-target=`).
- [ ] 8.7 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 8.8 `actionlint` the workflows; `bash -c` extracted `run:` snippets with
      `GITHUB_STEP_SUMMARY=$(mktemp)`. Never `bash -n` a YAML file.
- [ ] 8.9 Full battery if `/var/tmp` is uncontended; on rc=4 report skipped-for-contention and run the
      affected suites directly. Never force.
