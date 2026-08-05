# RESUME — #7277 D10 gate PASS condition

Updated 2026-08-05 (second session). Every command below was run; nothing is recalled.

---

## Paste this to resume

> Resume #7277 from PR #7290 (OPEN, **draft — do not mark ready**). Work in the existing worktree
> `.worktrees/feat-one-shot-7277-d10-gate-pass-condition`. Read
> `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/RESUME.md` first — a
> four-agent review found the gate **could not pass**, most blockers are fixed, and the remaining
> ones are listed there with file anchors. Finish the OPEN BLOCKERS section, re-run both suites
> plus the mutation batteries, then review → QA → compound → ship.

---

## State

| | |
|---|---|
| Branch | `feat-one-shot-7277-d10-gate-pass-condition` (pushed, 0 unpushed) |
| PR | **#7290** — OPEN, **DRAFT**. Body carries `Closes #7277`. |
| Suites | `test-registry-pull-path-health.sh` **46/0**, `test-registry-restore-from-ghcr.sh` **34/0** |
| Mutation | 15/15 (engine) + 13/13 (gate) caught — **must be re-run**, both files changed after |
| Exit gate | **VOID — must be re-run from scratch.** See "The exit gate result is not usable" below. |
| Net issue flow | 0 — closes #7277, files #7295 |

Phases 0–4 are committed. Phase 5 is **not** finished.

---

## The exit gate result is not usable — re-run it on a clean tree

A `bash scripts/test-all.sh` run reached **465 suites, 0 failed** at hand-off. **Do not read that
as a green exit gate.** It was launched at 16:52 against one tree, spent ~15 minutes queued on
another worktree's advisory lock, and then executed while the review fixes were committed
underneath it at **17:06:54** and **17:08:28**. Early suites read pre-fix files; later suites read
post-fix files.

That is the documented trap — an exit gate describes only the tree you launched it against, and if
an edit cannot wait you kill the run rather than reinterpreting its output. The rule exists
precisely because "each suite probably read a self-consistent snapshot" is reasoning, not
measurement.

**Re-run it on the final tree, with `git status --porcelain` empty, and do not edit under it.**
A run can sit at ~1130 bytes for many minutes because it is QUEUED on another worktree's advisory
lock — that is not a hang. Read the contention banner before killing anything.

### Process-matching cost three shells this session — use this recipe

`pgrep -f test-all`, the bracket trick `pgrep -f '[t]est-all\.sh'`, and matching on
`/proc/<pid>/cmdline` **all self-matched**, because the pattern string is itself present in the
matching command's own command line. Each time, the shell killed itself mid-command — once taking
an unwritten commit-message heredoc with it. What actually works:

```bash
SELF=$$; PARENT=$PPID
for p in $(pgrep -x bash); do
  [[ "$p" == "$SELF" || "$p" == "$PARENT" ]] && continue
  cwd=$(readlink "/proc/$p/cwd") || continue
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline")
  case "$cmd" in *"pgrep"*|*"readlink"*) continue ;; esac   # skip other scanners
  case "$cmd" in "bash scripts/test-all.sh"*) [[ "$cwd" == "$PWD" ]] && kill "$p" ;; esac
done
```

Exclude `$$`/`$PPID`, skip anything that is itself a scanner, anchor on the INVOCATION shape rather
than a bare substring, and confirm the sibling's PID is untouched afterwards. Also: never build a
commit message with a heredoc in the same Bash call as a command that can kill the shell — write it
with the Write tool first, then `git commit --file`.

---

## READ THIS FIRST — the shape of the mistake

The first session shipped a gate whose central claim was false. Four review agents
(`user-impact`, `silent-failure-hunter`, `observability-coverage`, `platform-strategist`) ran
against the pushed diff; **three independently found the same blocker**, and the pattern is worth
carrying forward:

> **Every suite was green, and every suite stubbed the thing that was broken.**

`ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` were validated non-empty and then never handed to crane, which
reads only the Docker keychain. So the rehearsal pushed **anonymously** into a `defaultPolicy: []`
sink → 401 → `DENIED` → exit 5 → A2 abort, deterministically, on every dispatch. The PR whose
entire purpose was "give the D10 gate a PASS condition" shipped a gate that could not pass. No test
caught it because every test injects a fake crane.

