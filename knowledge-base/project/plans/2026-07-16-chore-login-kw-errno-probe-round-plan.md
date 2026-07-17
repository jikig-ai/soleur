---
type: chore
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-6565-kw-errno-probe
tracker: Ref #6565
created: 2026-07-16
---

# chore(infra): name the errno — six hardcoded probes in `_login_kw`

> **Lane note:** no `spec.md` for this branch — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Add **six hardcoded errno literals** to `_login_kw` in `apps/web-platform/infra/ci-deploy.sh`, so the next
real deploy names the credential-store failure's errno instead of reporting `kw=errsaving` alone.

**This is a diagnosis continuation, not a repair of a regression.**

- Nothing is broken. The instrument shipped 2026-07-15 and is **working** on web-1.
- Production is **serving** (`soleur.ai` 200). A failed deploy leaves the prior version running.
- The zot gate is **fail-open by design**: a login failure drops to the GHCR path. That degrades the zot
  migration, not the site — **but see the honest version of this claim below**; the GHCR path is itself the
  one #6400 / #6525 / #6560 report failing ~60% of the time, so it is not a clean fallback. It is still not
  an outage: a failed deploy leaves the prior version serving. **Stale code, not downtime.**

**Do NOT repair the underlying failure in this PR.** The point of the instrument is to stop guessing.
Repair the ONE named mode only after the probe reports.

### The diff

```bash
case "${1:-}" in *'cannot allocate memory'*)    printf 'enomem,' ;; esac
case "${1:-}" in *'read-only file system'*)     printf 'erofs,' ;; esac
case "${1:-}" in *'no such file or directory'*) printf 'enoent,' ;; esac
case "${1:-}" in *'invalid argument'*)          printf 'einval,' ;; esac
case "${1:-}" in *'input/output error'*)        printf 'eio,' ;; esac
case "${1:-}" in *'operation not permitted'*)   printf 'eperm,' ;; esac
```

Form B — hardcoded literals, structurally incapable of echoing the stderr back out. Plus their tests, plus
**one reporting line** in the follow-through probe (see Files to Edit / D6).

**Why six — and the honest limit of six (read this before defending the number).** Under the plan's own
22-char arithmetic, **only ENOMEM fits** — measured lengths are ENOMEM **22**, EPERM 23, EROFS 21, EIO 18,
EINVAL 16, ENOENT 25. So the other **five are reachable only if the 22-char premise is wrong**. And if that
premise is wrong (the verb is not `open()`, or the path is not 32 chars — both read from code, neither
observed), the errno is unconstrained across **~130** errnos and six guesses is a **~5%** shot.

Six is therefore **not** "the plausible set" — it is ENOMEM (the premise's answer) plus five cheap hedges
against the premise itself. That is worth six lines, but it does **not** make the round likely to succeed if
the premise is wrong. **This is the argument for D7 (`errno_chars`)** — one field that bounds all ~130 in a
single round *and* tests the premise instead of assuming it. Do not defend "six" as principled; defend it as
cheap.

---

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified 2026-07-16) | Response |
|---|---|---|
| Edit `scripts/ci-deploy.sh` | **FALSE — no such file.** Real path: `apps/web-platform/infra/ci-deploy.sh` | Corrected throughout |
| Six errno literals as written | **MEASURED verbatim** via `go1.21.6` `syscall.Errno.Error()` | Pinned; see Phase 0 |
| ENOMEM = 22 chars → total 96/97 | **MEASURED.** `26+5+32+9+2+22 = 96`; suffix 10 → **97**. Exactly the observed values | Arithmetic confirmed |
| EROFS (21) needs an 11-digit suffix | **MEASURED** — EROFS totals 95/96, so it needs suffix 10/11; 11 is impossible | Lead 2's own objection holds |
| `ProtectHome=read-only`, `/home/deploy` not in `ReadWritePaths` | **VERIFIED, both copies** — `cloud-init.yml:247-262`, `webhook.service:16,20,48` | Lead 2 config-verified; still a LEAD |
| Strong form: one broken cred store explains BOTH | **FALSIFIED BY EXECUTION** | Retracted; weak form carried as hypothesis |
| Issue 6565 is the target | OPEN, titled *"repair the … login failure"* | **This PR does not repair** → `Ref` form only (D3) |
| 6400 / 6525 / 6560 / 6497 open | **Verified** — all five (incl. 6565) OPEN | All stay open |

**Premise validation:** the premise (`kw=errsaving` alone ⇒ the errno matches none of the ten probed
literals) **holds** — `_login_kw` (`ci-deploy.sh:669-691`) probes ten; none is an errno string. H-D is the
case the hatch exists for. The change is additive.

---

## The measured datum

```
class=cred_store rc=1 stderr_chars=96 stdout_chars=0 kw=errsaving tok=error docker_ver=29.3.0   (zot)
class=cred_store rc=1 stderr_chars=97 stdout_chars=0 kw=errsaving tok=error docker_ver=29.3.0   (ghcr)
```

Settled by execution — **do not re-litigate**: `kw=errsaving` fired alone ⇒ H-D. The 96/97 delta is docker's
`uint32` temp suffix (9 or 10 digits; 11 impossible), so both registries are the **identical** error ⇒ it is
web-1's credential store, not registry-specific. The arithmetic pins the errno to **22 chars**, and only
ENOMEM fits `open()` on a local file.

**But that is INFERENCE, not measurement** — it rests on the verb being `open()` and the path being 32
chars, both read from code, neither observed. **That gap is why the probe ships instead of a fix.**

