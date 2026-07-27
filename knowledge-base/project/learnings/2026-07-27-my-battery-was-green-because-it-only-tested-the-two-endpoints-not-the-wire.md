---
date: 2026-07-27
issue: 6570
pr: 6974
category: test-failures
module: apps/web-platform/infra
tags: [mutation-testing, terraform, test-vacuity, citation-drift, triggers_replace, false-comment]
---

# Learning: my battery was green because it only tested the two endpoints, not the wire

## Problem

PR #6974 repinned the `git-data` Hetzner host off an unorderable ARM type and made its
architecture *derived* from the type prefix. I wrote four behavioral assertions, gave every one a
mutation arm, and reported **35 passed, 0 failed**. I explicitly did *not* copy the weak half of the
sibling precedent, and I cited that precedent's own §9b measurement ("5 of 8 such mutations passed
the old fragment guard") as the reason.

An 11-agent review panel then found **seven P1s**, four of them introduced by me, past that green
suite plus `terraform validate`, `terraform fmt`, a clean 7/7 render gate, 72/72 registered infra
suites and 226/226 repo suites.

## Root cause

### 1. The endpoints were asserted; the wire between them was not

The data path is `var.git_data_server_type` → `local.git_data_arch` → **templatefile map key** →
`${doppler_arch}` in the cloud-init.

- A16 proved the *producer* (the derivation replays correctly over the type space).
- A14 proved the *consumer* (the cloud-init interpolates `${doppler_arch}`).
- **Nothing proved they were connected.**

Hardcoding `doppler_arch = "arm64"` on the map key between them reproduced the exact boot-brick the
PR exists to prevent — arm64 binary on an x86 host, `doppler` never runs, `GIT_DATA_LUKS_KEY` never
arrives, the LUKS volume never opens — at **35/35 green**. The `lifecycle.precondition` cannot see it
either, because `local.git_data_arch` is still correctly `amd64`.

### 2. An order-compare was called a pairing check

`canon_doppler_pair` extracted the two per-arch checksums and compared them **in textual order**
across three files. It never read the ternary's *condition*. Flipping `local.git_data_arch == "arm64"`
to `== "amd64"` leaves both literals present, in the same order — so all three files still compared
byte-equal at 35/35, while the host verifies the amd64 tarball against the arm64 digest. My own
comment claimed this assertion caught "a pairing SWAP". It could not.

The generalization: **the binding lives in the condition, not in the sequence.** An assertion over
token order is not an assertion over the mapping those tokens participate in.

### 3. Every mutation arm perturbed bytes the predicate already read

That is the signature of arms fitted to the shipped implementation rather than derived from the
requirement. Both P1 classes were *structurally unreachable* by the battery — not missed by bad luck.

## Solution

- Normalize before comparing: emit an order-independent `amd64=<sha>;arm64=<sha>` binding parsed
  from the ternary's condition. This catches the swap **and** stops a semantically identical
  refactor from red-lining the guard.
- Add an assertion for the **wire** (`p_templatefile_wiring`), not just the endpoints.
- Add an assertion for the **referencing edge** the whole design rests on (`p_tripwire_edge`) —
  terraform prunes an unreferenced data source under `-target=`, so deleting the precondition
  silently disarms the phantom-type guard while CI stays green.
- Re-verify against a **pristine baseline** in a sandbox: 4/6 → **6/6** mutations caught.

## Key insights

**A mutation battery measures the mutations its author imagined.** A green battery is evidence about
the battery, not about the tests. Before crediting one, ask of each assertion: *what SET does this
quantify over, and how many distinct members does the fixture instantiate?* Then ask someone else to
find the vacuity you did not imagine — not to re-run your mutations.

**Assert the edges of a data path, not only its endpoints.** Producer-correct plus consumer-correct
does not imply connected. The unasserted wire is where the original bug relocates to.

**`mock_provider` synthesizes a random string for computed attributes.** A `lifecycle.precondition`
reading `data.<x>.architecture` therefore fails *every* `terraform test` run block with a message
that names a Hetzner anomaly which never happened. Fix with `override_data` — and verify the
override does not *disable* the guard (`-var git_data_server_type=cax11` must still red).
`terraform validate` passing says nothing about `terraform test`.

**A comment-only edit can have production blast radius.** `web-git-data-probe.sh`'s bytes are hashed
into a `terraform_data` `triggers_replace`, and that resource sits in the per-merge SSH apply's
`-target` list on a step with no destroy-guard. A citation fix would have root-SSHed the live serving
host to re-upload unit files and rewrite a token env file. **Before editing any file — even a
comment — grep every `triggers_replace` / `filesha256` for its path.**

**Sweep by CLASS, not by the file you were thinking about.** I swept every stale citation *into*
`cloud-init-git-data.yml` (+10 lines) and completely missed the identical class for `git-data.tf`,
which the same diff grew by **+68 lines**. Caught only because an unrelated ledger entry cited a
resource that had moved. The unit of the sweep is the defect class, not the file.

**A false comment restated across artifacts is one defect, not three.** "The real abort is downstream
at `doppler run` (which does carry `set -euo pipefail`)" went into the Terraform, the ADR and the
plan. That `set -e` is line 1 of the heredoc `doppler run` *executes*, so on the missing/wrong-arch
binary it never runs. Nothing aborts; the boot "succeeds" with the LUKS volume unmounted. Repetition
across artifacts reads as corroboration and is not — they share one premise.