**The lesson to apply to the remaining work:** a stub proves the argv you chose, never the protocol
you speak. Anything that only a real registry, a real shell mode, or a real credential can falsify
needs a real exercise — the local throwaway-zot probe (see §0.9 in `phase-0-probe-evidence.md`) is
the pattern; it is cheap and it is what caught the `crane digest` fail-open in the first place.

---

## OPEN BLOCKERS — do these before anything else

### B1. A5 has no real probe, and the gate now REFUSES without one

**Current state is deliberately fail-closed and therefore currently unfireable in CI.**
`scripts/registry-pull-path-health.sh` aborts A5 when no probe is configured (`no sink probe is
configured`). That is honest — an unwired predicate cannot fire, and shipping one is the
dark-operand defect this whole change exists to remove — but it means **the workflow must wire a
real probe or the gate always refuses**.

Wire `REGISTRY_SINK_PROBE_CMD` (the production knob; deliberately NOT a `REGISTRY_GATE_*` seam,
because the seam guard refuses those inside Actions). The probe must emit exactly one bare token on
stdout: `ok` | `credential_rejected` | `wrong_digest` | anything else (→ degrade).

It needs the CF Tunnel bridge up in the recut job (`./.github/actions/cf-tunnel-registry-bridge`,
already used by `registry_store_restore`), then one `crane copy` of an already-present ref — crane
skips blobs the destination holds, so it is near-idempotent.

**Alternative, if the budget cost is judged too high:** delete A5 outright and say plainly in
ADR-169 and the plan that the destroy is authorized *without observing the sink*. That is a real
regression (plan review R2 added A5 precisely to stop that), so it is a decision to record, not a
silent drop. **Do not** leave A5 present-but-dark.

### B2. The rehearsal probably should not run inside the mutex-holding job

`platform-strategist`: `registry_luks_recut`'s `timeout-minutes: 30` is load-bearing because it
holds the **workflow-level** apply mutex and D11's 630 s bound must sit below it. The rehearsal
(multi-GB, wall-clock **unmeasured** — Phase 0.4) now runs *ahead of the apply* inside that budget.
A rehearsal that succeeds *slowly* subtracts from the post-destroy window, pushing a timeout into
`terraform apply` or D11, where it is catastrophic.

