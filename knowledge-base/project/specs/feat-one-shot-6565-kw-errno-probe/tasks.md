---
feature: feat-one-shot-6565-kw-errno-probe
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-16-chore-login-kw-errno-probe-round-plan.md
tracker: Ref #6565
brand_survival_threshold: single-user incident
created: 2026-07-16
---

# Tasks — name the errno: six hardcoded probes in `_login_kw`

> **Scope:** six `case` probes in `apps/web-platform/infra/ci-deploy.sh` + their tests. **Nothing else.**
> **Do NOT repair the underlying login failure.** The instrument exists to stop guessing; the repair
> follows the named errno.
>
> **Path correction:** the task brief said `scripts/ci-deploy.sh`. That file does **not exist**. The real
> path is `apps/web-platform/infra/ci-deploy.sh`.

## Phase 0 — Preconditions (already measured; re-confirm only if you doubt them)

- [x] 0.1 Confirm the six Go errno literals are byte-exact. Measured 2026-07-16 against `go1.21.6`
      (`syscall.Errno.Error()`), **lowercase** — Go's table, **not** `strerror(3)`'s capitalized form:
      | errno | literal | len |
      |---|---|---|
      | ENOMEM | `cannot allocate memory` | 22 |
      | EROFS | `read-only file system` | 21 |
      | ENOENT | `no such file or directory` | 25 |
      | EINVAL | `invalid argument` | 16 |
      | EIO | `input/output error` | 18 |
      | EPERM | `operation not permitted` | 23 |
- [x] 0.2 Read `apps/web-platform/infra/ci-deploy.sh` › `_login_kw` (~line 669) and its header comment
      (~line 639) before editing (`hr-always-read-a-file-before-editing-it`). The header is the surface's
      threat model — Form B is load-bearing, not style.

## Phase 1 — RED: T-5B-20 (must precede Phase 2)

`KW_BODY` is set at **T-5B-15** (`ci-deploy.test.sh:3865`); T-5B-16 (`:3897`) is what *sources* the
emitters. Place T-5B-20 after both.

**T-5B-20 has TWO assertion families with OPPOSITE sourcing rules. Do not collapse them.**

- [x] 1.1 **(a) Firing assertions — fixture literals HAND-WRITTEN.** For each of the six
      `(literal, token)` pairs, assert
      `_login_kw "error saving credentials: open /home/deploy/.docker/config.json123456789: <literal> ${T16_KW_CANARY}"`
      **contains** `<token>,`. The path/suffix is **decorative** — the arms are path-agnostic.
- [x] 1.2 **NEVER derive the firing fixture from `KW_BODY`.** Measured: with a typo'd source arm
      (`read only file system`), a derived fixture feeds the typo back in, the arm fires, and the test is
      **GREEN with the bug**. A hand-written `read-only file system` goes **RED**. The fixture's
      independence from the source **is** the test. This file's *"derive the oracle from the SUT"* precedent
      (`:3922-3928`) is correct for `T16_CLOSED` and **must not** be applied here — leave a comment saying
      so, or a reviewer will "fix" it into a tautology.