Eliminated by evidence, do not revisit: htpasswd causation (08:15Z re-bake), the `cli_daemon` arm, H-A,
H-B, H-C (`root_avail: 70G`). `docker_ver=29.3.0` is the first read of the host's unpinned docker (prior
measurements were 29.4.3); **the arms hold across the gap**.

---

## Leads — LEADS, not claims

1. **ENOMEM.** zot-registry host right-sized cx33 8GB → cx23 4GB at 08:13Z; `login_failed` began 08:27Z,
   14 min later. **But this cannot explain the GHCR half** (web-1's *local* cred write). Two effects, or
   coincidence.
2. **EROFS.** `webhook.service`: `ProtectHome=read-only`, `User=deploy`, `/home/deploy` **not** in
   `ReadWritePaths`; `docker login` writes `$HOME/.docker` with no `--config`. **Config-verified this
   session.** Mechanically compelling **but** needs an impossible 11-digit suffix, and `ProtectHome` landed
   months ago (#1551) — so it is not the trigger.
3. **Systemd-sandboxing prior art — CLASS-EVIDENCE ONLY.** Commit `e3a5bab21` (verified: ancestor of
   `origin/main`, *"heartbeat unit needs PrivateTmp=true — root-owned /tmp/.doppler killed it"*) shows unit
   sandboxing directives on these hosts **do** cause real filesystem-write failures in prod. It does **not**
   transfer mechanically: `PrivateTmp` governs `/tmp`; docker writes into `$HOME/.docker/`. It raises the
   prior on lead 2. **Not a cause. Not grounds to pre-empt the probe.** The `erofs` token covers this arm.

---

## The self-correction — a retracted claim, carried honestly

**The strong form is dead.** The earlier framing — *"a failed credential write leaves the subsequent GHCR
pull unauthenticated; one broken credential store explains BOTH the zot login failure and the ~60% pull
failures"* — is **falsified by execution**: the `39a4bb8d` deploy **succeeded** (deploy + live-verify both
green) while the login was **still failing** at 20:53Z. If a failed cred write made the pull
unauthenticated, that deploy could not have gone green.

### The corrected decomposition — write THIS

- **(A)** The cred-store write fails **continuously**, on **both** registries. This is what the probes pin.
- **(B)** `image_pull_failed` is **intermittent** (17:05Z, 17:52Z, 20:21Z, interleaved with successes) and
  **predates the instrument's merge** — v0.218.4 and v0.218.6 both fired before #6528 landed.

Different shapes — continuous vs intermittent. **"A causes B" is dead.**

### The surviving weak form — a HYPOTHESIS

B *may* still be downstream of A: `docker login` fails at the **store write**, i.e. **after** auth already
succeeded, so a previously-baked `config.json` keeps pulls working until it goes stale — which would explain
B's intermittency without a second cause. **State it as a hypothesis**, and name the **shape-mismatch
(continuous A vs intermittent B) as the thing it must explain away.** Do **not** let it harden into a claim
— the first version hardened exactly that way and had to be retracted, which is the error this PR's whole
discipline exists to prevent. **Do not act on it:** 6400 / 6525 / 6560 stay open and untouched.

**PR-body framing:** the self-correction *is* the deliverable's story. The instrument's value is that it
falsifies the operator's own reasoning — **including the reasoning that motivated it**. Show the retraction;
do not quietly omit it.

---

## User-Brand Impact

**If this lands broken, the user experiences:** two modes, one benign and one not.
*Benign* — a typo'd literal never matches, the next deploy reports `kw=errsaving` alone again, and the round
is wasted (~24h more of zot degraded). Guarded by AC2.
*Not benign* — the probe fires **wrongly** and manufactures a false errno of record. A repair built on it
ships to **every web host** through `apply-deploy-pipeline-fix.yml` with no operator step and no apply-time
gate. **A false-confident match is categorically worse than no match**, and it is the same class as the
htpasswd causation and the retracted strong form. Guarded by AC5's multi-token branch.

**Standing condition (not caused by this diff):** the fail-open drop lands on the GHCR path, which
#6400 / #6525 / #6560 report failing ~60% of the time. So merged `apps/web-platform` changes — including
security fixes — may not reach `soleur.ai`, leaving users on the prior version. Pre-existing; **stale code,
not an outage**; scoped out here, untouched by this diff.

**If this leaks, the user's credentials are exposed via:** `_login_kw` receives **raw `docker login`
stderr**, which may carry `ZOT_PULL_TOKEN` / the GHCR PAT (a registry echoing the credential, an argv or
path echo, a helper's error text). A Form-A splice in any arm sends that to journald → Vector → **Better
Stack unscrubbed** (and Sentry on the zot arm, `ci-deploy.sh:1289`). **A leaked GHCR read credential is a
supply-chain path to every end user of the web platform.**

> **The asset is the TOKEN, not the username.** `ci-deploy.sh:766-768` records that the username is a
> *declared non-secret* — `ZOT_PULL_USER` is a constant and the GHCR username is public as the package
> owner — so its disclosure is **already accepted, not overlooked**. Naming the username as the asset would
> invite a future reader to conclude the risk is minor (it's public) and loosen Form B. The supply-chain
> claim survives on the **token**.

**Second channel — `kw` is a PREDICATE channel, not just an echo channel.** Each arm's firing is a one-bit
statement about the stderr's content, and `kw` now carries up to 16 such bits to an unscrubbed sink. That is
safe today because **every literal contains a character outside `[A-Za-z0-9]`** — the credential alphabet
(zot: `random_password length=40 special=false` ⇒ `[A-Za-z0-9]{40}`, `zot-registry.tf:144-145`; GHCR PAT:
alnum + `_`) — so no substring of a credential can ever match an arm. **Verified: all 16 literals pass.**
But that is safe *by accident of English*, not by construction: a future short-alnum probe (`*'403'*`,
`*'ghp'*`) would condition firing on credential content, and T-5B-15, T-5B-16 and T-5B-20 would **all pass**.
AC4 converts this into an asserted invariant, mirroring the alphabet reasoning already at
`ci-deploy.sh:748-763`.

**Brand-survival threshold:** `single-user incident`

The threshold is a property of the **surface**, not the diff size. `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review time.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | +6 `case` probes in `_login_kw`, in a new INFERRED-errno block |
| `apps/web-platform/infra/ci-deploy.test.sh` | +T-5B-20 (per-arm firing, canary-carrying, KW_BODY-derived); +alphabet invariant |
| `scripts/followthroughs/zot-login-gate-names-failure-6497.sh` | **+1 reporting line** (`Observed kw:`) — see D6 |

**NOT edited:** `webhook.service`, `cloud-init.yml`, any `.tf`, any Doppler value. **No behaviour changes on
the host** beyond one telemetry field.

**Delivery:** `apply-deploy-pipeline-fix.yml:66` carries `ci-deploy.sh` in its path filter and applies on
merge. **No operator step, no SSH.** Failure mode (A) is **continuous**, so the next deploy exercises it.

---

## Implementation Phases

### Phase 0 — Preconditions (measured, not assumed)

Six literals measured against `go1.21.6` (`syscall.Errno.Error()`) — **lowercase (Go's table), NOT
`strerror(3)`'s capitalized form**:

| errno | literal | len | | errno | literal | len |
|---|---|---|---|---|---|---|
| ENOMEM | `cannot allocate memory` | **22** | | EINVAL | `invalid argument` | 16 |
| EROFS | `read-only file system` | 21 | | EIO | `input/output error` | 18 |
| ENOENT | `no such file or directory` | 25 | | EPERM | `operation not permitted` | 23 |

Read `_login_kw` (~line 669) **and** its ~45-line header (~line 639) before editing
(`hr-always-read-a-file-before-editing-it`). The header is the threat model; Form B is load-bearing.

### Phase 1 — RED: T-5B-20 (must precede Phase 2)

Add after **T-5B-15** (which sets `KW_BODY` at `ci-deploy.test.sh:3865`) and after T-5B-16 sources the
emitters (`:3897`).

**T-5B-20 carries TWO assertion families with OPPOSITE sourcing rules. Getting this backwards silently guts
the test — measured, not theorised (see Research Insight 8).**

**(a) Firing assertions — fixture literals are HAND-WRITTEN. NEVER derive these from `KW_BODY`.**

1. the arm **fires** on its literal (`_login_kw "error saving credentials: … <literal>"` contains `<token>,`);
2. the output satisfies the closed-form oracle `^([a-z]+,)*$`;
3. the fixture carries `${T16_KW_CANARY}` (leak guard folded in — no separate fixture phase).

> **DO NOT "FIX" THIS INTO A DERIVED ORACLE.** This file carries a loud, correct *"the oracle is DERIVED
> from the SUT, never hand-copied"* precedent (`:3922-3928`) for `T16_CLOSED`, and a reviewer will reach for
> it here. **It does not apply to a firing assertion.** Measured: with a typo'd source arm
> (`read only file system`), a `KW_BODY`-derived fixture feeds the typo back in, the arm fires, and the test
> is **GREEN with the typo undetected**. A hand-written `read-only file system` goes **RED**. Deriving makes
> the firing assertion a **perfect tautology** — it would assert "the arm fires on the string the arm
> contains". The independence of the fixture from the source **is** the test.

**(b) Whole-vocabulary invariants — these ARE derived from `KW_BODY`**, so they span every arm including
future ones (this is where the derived-oracle precedent *does* apply):

4. **every literal contains a character outside `[A-Za-z0-9]`** — the alphabet invariant (AC4); closes the
   predicate channel and covers all 16 arms plus arm #17 for free;
5. **every literal is lowercase** — directly asserts the Sharp Edge #1 class (Go's lowercase table vs
   `strerror(3)`'s capitalized form), zero new dependency;
6. **every literal appears in a canary-carrying fixture** — turns "one canary per arm" from a checklist item
   into an invariant that cannot decay when arm #17 lands.

**Expected: RED.** Output is **`errsaving,` alone** — *not* zero tokens: every fixture starts with
`error saving credentials:`, so the existing `errsaving` arm fires first. RED because `enomem,` etc. are
absent.

> **Why the ordering is load-bearing (D4, proven by execution):** with an arm removed, output degrades to
> `errsaving,`, which **passes** the closed-form oracle. A canary fixture alone is **GREEN on a missing or
> typo'd arm**. Only a positive per-arm firing assertion catches a dead probe.

**Residual, stated honestly:** family (a) catches a *one-sided* typo (source wrong, fixture right). It does
**not** catch a *two-sided class error* — if Phase 0 had copied `strerror(3)`'s capitalized `Cannot allocate
memory` into **both** the source and the fixture, both agree and the test is green. Invariant (5) closes
exactly that class. A two-sided *transcription* typo (`read only` in both) is closed only by an independent
oracle — `python3 -c "import os; s=os.strerror(12); print(s[0].lower()+s[1:])"` reproduces all six exactly
and `go` is installed. `/work` may adopt one if it can do so without adding a dependency to this pure-bash
suite; otherwise the `failure_modes` claim must read **"a one-sided typo"**, not "a typo".

### Phase 2 — GREEN: the six probes

Append to `_login_kw` **below** the measured arms, **above** the falsified ones, under a short block marking
the class as INFERRED-not-measured and naming the one genuinely new trap:

```bash
  # --- INFERRED, not measured on the host (#6565): the 22-char arithmetic points at ENOMEM, but
  # rests on the verb being open() and the path being 32 chars — both read from code, neither
  # observed. Literals are Go's syscall.Errno.Error() strings: LOWERCASE, not strerror(3)'s
  # capitalized form. `case` is case-sensitive; a capitalized copy silently never matches.
  case "${1:-}" in *'cannot allocate memory'*)    printf 'enomem,' ;; esac
  ...
```

Keep it short — the function's existing header already covers Form B and `case`-vs-`grep -q` at length; do
not restate it a fourth time. The arms are **path-agnostic** (they match the errno substring only; any path
in a fixture is decorative).

**Expected: GREEN.**

#### Phase 2b — the change FALSIFIES two comments. Update both, in the same commit.

This plan's whole thesis is that a false comment is a bug. Two existing comments become false the moment the
six arms land, and both make a **universal** claim that the new class breaks:

| File | Comment (content anchor) | Why it goes false |
|---|---|---|
| `apps/web-platform/infra/ci-deploy.sh` › `_login_kw` header | *"Every literal below is MEASURED … except the last three"* | Six **inferred** arms are neither "measured" nor "the last three". The comment has no word for the new class. |
| `apps/web-platform/infra/ci-deploy.test.sh:3900-3903` | *"Every literal here is a string the /work Phase 0 battery measured out of a real `docker login`"* | The six new fixtures are **inferred from arithmetic**, never measured out of a real login. |

Introduce an explicit **INFERRED** class in both, alongside MEASURED and FALSIFIED. Shipping the arms while
leaving these comments asserting "every literal is measured" would be the exact defect
(`2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it`) that
`_login_hatch`'s own header warns about — and it would be this PR restating it.

### Phase 3 — Follow-through reporting line (D6)

Add one line to `scripts/followthroughs/zot-login-gate-names-failure-6497.sh`, beside the existing
`Observed docker_ver … record on #6565` echo (`:116-117`), which already makes this script a
**datum-reporting channel**, not merely a pass/fail gate:

```bash
echo "Observed kw (the errno datum — record on 6565):" \
  "$(printf '%s\n' "$FAILED_LINES" | grep -oE 'kw=[a-z,]*' | sort -u | tr '\n' ' ')"
```

**Reporting only** — after the PASS/FAIL decision; it cannot flip the verdict. Form-B-safe by construction:
`kw=[a-z,]*` reads an already-closed-vocabulary field over a closed alphabet, so it cannot echo stderr.
The three-state invariant logic is **untouched**.

### Phase 4 — Full suite

`bash apps/web-platform/infra/ci-deploy.test.sh` — all green, no pre-existing failures introduced.

---

## Research Insights — the diff was EXECUTED at plan time

The proposed 16-arm `_login_kw` was sourced into a harness carrying the **real** T-5B-16 oracle
(`^([a-z]+,)*$`), the **real** `T16_KW_CANARY` shape and the **real** 200-random fuzz corpus. Measured
2026-07-16. Observations, not inferences:

1. **All six fire, none escapes the oracle:** `errsaving,enomem,` · `errsaving,erofs,` ·
   `errsaving,enoent,` · `errsaving,einval,` · `errsaving,eio,` · `errsaving,eperm,`. Canary never emitted.
2. **Zero regression.** All nine existing `T16_KW_FIXTURES` produce **byte-identical** tokens with the six
   arms added. `enoent` does **not** cross-talk with the `executable file not found` fixture — the one
   plausible collision.
3. **Fuzz: 0 escapes / 200.** (Base64 cannot produce a space, so no new literal is reachable by a random tail.)
4. **D4 proven:** with the `enomem` arm removed, output degrades to `errsaving,` — **passes** the oracle.
   T-5B-20 is load-bearing. **The single most important measurement here.**
5. **`case` vs `grep -q` verified** under `set -euo pipefail`: `case` non-match → **rc=0** (cannot abort);
   top-level `grep -q` non-match → **exit 1** → **aborts**. Confirms the mandated form.
6. **Multi-token co-fire is REACHABLE:** `_login_kw 'error saving credentials: open /…: read-only file
   system: operation not permitted'` → **`errsaving,erofs,eperm,`**. This is what AC5 guards.
7. **Alphabet invariant holds:** all 16 literals contain a non-`[A-Za-z0-9]` character.

---

## Acceptance Criteria

### Pre-merge

- [ ] **AC1 — scope.** `git diff --stat origin/main...HEAD` touches exactly three files: `ci-deploy.sh`,
      `ci-deploy.test.sh`, `zot-login-gate-names-failure-6497.sh`. No `.tf`, no `.service`, no
      `cloud-init*`, no Doppler.
- [ ] **AC2 — each probe fires on its measured Go literal.** T-5B-20 passes (catches a typo'd literal).
- [ ] **AC3 — full suite green.** `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0.
      *(Subsumes T-5B-15 / T-5B-16 / T-5B-19 — do not re-assert them as separate ACs with hand-copied
      pipelines; a second copy of an oracle drifts from the test it restates.)*
- [ ] **AC4 — alphabet invariant asserted, not assumed.** T-5B-20 requires every `KW_BODY`-derived literal
      to contain a character outside `[A-Za-z0-9]`, so no arm can ever fire on credential content.
- [ ] **AC5 — the follow-through's three-state invariant LOGIC is unmodified.** Reporting-only additions
      are permitted (D6). Verify the probe still asserts `rc`/`class`/`*_chars`, still does **not** assert
      `kw` non-empty (an empty `kw` is itself the H-D datum), and that no assertion changed.
- [ ] **AC6 — no close-keyword adjacent to 6497 / 6400 / 6525 / 6560 / 6565.** Check **three** surfaces —
      PR title, PR body, **and the commit messages** (Sharp Edge #2: the squash body is *the* risk surface,
      and a title/body-only check does not see it):

      ```bash
      KEYS='\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[[:space:]]*:?[[:space:]]*(#|GH-|https?://github\.com/[^[:space:]]*/issues/)?(6497|6400|6525|6560|6565)\b'
      gh pr view --json title,body -q '.title + "\n" + .body' | grep -inE "$KEYS"
      git log origin/main..HEAD --format='%B' | grep -inE "$KEYS"
      ```
      Both → **no output**.

      > The link form matters: a naive `#?` alternation **misses** the `GH-NNNN` form and the full
      > `https://github.com/<org>/<repo>/issues/NNNN` form — **both of which GitHub honors** (measured
      > against this exact regex). A `[^.]{0,40}` proximity form also breaks on the `.` in `github.com`.
      > *(Placeholders again deliberate: spelling those two forms out against a live number would arm the
      > landmine — the same trap this plan already tripped once and had to defuse.)*

### Post-merge

- [ ] **AC7 — the probe reaches web-1.** `gh run list --limit 100 --workflow apply-deploy-pipeline-fix.yml`
      shows the apply succeeded with `files_written == files_total == EXPECTED_COUNT` (**`--limit 100`** —
      default is 20; the prior merge produced 33 runs). *Note: the workflow asserts a COUNT, not per-file
      presence; 15/15 implies `ci-deploy.sh` landed but does not name it.*
- [ ] **AC8 — a deploy must actually RUN. Merging is not deploying.**
      `apply-deploy-pipeline-fix.yml`'s *"Redeploy to load applied profile"* step fires **only when the
      running container's loaded seccomp profile differs from committed** (`:200-201`) — a rare profile
      change. A `ci-deploy.sh`-only merge leaves that invariant holding, so the step **no-ops** and the probe
      **lands on web-1 and sits**. It is exercised by the next independent web-platform release — which
      #6400 / #6525 / #6560 report failing ~60% of the time.
      **Do not claim "the next deploy is guaranteed".** Claim: *if* a deploy runs, the continuous failure
      (A) fires. Confirm a release ran before reading AC9; the follow-through documents 6-12 deploys/day, so
      the wait is short, not zero.
- [ ] **AC9 — read the gate line** (no SSH):
      ```bash
      doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
        --since 90m --grep ZOT_GATE --grep PRELUDE
      ```
      **Adopt the follow-through's own PASS/FAIL/TRANSIENT contract — it already solved this, same window,
      same query. A 2-state rule over a ≥5-state space is how a false-resolved reading happens:**

      | observation | verdict | action |
      |---|---|---|
      | **zero rows** (no deploy in the 90m window) | **TRANSIENT — not a result** | **The worst misread available, and the MOST LIKELY given AC8.** Zero rows is *absence of data*, NOT "the failure stopped". Re-query after a confirmed release. Never read as resolved. |
      | login lines present, **all success** | **premise (A) FALSIFIED** | Major datum: the continuous failure stopped on its own. Record on 6565; re-open the diagnosis — do not assume the errno question still stands. |
      | **exactly one** of `enomem\|erofs\|enoent\|einval\|eio\|eperm` alongside `errsaving` | **NAMED** | Record on 6565; open the repair with evidence. **Only this branch authorises a repair.** |
      | **two or more** new tokens | **NOT named** — a wrapped chain (measured reachable: `errsaving,erofs,eperm,`) | Record the full `kw` string **and the chain shape**. **Do NOT open a repair.** |
      | a new token **without** `errsaving` | **NOT named** — an unmodelled shape | Record verbatim; the `cred_store` framing itself is in question. |
      | `errsaving` **alone** | **NOT named** — a seventh shape | A **datum, not a regression**: the `open()` / 32-char premises are where to look next. See D7. |

      Four of six branches are data, not repairs. **None is a failure of this PR.**

---

## Observability

```yaml
liveness_signal:
  what: ZOT_GATE / PRELUDE docker-login lines carrying kw= (the hatch's field set)
  cadence: every deploy; failure mode (A) is CONTINUOUS, so the next deploy exercises it
  alert_target: none new — this IS the diagnostic surface; the zot fallback alarm is unchanged
  configured_in: apps/web-platform/infra/ci-deploy.sh (_login_hatch, _login_kw); emitted via
                 `logger -t ci-deploy`, allowlisted in vector.toml [sources.host_scripts_journald]

error_reporting:
  destination: journald -> Vector -> Better Stack (plus Sentry on the zot fallback arm, ci-deploy.sh:1289)
  fail_loud: false — BY DESIGN. All three hatch call sites are `$( ( _login_hatch … ) || true )`
             (ci-deploy.sh:1110, :1181, :1286); a telemetry fault must never abort a deploy. Pinned by T-5B-19.

failure_modes:
  - mode: all six probes stay silent (the errno is a seventh shape)
    detection: kw=errsaving alone, via the Better Stack query below
    alert_route: none needed — a DATUM (round 3), not a regression
  - mode: two or more probes co-fire (a wrapped error chain) and are misread as a named errno
    detection: AC8's middle branch; measured reachable as `errsaving,erofs,eperm,`
    alert_route: operator verdict rule — explicitly forbids opening a repair on this shape
  - mode: a probe literal is typo'd and silently never matches
    detection: T-5B-20 per-arm firing assertion
    alert_route: CI — apps/web-platform/infra/ci-deploy.test.sh
  - mode: a probe is Form A and echoes credential-adjacent stderr to Better Stack
    detection: T-5B-15 (structural) + T-5B-16 (canary vs closed-form oracle) + T-5B-20 (canary per arm)
    alert_route: CI
  - mode: a future arm's literal is alnum-only, turning kw into a predicate channel on the credential
    detection: T-5B-20's alphabet invariant (AC4)
    alert_route: CI

logs:
  where: Better Stack (journald -> Vector), UNSCRUBBED — which is why Form B is load-bearing
  retention: per the existing Better Stack plan; no change

discoverability_test:
  command: |
    doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
      --since 90m --grep ZOT_GATE --grep PRELUDE
  expected_output: |
    A docker-login failure line whose kw= carries one of enomem|erofs|enoent|einval|eio|eperm
    (alongside errsaving), or errsaving alone (= a seventh shape). Read it with AC8's three-branch rule.
```

**No SSH.** `--since 90m` parses (the script's own regex is `^([0-9]+)([hmd])$`); a bare `--since 60`
degrades to `WHERE dt >= '60'`. Rows are `{dt, raw}`; `raw` is a JSON **string**; the text is `raw.message`,
**not** `raw.MESSAGE`.

### Soak follow-through enrollment

**No new enrollment — and enrolling would be actively harmful.** `scripts/sweep-followthroughs.sh` **closes
the host issue on PASS** (`action="close"`, `:233`/`:272`). Enrolling issue 6565 would auto-close the
**repair** issue on the first green sweep — manufacturing exactly the false-resolved state D3 exists to
prevent. This PR uses the `Ref` form, so no time-gated flip exists.

The existing probe stays enrolled; its **invariant logic** is untouched (AC5), and D6 adds the one reporting
line that makes this round's own deliverable readable by the automated reader.

---

## Domain Review

**Domains relevant:** Engineering (CTO)

**Status:** reviewed. Additive telemetry on an existing, well-tested emitter. No architectural decision, no
new substrate, schema, dependency, or infra resource. The real risks are the emitter's leak surface (held by
T-5B-15/16, extended by T-5B-20) and the predicate channel (newly closed by AC4). Delivery rides an existing
automated workflow.

**Product/UX Gate:** N/A — no UI surface; the mechanical UI-surface override does not fire. Tier NONE.

- **GDPR (2.7):** not triggered — no schema, migration, auth flow, API route, or `.sql`; no new processing
  activity. The credential concern is a security invariant, not a regulated-data surface.
- **IaC routing (2.8):** no new infrastructure; rides `apply-deploy-pipeline-fix.yml`. Zero operator steps.
- **Architecture Decision (2.10):** **skipped — no architectural decision.** Six literals into an existing
  hatch's probe list. No ownership/tenancy boundary, no new substrate or integration pattern, no
  resolver/dispatch/trust-boundary change, no ADR divergence. Existing ADRs + C4 remain accurate.

## Open Code-Review Overlap

**None** — no open `code-review` issue names `ci-deploy.sh` or `ci-deploy.test.sh`.

**Acknowledged, deliberately not folded in:** 6400 / 6525 / 6560 (`image_pull_failed` ~60%). Pre-existing;
**not** caused by the instrument (fired on v0.218.4 / v0.218.6 before #6528 merged). The weak-form
hypothesis may settle them for free once the errno is named — **do not act before the probe reports.** All
three stay open.

---

## Test Strategy

**Runner:** `bash apps/web-platform/infra/ci-deploy.test.sh` — the file's own `PASS/FAIL/TOTAL` convention.
**No new test dependency**; `bats` is not installed and must not be introduced.

| Test | Guards | Impact |
|---|---|---|
| **T-5B-20** (new) | (a) per-arm firing, **hand-written** fixtures · (b) alphabet + lowercase + canary-coverage invariants, **`KW_BODY`-derived** | new |
| **T-5B-14** | asserts `kw=` is **EMPTY** on its fixture | **re-verify — most exposed.** It survives only on its fixture's wording; a new arm matching that string flips it. Verified passing against the proposed body, but it MUST be named and re-run, not assumed. |
| T-5B-15 | Form B, structurally: no expansion but `${1:-}` in **either** emitter body | must stay green |
| T-5B-16 | closed-form output over fixtures + 200 randoms; `T16_CLOSED_N` bound is derived from **`TOK_BODY`**, so six `_login_kw` arms cannot move it | must stay green |
| T-5B-17 | feeds strings into `_login_kw` | re-verify |
| T-5B-19 | hatch containment — 3 call sites, 3 wrapped | must stay green (D7 does not add a call site) |

Fixtures **synthesized only** (`cq-test-fixtures-synthesized-only`); reuse `T16_KW_CANARY`, already split
against GitHub push protection.

**Open question for `/work` — resolve before reading AC9.** The measured datum is **web-1**, but recent
history references two hosts (`39a4bb8d` *"pin both hosts"*). Confirm `deploy_pipeline_fix` delivers
`ci-deploy.sh` to **every** host that runs a `docker login` — otherwise the probe can be absent on the host
that fires, and AC9 reads zero rows for a reason that has nothing to do with the errno.

---

## Decisions

- **D1 — Six probes, not one.** The arithmetic favours ENOMEM but rests on two unverified code-read
  premises. Being wrong costs another ~24h round with zot degraded; six probes cost five lines in a function
  structurally incapable of misusing them. Stopping rule: the plausible `open()` failure set minus EACCES
  (`permdenied`) and ENOSPC (`nospace`).
- **D2 — Probe, do not pre-empt.** Bounded downside (wait) vs unbounded (auto-apply a `.service` change to
  every web host against an unmeasured cause). This plan has been burned twice by the other choice.
- **D3 — `Ref` form, never a close-keyword.** Issue 6565 is the **repair**; this PR does not repair. A
  close-keyword link would auto-close it at merge and manufacture a false-resolved state.
- **D4 — T-5B-20 is load-bearing, proven by execution.** A missing arm degrades to `errsaving,`, which
  passes the oracle. Phase 1 must precede Phase 2.
- **D5 — T-5B-20 splits its sourcing: firing fixtures HAND-WRITTEN, vocabulary invariants DERIVED.**
  Two reviewers gave opposite guidance here and **both were right about different assertions**; the
  measurement settled it. Deriving a *firing* fixture from `KW_BODY` feeds a typo back into itself and the
  test goes green with the bug (measured). Deriving the *alphabet / lowercase / canary-coverage* invariants
  is correct and necessary — they must span arm #17, which no hand-written list will. The file's
  "derive the oracle from the SUT" precedent applies to (b) and **must not** be applied to (a). Phase 1
  carries an explicit DO-NOT-FIX note so a future reviewer cannot gut D4 by "correcting" it.
- **D6 — Add ONE reporting line to the follow-through probe.** *Deviation from the brief's "nothing else",
  taken deliberately.* The probe is the only automated reader of these lines, is **single-shot** (it PASSes
  on the measured datum, comments, auto-closes issue 6497 via the sweeper, never runs again), and reports `class` + `docker_ver` but
  **not `kw`** — it would drop this round's entire deliverable. It already echoes `docker_ver` with "record
  on #6565", so it is already a datum-reporting channel. One line, same pattern, reporting-only,
  Form-B-safe, cannot flip the verdict. ~~Flag for operator veto if the "nothing else" constraint is
  absolute.~~ **OPERATOR DECISION 2026-07-17: APPROVED — implement it.** The single-shot argument carried:
  without this line the round's deliverable has no automated reader, ever.
- **D7 — ~~RECOMMENDED, needs operator sign-off~~ OPERATOR DECISION 2026-07-17: APPROVED — implement it.
  Emit `errno_chars` from `_login_hatch`.** The operator accepted the deviation from the brief's "nothing
  else" on the plan's own arithmetic: six arms answer only "is it ENOMEM?", and if the 22-char premise is
  wrong they cover ~5% of ~130. `errno_chars` bounds the whole set in one round *and* tests the premise.
  The honest caveats below are NOT waived by this approval — length is non-injective, and security must
  **re-confirm** (not inherit) the `stderr_chars` residual argument for the narrowed segment.
  *Not in the brief's scope. Surfaced because the panel's arithmetic makes the six probes a ~5% shot if the
  premise is wrong, and this is the cheap move that ends the guessing.*

  The 22-char filter admits **only ENOMEM** (measured: the other five are 21/25/16/18/23). So the round has
  two outcomes: the premise is right and ENOMEM alone would have sufficed, or the premise is wrong and six
  guesses cover ~5% of ~130 errnos — a likely **seventh shape**, i.e. a soft dead end and a round 4.

  One field ends it. `_login_hatch` **already** emits `${#_e}` as `stderr_chars`; add the errno segment's
  **length**:

  ```bash
  _suffix="${_e##*: }"     # text after the last ": "
  # emit: errno_chars=${#_suffix}
  ```

  - **Buckets all ~130 errnos in ONE round** instead of six-at-a-time, and **tests the 22-char arithmetic
    directly** rather than assuming it — the plan's single unverified premise.
  - **Form B is not at risk:** this lives in `_login_hatch`, **not** `_login_kw`, so T-5B-15's
    no-expansion-but-`${1:-}` constraint does not apply. It sits exactly where `stderr_chars` already sits,
    under the same no-echo-safe reasoning (`ci-deploy.sh:748-763`).
  - **Honest caveats — do not skip these at review:** length is **not injective** across errnos (it bounds
    the candidate set, it does not always name one), and it carries the **same accepted residual** as
    `stderr_chars` — it moves by `len(username)` if a username lands in the final colon segment. That
    residual is *already* accepted for `stderr_chars` (`:766-768`), but `errno_chars` narrows the segment,
    so security must re-confirm the argument still holds rather than inherit it.

  **Recommendation: take it.** It is ~2 lines, it converts "seventh shape = dead end" into "seventh shape =
  bounded set", and it is the same "buy the datum" discipline that motivates the whole PR. ~~But it is
  scope beyond the brief — the operator decides, not `/work`.~~ **Approved 2026-07-17 (see D7 heading).**

---

## MANDATORY PRE-SHIP CORRECTIONS — from the plan review panel (2026-07-17)

The review verified **166/166 on the real worktree**; the six arms introduce **zero** test failures and all
18 `6497` tests pass. The code is correct. **The defects are in this plan's Acceptance Criteria and in two
shipped comments** — `/work` MUST fix each before the AC gate is trusted. Each was demonstrated by
execution, not asserted; do not re-argue them.

1. **AC6 false-FAILs on 100%-correct code — DEMONSTRATED.** `awk … | grep -c 'grep -q'` matches *comment
   prose*, including Phase 2's own "`case`, never `grep -q`" wording. Adding that comment made AC6 return 1
   on correct code. **Fix:** copy T-5B-19's comment-strip (`grep -vE '^[[:space:]]*#'`,
   `ci-deploy.test.sh:4089-4092`) — it already exists and already explains why. Violates
   `cq-assert-anchor-not-bare-token`.
2. **AC6 is not in CI.** `failure_modes` claims `alert_route: CI`, but AC6 is a one-time manual grep —
   nothing pins it post-merge. Either wire it into the suite or correct the claimed alert route. Do not
   leave a false CI claim.
3. **AC10 misses a close-form GitHub honors — VERIFIED.** `[^.]{0,40}` breaks on the `.` in `github.com`,
   so `Closes https://github.com/jikig-ai/soleur/issues/6565` is **MISSED**. AC10 also claims to cover "the
   commit message" while supplying no command for it, and Sharp Edge #2 names the **squash commit body** as
   *the* risk surface. Fix the regex to cover `#N`, `GH-N`, **and** the full issue URL, and give it a
   command that actually reads the squash body.
4. **AC13's command cannot answer AC13 — VERIFIED.** `gh run list --json` returns only
   name/status/conclusion, and `files_written` is a **count** (`files_written=8`) that never names
   `ci-deploy.sh`. The criterion is unanswerable by that field under any command. Rewrite it against a
   field that can actually settle it.
5. **The change ships two mutually contradicting comments.** `_login_kw`'s header says *"Every literal
   below is MEASURED … except the last three"*; the new arms are **INFERRED**. Same defect at
   `ci-deploy.test.sh:3900-3903`. The universal quantifier breaks for the six new arms. **Fix:** introduce
   an explicit third class — **MEASURED / INFERRED / FALSIFIED** — in both. This is exactly the
   *"false-measured-comment this change exists to drain"* that the file itself warns about. Neither file is
   currently in Files to Edit; add them.
6. **Phase 1's parenthetical is factually wrong.** *"Expected: RED (arms absent → zero tokens emitted)"* —
   measured unpatched output is `errsaving,`. Phase 1's own blockquote and D4 state this correctly. Delete
   the parenthetical.
7. **Name the two most-exposed tests in Test Strategy.** T-5B-14 (`ci-deploy.test.sh:3828`,
   asserts `kw=` is **empty**) and T-5B-17 both feed `_login_kw`. Both pass, but T-5B-14 survives only on
   its fixture's wording and is the test any future arm breaks first.
8. **T-5B-20's (literal, token) pairs are HAND-WRITTEN ON PURPOSE — never derive them from `KW_BODY`.**
   Deriving copies a typo into its own oracle and the test goes green with the bug (measured). The file's
   loud "oracle DERIVED from the SUT, never hand-copied" precedent (`ci-deploy.test.sh:3922-3928`) applies
   to the *vocabulary invariants* and **must not** be applied to the *firing fixtures*. Carry the
   DO-NOT-FIX note so a reviewer cannot gut D4 by "correcting" it.

**Minor (fix if cheap, do not gold-plate):** plan cites `ci-deploy.sh:669-691`, actual is **669-682**;
AC3's `grep -c` exits rc=1 on zero and would abort a `set -e` wrapper — the same "non-match returns 1" class
this instrument exists to survive; AC1's headline exceeds its command; AC5 has no command and a whole-file
grep cannot distinguish the T16 fixture from the T-5B-20 fixture.

**Methodology note worth preserving:** the reviewer's first run showed 5 failures. A **control run on
unpatched code in the same copied dir reproduced the identical 5-failure set** — they were path artifacts of
the scratchpad copy (drift guards resolving outside the copied tree), not a regression. A reviewer who
stopped at the patched run would have reported a false regression. Run the suite in the **real worktree**.

---

## Sharp Edges

1. **The probes are case-sensitive, and the obvious source is the wrong one.** `case` is case-sensitive. Go
   returns **lowercase** (`cannot allocate memory`); C's `strerror(3)` returns **capitalized** (`Cannot
   allocate memory`) — and **issue 6565's own errno table uses the capitalized C form**. Copying from that
   table produces six probes that silently never match and waste the round. Typo traps: `read-only` has a
   **hyphen**; `input/output error` has a **slash**.
2. **GitHub's close-keyword parser is negation-blind and reads the squash commit body.** A phrase shaped
   *"does not `<keyword>` #NNNN"* **still closes** NNNN. Prefer omitting the number; `Ref #NNNN` is the safe
   form. Applies to 6497, 6400, 6525, 6560 **and 6565** — all open, all must stay open.
   *(This bullet uses `#NNNN` deliberately: writing the negated example against a live number would arm the
   landmine it documents.)*
3. **Never `grep -q` in the emitters.** Measured: `case` non-match → rc=0; top-level `grep -q` non-match →
   exit 1 → **aborts the deploy**. That is the dominant abort class the instrument was built to survive.
4. **`kw` is a predicate channel.** Form B stops the *echo*; it does not stop an arm's *firing* from being a
   statement about credential content. Every literal must contain a non-`[A-Za-z0-9]` character. AC4.
5. **The follow-through probe is single-shot.** It PASSes on the current datum, auto-closes issue 6497 via the sweeper, and never runs
   again. Anything you need it to report must land **before** its first eligible sweep.

---

## PR body checklist

- [ ] Title carries no issue number and no close-keyword. Proposed:
      `chore(infra): name the errno — six hardcoded probes in _login_kw`
- [ ] `Ref #6565`. No close-keyword clause near 6497 / 6400 / 6525 / 6560.
- [ ] States: **nothing is broken**; instrument working; prod serving; gate fail-open by design.
- [ ] Carries the **corrected decomposition** (A continuous / B intermittent, B predates the instrument).
- [ ] Carries the **retraction** with its falsifying datum (`39a4bb8d` went green while login was failing).
- [ ] Carries the surviving mechanism as a **HYPOTHESIS**, naming the shape-mismatch it must explain away.
- [ ] All three leads labelled **LEADS**; `e3a5bab21` labelled **class-evidence**, not a cause.
- [ ] States explicitly: **this PR does not repair the failure**; the repair follows the named errno.