Options: move the rehearsal to a `needs:`-preceding gate job (does not release the mutex, but
restores the invariant — the recut's clock starts at the apply), or raise the 30 with the unmeasured
term stated explicitly. **Do not leave the comment at `:1888-1891` asserting an invariant that no
longer holds.**

### B3. Cheap denies still run after the expensive proof

`terraform init`/`plan`, the sourced `registry_luks_recut_gate` (`volume_id_mismatch`,
`out_of_scope`, `luks_key_touched`), `stock_preflight_gate` and the zero-touch assert are all
~1–2 min pre-destroy denies sitting **behind** the multi-GB rehearsal. Nothing in the rehearsal needs
`tfplan.json`, so `init` + `plan` + the guards can be hoisted. Tradeoff to state explicitly: it
widens the plan→apply gap by the rehearsal's duration against a lock-less R2 state.

### B4. `soleur-inngest-config` — the "measured absent" claim is wrong

The gate asks for tag `latest`; `build-inngest-config-bundle.yml` publishes `v${VERSION}` and the
promoted ref is a **Terraform digest pointer** (`apps/web-platform/infra/inngest-config-digest.tf`,
`TF_VAR_inngest_config_digest`). So the entry classifies NOTFOUND forever and is skipped by design.
The plan's "not published at GHCR (measured — `crane ls` returns `NAME_UNKNOWN`)" used the **tags**
API without credentials, which is exactly the ambiguity both scripts document everywhere else.

Re-measure with a credentialed digest read against the promoted digest; if it resolves, promote to
`required`, raise `FLOOR`, and **correct the claim in the plan and in ADR-169**.

### B5. Manifest divergence — rehearsal and real restore can consume different inventories

PREPARE writes `${RUNNER_TEMP}/restore-pins.json` and uploads it; VERDICT then re-derives over the
**same path after the upload**; the restore job downloads the PREPARE artifact. A deploy landing in
between (the window spans the stock probe, two docker pulls and up to 40 s of readiness polling)
means the rehearsal proves set B while the restore restores set A, both green.

Fix: upload the artifact **after** VERDICT, or have VERDICT consume PREPARE's manifest instead of
re-deriving. Emit the manifest `sha256` in the verdict line either way.

---

## Lower-severity, still open (all file-anchored in the agent reports)

- **Exit 1 is reachable and unenumerated.** Ten `die 1` sites in the engine cover real manifest-shape
  faults; both consumers call it "unenumerated … a defect worth filing", sending the operator to file
  a bug about a correct diagnosis. Add a `1)` arm + a runbook row, or recode those to `6`.
- **`classify()` diverges between the two scripts.** The gate's copy lacks `connection reset`,
  `BLOB_UNKNOWN`, `502/503/504`. A TCP reset during A1 — the literal text of the motivating incident
  — classifies `UNKNOWN` and deadlocks the recut.
- **`*"EOF"*` in the NETWORK arm** is a 3-char substring match that converts unclassifiable failures
  into retryable sink outages, downgrading exit 6's loudest-arm guarantee.
- **`last_err` takes the last 400 *bytes*, not the last *line*,** despite the classifier's stated
  contract of classifying on the last line.
- **Manifest write guard tests only the last `printf`** — a brace group's status is its last command,
  so a failing `paste`/ENOSPC yields a truncated manifest at exit 0.
- **`shift 2` with a missing flag value spins forever** (both scripts). `--target` with no value hangs
  to the job timeout and is *cancelled*, not failed — no `::error::`.
- **Unguarded greps in the throwaway step** die at the assignment under `-e`, one line before the
  `::error::` written to explain that exact input. The readiness loop's exhaustion is unchecked, so a
  zot that never bound reports "the throwaway registry accepted an unauthenticated request (000)".
- **Signature reads are the only unclassified reads** in the engine — a GHCR 503 reports "no cosign
  signature found" (exit 4, non-retryable) for what is an availability fault (exit 2).
- **No runner-disk preflight.** ~2.5 GB against ~20 GB today, but linear in `FLOOR` (now 4, was 2) and
  doubles if arm64 lands (#6460). A full store makes zot answer 500, which classifies `UNKNOWN` → a
  runner-local fault reported in the vocabulary of a restore-engine defect.
- **`discoverability_test.command` in the plan does not work** — `--job` takes a numeric ID, it is
  scoped to the wrong job, and the grep matches neither the predicate lines nor the per-entry lines.
- **Runbook orphaned tail** — still calls the gate "the file whose refusal blocks the runbook" and
  quotes a "DISPOSABLE GHCR MIRROR" phrase that is no longer in the rewritten header.
- **"re-run that job" has no command** at four sites, after an irreversible destroy.
- **#7295 is referenced nowhere in-tree**; the three out-of-diff sites still telling operators to rely
  on `ghcr-fallback` (`scheduled-zot-restart-loop.yml`, `zot-registry-revert.md`,
  `zot-soak-6122.sh`) carry no marker.

---

## What IS solid (do not re-litigate)

- **Probe 0.9**, with its negative control: `crane digest` returns rc 0 PASS on a blob-evicted image;
  `crane validate --remote` returns `BLOB_UNKNOWN`. Measured against a real throwaway zot.
- **Phase 0.3**: the GHCR signature is a Sigstore **bundle v0.3** bound to the digest, so copying is
  sound and the job needs no `id-token: write`.
- **A5's abort/degrade boundary** (availability degrades, authorisation/correctness aborts), pinned
  in both directions.
- The green row, the distinctness guard, the seam guard, `FLOOR=4` and its derivation.
- ADR-169, the ADR-096 amendment (clause (g) open, `unowned constraint` still 2, Status `Adopting`),
  the runbook rewrite, the C4 edges + re-render (both C4 gates green).

## Gates

```
bash tests/scripts/test-registry-pull-path-health.sh     # 46/0
bash tests/scripts/test-registry-restore-from-ghcr.sh    # 34/0
bash scripts/test-all.sh                                 # RE-RUN — was mid-flight at hand-off
actionlint .github/workflows/apply-web-platform-infra.yml
grep -c "no valid PASS condition" scripts/registry-pull-path-health.sh   # must be 0
```

**Re-run both mutation batteries** — the engine and the gate both changed materially after the last
run, and the batteries are what caught five of the original gaps.

**ADR-169** was next-free at 2026-08-05 (168 highest, 167 absent). Re-derive against freshly-fetched
`origin/main` before merge.