- [x] 1.3 Assert every output satisfies the closed-form oracle `^([a-z]+,)*$`.
- [x] 1.4 **(b) Whole-vocabulary invariants — these ARE derived from `KW_BODY`** (so they span arm #17):
      every literal (i) contains a character outside `[A-Za-z0-9]` — the alphabet invariant, closing the
      predicate channel; (ii) is **lowercase** — directly asserts the Sharp Edge #1 class (Go's table vs
      `strerror(3)`'s capitalized form); (iii) appears in a canary-carrying fixture.
- [x] 1.5 Run the suite. **Expect RED — output is `errsaving,` alone, NOT zero tokens** (every fixture
      starts with `error saving credentials:`, so that arm fires first). RED because `enomem,` etc. are absent.
      > **Why the ordering is load-bearing (plan D4, proven by execution):** with an arm removed, output
      > degrades to `errsaving,`, which **passes** the closed-form oracle. A canary fixture alone is GREEN
      > on a missing or typo'd arm. Only the firing assertion catches a dead probe.
- [x] 1.6 **Re-run T-5B-14** (`:3828`) — it asserts `kw=` is **EMPTY** and is the test most exposed to a new
      arm; it survives only on its fixture's wording. Also re-run T-5B-17. Verify, do not assume.

## Phase 2 — GREEN: the six probes

- [x] 2.1 Append to `_login_kw` in `apps/web-platform/infra/ci-deploy.sh`, **below** the measured arms and
      **above** the falsified ones, under its own comment block marking the class as INFERRED-not-measured:

      ```bash
      case "${1:-}" in *'cannot allocate memory'*)    printf 'enomem,' ;; esac
      case "${1:-}" in *'read-only file system'*)     printf 'erofs,' ;; esac
      case "${1:-}" in *'no such file or directory'*) printf 'enoent,' ;; esac
      case "${1:-}" in *'invalid argument'*)          printf 'einval,' ;; esac
      case "${1:-}" in *'input/output error'*)        printf 'eio,' ;; esac
      case "${1:-}" in *'operation not permitted'*)   printf 'eperm,' ;; esac
      ```
- [x] 2.2 **`case`, never `grep -q`.** Verified under `set -euo pipefail`: `case` non-match → rc=0 (cannot
      abort); top-level `grep -q` non-match → exit 1 → **aborts the deploy**. This is the dominant abort
      class the instrument was built to survive.
- [x] 2.3 Every `printf` takes a **hardcoded literal**. No parameter expansion but `${1:-}` anywhere in the
      body (Form B). A Form-A filter that re-emits its input degrades to **credential disclosure**.
- [x] 2.4 Run the suite. **Expect GREEN** (T-5B-20 passes).

## Phase 2b — the change FALSIFIES two comments. Update both, same commit.

- [x] 2b.1 `ci-deploy.sh` › `_login_kw` header: *"Every literal below is MEASURED … except the last three"*
      — **false** once six **inferred** arms land (neither "measured" nor "the last three").
- [x] 2b.2 `ci-deploy.test.sh:3900-3903`: *"Every literal here is a string the /work Phase 0 battery
      measured out of a real `docker login`"* — **false**; the six new fixtures are inferred from arithmetic.
- [x] 2b.3 Introduce an explicit **INFERRED** class in both, alongside MEASURED and FALSIFIED. Shipping the
      arms while these comments still claim "every literal is measured" is exactly the false-comment defect
      this PR's discipline exists to drain — it would be this PR restating it.

## Phase 3 — Follow-through reporting line (plan D6 — flag for operator veto)

- [x] 3.1 Add ONE line to `scripts/followthroughs/zot-login-gate-names-failure-6497.sh`, beside the existing
      `Observed docker_ver … record on #6565` echo (`:116-117`):
      ```bash
      echo "Observed kw (the errno datum — record on 6565):" \
        "$(printf '%s\n' "$FAILED_LINES" | grep -oE 'kw=[a-z,]*' | sort -u | tr '\n' ' ')"
      ```
- [x] 3.2 **Reporting only** — after the PASS/FAIL decision; it cannot flip the verdict. Form-B-safe:
      `kw=[a-z,]*` reads a closed-vocabulary field over a closed alphabet, so it cannot echo stderr. The
      three-state invariant logic is **untouched**.
- [x] 3.3 **Why this is not optional:** the probe is the **only** automated reader of these lines and is
      **single-shot** — it PASSes on the current datum, comments, then the sweeper auto-closes issue 6497
      (`sweep-followthroughs.sh:233,272`), and never runs again. It reports `class` + `docker_ver` but
      **not `kw`** — it would drop this round's entire deliverable. It already echoes `docker_ver` with
      "record on #6565", so it is already a datum-reporting channel.

## Phase 3b — `errno_chars` (plan D7) — **OPERATOR APPROVED 2026-07-17; not in the original brief**

This phase did not exist when tasks.md was written — D7 was still awaiting sign-off. The operator approved
it together with D6. It is the field that actually ends the guessing; the six arms only ask "is it ENOMEM?".

- [x] 3b.1 In `apps/web-platform/infra/ci-deploy.sh` › `_login_hatch`, take the final `": "`-delimited
      segment by expansion and print its LENGTH beside `stderr_chars`:
      ```bash
      _errseg="${_e##*: }"      # expansion only — no subprocess; the TEXT never leaves the function
      # printf … stderr_chars=%s errno_chars=%s …   "${#_e}" "${#_errseg}"
      ```
- [x] 3b.2 **Not Form-B constrained** — this is `_login_hatch`, not `_login_kw`/`_login_tok`, so T-5B-15's
      "no expansion but `${1:-}`" grep does not apply. It sits exactly where `stderr_chars` already sits and
      prints a LENGTH, never content.
- [x] 3b.3 **Re-confirm the no-echo residual, do NOT inherit it.** D7 narrows the segment vs `stderr_chars`,
      and a narrower segment is a priori a sharper oracle — so the argument must be re-run. It re-runs clean:
      a fixed-length token substituted into the segment yields a CONSTANT length ⇒ zero bits about content
      (the property turns on fixed-ness, not on any number). A username there costs `len(username)` — the
      same already-accepted residual `stderr_chars` carries. **The `stderr_chars` bucketing TRIGGER governs
      this field too.**
- [x] 3b.4 **The measured property that justifies it** (verified at /work, not reasoned): `errno_chars` is
      **invariant under docker's uint32 temp suffix**. The live datums were `stderr_chars=96` (zot) and `97`
      (ghcr) — it took arithmetic to conclude those were the identical error. `errno_chars` reports **22 for
      both**. It skips the inference the whole round was built to make.
- [x] 3b.5 T-5B-21 pins it: both live datums reproduce (96 AND 97 → errno_chars 22), invariance asserted
      explicitly, degenerate no-colon input renders `errno_chars == stderr_chars`, empty → 0, and a
      final-segment canary must not appear in the emit.
- [x] 3b.6 Report it from the follow-through probe alongside `kw` (D6) — same single-shot argument.

## Phase 4 — Verify

- [x] 4.1 **`bash apps/web-platform/infra/ci-deploy.test.sh` → all green.** This is the real gate (plan AC3);
      it subsumes T-5B-15 / T-5B-16 / T-5B-19. **Do not hand-copy their oracle pipelines into a checklist** —
      a second copy of an oracle drifts from the test it restates, which is the defect T-5B-16's own comment
      block warns about.
- [x] 4.2 **Sanity-only (NOT a gate): no abort vector in the emitter.** If you spot-check for `grep -q`,
      **strip comments first** — Phase 2's own comment block says *"case, never `grep -q`"*, so a bare-token
      body-grep matches that prose and **false-FAILs** (`cq-assert-anchor-not-bare-token`; T-5B-19 at `:4095`
      does the comment-strip and explains why). Note `grep -c` exits **rc=1** on a zero count — the exact
      non-match-returns-1 abort class this instrument was built around; never chain it under `set -e`.
- [x] 4.3 **Scope** (plan AC1): `git diff --stat origin/main...HEAD` touches exactly **three** files —
      `ci-deploy.sh`, `ci-deploy.test.sh`, `zot-login-gate-names-failure-6497.sh` (the D6 line). No `.tf`,
      no `.service`, no `cloud-init*`, no Doppler.
- [x] 4.4 **The follow-through's three-state invariant LOGIC is unmodified** (plan AC5). Reporting-only
      additions are permitted — that is D6/Phase 3.
      > **Do NOT assert `git diff -- scripts/followthroughs/` is empty.** An earlier draft did, and it
      > directly contradicted Phase 3: the "unmodified" form wins by being mechanically checkable, which
      > would ship the round with its own deliverable unreadable by the only automated reader. Verify
      > instead that the probe still asserts `rc`/`class`/`*_chars`, still does **not** assert `kw`
      > non-empty (an empty `kw` is itself the H-D datum), and that **no assertion changed**.

## Phase 5 — Ship (PR body discipline — the deliverable's story)

- [ ] 5.1 Tracker link uses the **`Ref`** form (never a close-keyword). Issue 6565 is the **repair**; this
      PR does not repair, so a close-keyword link would manufacture a false-resolved state at merge.
- [ ] 5.2 **No close-keyword adjacent to 6497 / 6400 / 6525 / 6560 / 6565** in the commit message, PR title,
      or PR body. GitHub's parser is **negation-blind** and reads the squash commit body. Verify:
      `gh pr view --json title,body -q '.title + "\n" + .body' | grep -inE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[[:space:]]*:?[[:space:]]*#?(6497|6400|6525|6560|6565)\b'` → **no output**
- [ ] 5.3 PR body states plainly: **nothing is broken**; the instrument shipped 2026-07-15 and is working;
      prod is serving (`soleur.ai` 200); the zot gate is **fail-open by design**.
- [ ] 5.4 PR body carries the **corrected decomposition** — (A) cred-store write fails **continuously** on
      both registries; (B) `image_pull_failed` is **intermittent** and **predates** the instrument's merge.
- [ ] 5.5 PR body carries the **retraction**: the strong form ("one broken credential store explains BOTH")
      is **falsified by execution** — the `39a4bb8d` deploy went green (deploy + live-verify) while the
      login was still failing at 20:53Z. Show the retraction; do **not** quietly omit it.
- [ ] 5.6 PR body carries the surviving mechanism as a **HYPOTHESIS**, not a claim: login fails at the
      **store write**, i.e. **after** auth succeeded, so a previously-baked `config.json` keeps pulls working
      until it goes stale. Name the **shape-mismatch (continuous A vs intermittent B)** explicitly as the
      thing the hypothesis must explain away.
- [ ] 5.7 All three leads labelled **LEADS**, not claims. `e3a5bab21` labelled **class-evidence** for the
      sandboxing family — **not** a cause, and not grounds to pre-empt the probe.
- [ ] 5.8 Do **not** widen scope: 6400 / 6525 / 6560 stay open and untouched.

## Phase 6 — Post-merge

- [ ] 6.1 `apply-deploy-pipeline-fix.yml` (path filter `:66` carries `ci-deploy.sh`) applies on merge.
      Verify: `gh run list --limit 100 --workflow apply-deploy-pipeline-fix.yml`
      (**`--limit 100`** — the default is 20; the prior merge produced 33 runs). The workflow asserts a
      **count** (`files_written == files_total`), not per-file presence.
- [ ] 6.2 **A deploy must actually RUN — merging is not deploying.** The *"Redeploy to load applied
      profile"* step fires **only when the running container's loaded seccomp profile differs from
      committed** (`:200-201`). A `ci-deploy.sh`-only merge **no-ops** it: the probe lands on web-1 and
      **sits** until the next independent web-platform release (which #6400/#6525/#6560 report failing
      ~60%). **Do not claim "the next deploy is guaranteed."** Confirm a release ran before reading 6.4.
- [ ] 6.3 Read the gate line (**no SSH**):
      ```bash
      doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
        --since 90m --grep ZOT_GATE --grep PRELUDE
      ```
      `--since 90m` parses; a bare `--since 60` silently degrades to `WHERE dt >= '60'`. Rows are
      `{dt, raw}`; `raw` is a JSON **string**; the text is `raw.message`, **not** `raw.MESSAGE`.
- [ ] 6.4 **Apply the six-branch verdict rule.** A 2-state rule over a ≥5-state space is how a
      false-resolved reading happens:
      | observation | verdict | action |
      |---|---|---|
      | **zero rows** | **TRANSIENT — not a result** | **Worst misread available; MOST LIKELY given 6.2.** Absence of data ≠ "the failure stopped". Re-query after a confirmed release. **Never read as resolved.** |
      | lines present, **all success** | **premise (A) FALSIFIED** | Major datum — the continuous failure stopped on its own. Record on 6565; re-open the diagnosis. |
      | **exactly one** new token + `errsaving` | **NAMED** | Record on 6565; open the repair. **Only this branch authorises a repair.** |
      | **two or more** new tokens | **NOT named** — wrapped chain (reachable: `errsaving,erofs,eperm,`) | Record the full `kw` + chain shape. **Do NOT open a repair.** |
      | a new token **without** `errsaving` | **NOT named** — unmodelled | Record verbatim; the `cred_store` framing itself is in question. |
      | `errsaving` **alone** | **NOT named** — seventh shape | A **datum, not a regression**. See plan D7 (`errno_chars`). |
- [ ] 6.5 Record on issue 6565 by **comment, with no close-keyword**. Four of six branches are data, not
      repairs. **None is a failure of this PR.**