**A false *verification* claim is worse than a stale fact.** A statutory Art. 30 register asserted
"verified against `variables.tf` … server_type `cx23`" when live `variables.tf` said `cpx22`. A stale
fact is out of date; an attested check that never held is a claim about diligence. Correct it inline
rather than flag it — and correct its siblings so the document is not left self-contradictory.

**Fix the generator, not just the symptoms.** `terraform-architect.md` said "Prefer CAX (ARM)
instances for cost optimization". That standing instruction produced three unbornable hosts
(#6178, #6967, #6570). Fixing the third symptom while leaving the generator is how a fourth happens.

## Session Errors

- **`terraform test` never run in Phase 6, CI red.** The precondition/`mock_provider` interaction
  failed `infra-validate-required`. — Recovery: `override_data` pin, verified non-disabling. —
  **Prevention:** when a diff adds a `lifecycle.precondition`/`postcondition` or any assertion on a
  provider-computed attribute, run `terraform test`, not just `validate`.
- **Mutation battery green over two P1 vacuities.** — Recovery: sandbox-reproduced both, rewrote the
  predicates, 6/6. — **Prevention:** route the "find the vacuity my battery missed" question to an
  independent reviewer; never treat a self-run battery as coverage evidence.
- **False "real abort" claim in three artifacts.** — Recovery: corrected all three. —
  **Prevention:** when a claim names a guard, trace whether that guard *executes* in the failure mode
  described.
- **Citation sweep missed `git-data.tf`.** — Recovery: content-resolved every citation, regenerated
  `model.likec4.json`. — **Prevention:** derive the sweep target from the diff's line-count deltas,
  not from the file under discussion.
- **Comment edit would have triggered an unguarded SSH re-provision.** — Recovery: reverted. —
  **Prevention:** grep `triggers_replace`/`filesha256` before touching any infra file.
- **Plan Observability asserted an armed heartbeat, a Vector shipper and a reachable gate** — all
  three false against live data. — Recovery: pulled Better Stack (7 heartbeats, git-data absent) and
  measured the shipper (0 occurrences vs 31 in the sibling). — **Prevention:** every
  `liveness_signal` needs a `live_verification:` line, the way the Encryption Posture block already
  requires one per store.
- **PR body stale across 18 commits** ("Artifacts only — no IaC change"; asserted a birth dispatch
  that does not exist). — Recovery: rewritten. — **Prevention:** re-read the PR body at review time;
  it is the first artifact a reviewer sees and the last one anybody updates.
- **Bulk checkbox toggle** marked ship-prep and an unverified task done. — Recovery: re-audited and
  un-checked. — **Prevention:** the existing rule is right; a checkbox is a claim.
- **My own AC13 harness reported rc=0 always** — `$(basename …)` reset `$?` before it was read. —
  Recovery: captured `rc` before the `echo`. — **Prevention:** in a verification harness, capture
  `$?` into a variable on the very next line; any command substitution in between clobbers it.
- **Background notification said "exit code 0" twice while the real rc was 1** (trailing `tail`). —
  Recovery: read the rc file. — **Prevention:** already documented; it recurred anyway.
- **`/tmp` (4 GiB tmpfs) exhausted by an abandoned 2.3 GB sibling scratch dir** → false RED on
  `credential-persist-home-guard.test.sh` (28/0 on `/var/tmp`). — **Prevention:** run suites that
  copy large trees with `TMPDIR=/var/tmp`; do not delete a sibling session's scratch.
- **Edited the tree while suites were running**, measuring a moving target. — Recovery: killed,
  confirmed no survivors, re-ran clean. — **Prevention:** treat a running suite as a freeze window.
- **Shell env does not persist between Bash calls** — an unauthenticated `terraform state list`
  returned a false "0 matches" that contradicted the prior run. — **Prevention:** when two probes
  disagree, re-run both in one authenticated call before believing either.
- **An agent's proposed remedy was wrong** (revert `session-proxy.ts` to avoid the release —
  the infra `.tf` edits match the same glob, so it fires regardless). — **Prevention:** verify a
  remedy's mechanism, not just its finding.
- **Filed two follow-ups without the `code-simplicity-reviewer` CONCUR gate.** — **Prevention:** the
  gate exists for the dissent case; run it even when the size test is obviously satisfied.
- **CWD persists between Bash calls but shell env does not** — a second `cd apps/web-platform/infra`
  failed because the first had already landed there. — **Prevention:** the existing rule is right;
  use worktree-absolute paths and re-export credentials in every call that needs them.
- One-offs, noted without action: `terraform fmt` exit 3; `pkill` exit 144; wrong test runner
  (`vitest` 127 — `plugins/soleur/test` is bun); three python anchor-count REFUSEs (the guard worked
  as designed); `lint-bot-statuses` red on descriptive prose (wrapped in `lint-infra-ignore`).

## Related

- `knowledge-base/project/learnings/2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`
- `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`
- `knowledge-base/project/learnings/best-practices/2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md`
- ADR-068 addendum 2026-07-27 (D1–D10); issues #6977, #6982, #6983
