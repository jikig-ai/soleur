---
title: "A guard can recreate its own bug; a forced -replace from a stale pin ships nothing; a locally-measured exit code makes a branch silently CI-red"
date: 2026-07-16
category: best-practices
tags: [drift-guard, observability, syslog-identifier, pinned-artifact, terraform-replace, oci-image, review, concur-gate, version-skew, curl, ci-green-vs-local-green]
problem_type: logic_error
component: infrastructure
module: apps/web-platform/infra
related_pr: "#6539"
related-issues:
  - 6536
  - 6551
  - 6555
  - 6556
related_learnings:
  - 2026-05-06-source-grep-drift-guards-break-after-buildtime-interpolation.md
  - 2026-05-11-drift-guard-scoping-extract-call-site-not-widen-walk.md
  - 2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md
  - 2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md
---

# A guard can recreate its own bug; a forced `-replace` from a stale pin ships nothing; a locally-measured exit code hides a CI-red branch

Three independent findings from the review of PR #6539 (fix #6536). Each was confirmed by
running something, not by reasoning about it. The #6536 bug itself and its five planning
rounds live in the committed plan; this file records only what generalises.

## 1. A guard that derives an expected set from emitters is coupled to the WRONG emitter's lifetime — and its failure text can order the bug's recreation

### Problem

`vector-pii-scrub.test.sh` AC3 is a drift guard: the `SYSLOG_IDENTIFIER` allowlist in
`vector.toml` MUST equal the set of tags the infra scripts actually emit. It derived that
expected set from `logger -t` calls in `infra/*.sh`.

`inngest-bootstrap.sh` entered that derivation loop through **exactly one line** — a `sed`
replacement that renders a cutover-scoped "dark arm" into a generated ping script. Its only
`LOG_TAG` sat inside a heredoc.

But the tag's **real justification** is the unit's `SyslogIdentifier=inngest-heartbeat`,
which retags everything the unit writes (doppler's *and* curl's stderr) whether or not the
dark arm exists. The dark arm is scaffolding, due for deletion the moment the host goes
live.

So post-cutover, deleting the now-pointless dark arm would:

1. drop the file out of the `logger -t` loop,
2. drop `inngest-heartbeat` from EXPECTED,
3. fail AC3 with *"array != the logger -t scripts"*,
4. and thereby **instruct the engineer to delete the entry from `vector.toml`** — re-blinding
   the exact channel #6536 exists to open.

The guard would have recreated the bug it guards, through its own failure message, and the
engineer following it would have been doing as told.

### Root cause

The tag was justified by **channel B** (`SyslogIdentifier=`) but derived via **channel A**
(`logger -t`). A guarded artifact derived through a channel that is not its justification is
coupled to *that channel's* lifetime, not its own. The coupling is invisible while both
channels happen to coexist — which is exactly the window in which the guard looks correct.

### Solution

**Derive every emission channel independently**, before the gate that filters by the other:

```bash
for f in "$INFRA_DIR"/*.sh; do
  # Channel A — an explicit unit SyslogIdentifier=. Derived UNCONDITIONALLY, before the
  # logger gate below, because it is independent of whether the file also loggers.
  grep -hoP '^SyslogIdentifier=\K[a-z0-9-]+$' "$f"
  # Channel B — a real logger -t invocation.
  grep -qE '<logger forms>' "$f" || continue
  grep -hoP '^\s*(readonly\s+)?LOG_TAG="\K[^"]+' "$f"
done | sort -u
```

Verified on all three axes (a sandbox copy of `infra/*.sh`, never the tracked tree):

| Scenario | Old derivation | New derivation |
|---|---|---|
| dark arm present (today) | 13 tags | 13 tags — **identical; a no-op today** |
| dark arm removed (post-cutover) | **drops** `inngest-heartbeat` | retains it — hole closed |
| un-mirrored new `SyslogIdentifier=` unit | **0 (blind)** | 1 — drift caught |

The third row is the bonus: explicit-`SyslogIdentifier=` units previously had **zero** drift
coverage — which is the #6536 defect class itself (a unit whose tag matched no source).

### Key insight

Three rules, in order of how much they cost to learn:

1. **Enumerate every channel that can produce the guarded artifact, and derive each one
   independently.** Ask of any guard: *what, exactly, pulls this item into the expected set —
   and is that the same thing that justifies it?* If the answer differs, the guard is a
   coincidence with an expiry date.
2. **The failure message is part of the guard.** It must name the direction to reconcile —
   the **emitter** dictates, the allowlist follows. A message naming the wrong source of
   truth is not a diagnostic; it is an instruction to recreate the bug. AC3's text now says
   so explicitly, and refuses the tempting remedy by name.
3. **Derive, never exempt.** The obvious "fix" was to move the tag into the hardcoded
   `SYSTEMD_UNIT_IDENTIFIERS` list. Two reviewers were right to forbid it: that list is for
   identifiers **no source line can yield** (`webhook`'s bare binary basename), and parking a
   *derivable* tag there trades lockstep for the bypass its own comment forbids. The
   finding was right that the coupling was real; the reviewers were right that the remedy was
   wrong. Neither saw the third option. **When a review deadlocks between "fix it there" and
   "you can't fix it there", the missing move is often a new derivation rather than a new
   exemption.**

## 2. "Merging ships nothing" and "the dispatch ships the fix" are different claims — verify the second

### Problem

The team knew — and the plan documented — that merging #6539 delivers nothing:
`hcloud_server.inngest` is stripped from per-merge apply, and the replace is dispatch-only
(`apply_target=inngest-host-replace`, ADR-100 Amendment 6b). The conclusion drawn was
"merge, then dispatch the replace."

Nobody checked what the dispatch would actually boot. It runs:

```
terraform plan -replace='hcloud_server.inngest' -target=…
```

`-replace` **force-replaces regardless of any `user_data` diff** — so the "an IREF bump is
what triggers the replace" reasoning, true for a normal apply, does not gate this path at
all. The rebuilt host boots cloud-init pinned at `IREF=…:v1.1.19` and extracts
`inngest-bootstrap.sh` + `vector.toml` from **that image**. Measured:

| Tag | dark arm | `SyslogIdentifier=` | `vector.toml` tag |
|---|---|---|---|
| `vinngest-v1.1.19` (what the host pins) | 0 | 0 | 0 |
| `vinngest-v1.1.20` (exists on main; web host pins it) | 0 | 0 | 0 |

**Neither published image contains the fix.** Dispatching would have rebuilt the dark host
from a pre-fix image, left #6536 live, and **spent the zero-downtime window** — free only
while the host is dark, and a real cron outage once #6178 arms the flip. The most expensive
possible outcome: the rollback window consumed by an operation that changed nothing.

### Root cause

Two facts were conflated:

- *the code is on main* — true after merge;
- *the artifact the host boots contains the code* — requires a **new tag** (the image builds
  only on a `vinngest-v*` tag push, from that tag's tree) **and** a pin bump.

Nothing in CI ties them together. `cloud-init-inngest-bootstrap.test.sh` asserts the pin's
**format** and IREF/ZIREF **internal agreement** — never that the pinned image matches the
repo's content. So "the shipped image predates the fix" is silent drift, and the pin had
*already* been silently lagging (main carried v1.1.20 while the dedicated host pinned
v1.1.19).

### Key insight

**For any pinned-artifact delivery — OCI tag, chart version, AMI, lockfile, vendored blob —
grep the PINNED ARTIFACT's tree for the fix, not the repo's.** `git show <tag>:<path> | grep
<the fix>` is one command and it is the only one that answers the question actually being
asked.

Two corollaries:

- **A `-replace`/force-recreate from a stale pin is a silent no-op that consumes its own
  rollback window.** It succeeds loudly (the host really is rebuilt) while delivering
  nothing, so the failure looks like success until the symptom persists. When a plan's
  delivery step is a force-replace, the review question is not "will it replace?" but "what
  bytes will the new host boot?"
- **An internal-consistency guard reads exactly like a content guard and is not one.**
  IREF==ZIREF proves the two pins agree with *each other*; it says nothing about whether
  either agrees with the repo. Ask of any pin guard: *which of {format, self-consistency,
  content} does this actually check?*

## 3. An assertion pinned to a LOCALLY-MEASURED exit code reads green to its author forever, while the branch sits CI-red

### Problem

The plan measured the bug precisely: `curl -fsS --max-time 10 ""` → **rc=2** (`option : blank
argument where content is expected`). That measurement was correct, so `/work` encoded it
directly:

```bash
assert "AC5b/3 web render + URL absent -> rc=2" "[[ '$WEB_ABSENT_RC' -eq 2 ]]"
```

Locally: **110/110**. In CI: **109/110** — and it had been failing on *every* run since the
`/work` phase, on the last four commits, while the handoff notes recorded "tests green
(110/110 inngest.test.sh)". The branch was never CI-green; the author's machine simply
never said so.

**curl's empty-URL exit code is version-dependent.** curl 8.18 exits **2**; older curl exits
**3** (`URL using bad/illegal format or missing URL`) — which the runner ships, and which
**this very plan already knew**: its own §Hypotheses called H5 *"Same class as #4116 (`curl`
exit 3 on empty URL)"*. The plan cited a sibling incident with a **different rc for the same
condition**, one section above the AC that hardcoded rc=2.

### Root cause

An empirical measurement is a fact about **the environment it was taken in**. Encoding it as
an equality assertion silently converts "what my curl did" into "what curl does". The tell is
that the measurement and the contract are different propositions:

- measured: *this curl exits 2 on an empty URL* — true, environment-scoped;
- contract: *the live pusher must not silently succeed with no URL* — true everywhere.

Only the second is what the feature owes. `-eq 2` asserts the first.

### Solution

Assert the contract, and attribute it:

```bash
# non-zero is the property; ^curl: proves curl RAN and rejected it (a missing binary exits
# 127 with sh's "exec: not found" and would satisfy a bare -ne 0 — passing for the one
# reason that means the test proved nothing).
[[ "$RC" -ne 0 && "$RC" -ne 127 ]] && printf '%s' "$OUT" | grep -q '^curl:'
```

Mutation-checked across both real curl versions and every failure mode:

| input | verdict |
|---|---|
| rc=2, `curl: option : blank argument…` (8.18) | PASS |
| rc=3, `curl: (3) URL using bad/illegal format…` (#4116 / runner) | PASS |
| **rc=0, silent success — the regression this exists to catch** | **FAIL** |
| rc=127, `sh: exec: /usr/bin/curl: not found` | **FAIL** |
| rc=1, unrelated non-curl failure | **FAIL** |

### Key insight

**When a plan's evidence is a measured exit code / version string / byte count / timestamp,
the AC must assert the PROPERTY it demonstrates, not the VALUE it returned** — unless the
value itself is pinned by contract somewhere (and then cite where). Two cheap tells that this
line is about to be written:

- The plan cites a sibling incident with a **different value for the same condition**
  (here #4116's exit 3, one section above). That is the environment-dependence, already
  written down, going unread.
- The assertion would be **unfalsifiable on the author's box** — it can only ever fail
  somewhere the author is not, which is precisely where nobody is watching.

And the corollary for handoffs: **"tests green" is a claim about a machine.** Before trusting
a green in a resume note, check the branch's last CI run — `gh run list --branch <b>`. A
local-only green is indistinguishable from a real one right up until it isn't. Related:
[[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]]
— a gate that certifies the wrong property, in the version-skew dimension.

## Session Errors

- **The NUL-byte trap fired again.** `apps/web-platform/test/infra/vector-pii-scrub.test.sh`
  carries a NUL at offset 9426 (pre-existing on main). GNU grep treats the file as binary and
  **silently returns nothing** — no error, no "Binary file matches", just an empty result that
  reads exactly like "no match". It produced one false negative before being caught.
  **Prevention:** always `grep -a` that file. Known repo trap; noted here only because it
  recurred.
- **My own closed-value-set assertion failed open.** I wrote
  `[.services.x] | inside(["rendered","absent","script-missing"])` to bound a state field.
  jq's `inside`/`contains` are **substring** matches on strings, so `""`, `"render"`,
  `"dered"` and `"abs"` all **PASSED** — the assertion meant to bound the set would have
  certified an empty/unset value as valid. `IN("rendered","absent","script-missing")` is exact
  and rejects all four. **Prevention:** mutation-check closed-set assertions with a *near-miss*
  and an *empty string*, not just an obviously-bogus value — an obviously-bogus value is the
  one case a substring match also rejects, so testing only that certifies nothing. This is the
  same "the gate certifies the wrong property" class as
  [[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]].
- **I wrote a comment citing a test file that does not exist.** While documenting the sudoers
  mirror I referenced `deploy-inngest-bootstrap-sudoers-parity.test.sh` — invented. The real
  enforcement is `cloud-init-inngest-bootstrap.test.sh` AC5. Caught by checking before
  committing. **Prevention:** a comment citing an artifact is a claim; `ls` it. Writing a false
  comment into the PR whose entire subject is *a false comment authorized a 3-day outage* would
  have been a fine irony.
- **My hand-rolled reconstruction of a test's extraction disagreed with the test.** To check
  whether AC5's parity assertion was vacuous, I re-implemented its awk from memory; my version
  reported the cloud-init side had 0 occurrences of the new token while the real test passed.
  The real awk pulls **19 lines** from both sides and they match. I nearly filed a vacuous-guard
  finding against a guard that was fine. **Prevention:** to test whether real code is vacuous,
  **run the real code** (`sed -n` the region and `source` it, or invoke the suite) — a
  reimplementation tests your reimplementation.
- **I filed a scope-out under a criterion that does not fit, and the CONCUR gate caught it.**
  I claimed `cross-cutting-refactor` for the `--preserve-env`/`env_keep` finding on the grounds
  that `ci-deploy.sh` + sudoers are the "web-host delivery path" while the PR is about the
  dedicated host. `code-simplicity-reviewer` DISSENTed: the criterion defines "core change" at
  **directory** granularity, and all three files sit in `apps/web-platform/infra/` beside the
  PR's primary file. Mine was a *subsystem* distinction the criterion does not make.
  **Prevention:** none needed — this class is already documented (review SKILL.md, PR #3743) and
  I made the error anyway. That is the point: the **gate**, not the prose, is what caught it.
  The disposition for a documented-and-still-recurring class is a mechanical gate, and here the
  mechanical gate already existed and worked. Do not add another rule.
- **A DISSENT being right about the criterion did not make it right about the remedy.** The same
  reviewer prescribed adding `DOPPLER_PROJECT` to `--preserve-env`. Verified before applying:
  `grep -c DOPPLER_PROJECT ci-deploy.sh` → **0**. The flag would preserve an **unset** variable
  — a no-op. Applied the plumbing anyway (it closes the sudo-boundary half and is a strict
  improvement) with the limitation documented at all three sites, and routed the env-source half
  to #6555. **Prevention:** verify a reviewer's prescribed fix the same way you verify a
  reviewer's prescribed CLI flag — the finding and the remedy are separate claims.
- **Two test runs hit my own timeouts** (`test-all.sh` at 540s, `ci-deploy.test.sh` at 400s →
  exit 143/124). Not failures — `ci-deploy.test.sh` is docker-backed and genuinely slow.
  **Prevention:** budget >400s for `ci-deploy.test.sh`; exit 124/143 is `timeout`, not the SUT.
- **I tried to edit `plugins/soleur/skills/review/SKILL.md` at the BARE-REPO path while a
  worktree was active.** The `guardrails` PreToolUse hook denied it and named the worktree path
  to use instead. The edit would have landed on stray content not on any branch — invisible to
  the PR, silently lost. **Prevention:** none needed at the rule layer — compound's own
  route-to-definition step already says "always use worktree-absolute paths … verify with `git
  status --short` that the expected file is listed as modified", and the **hook** is what
  actually caught it. Another instance of *the mechanical gate catches what the prose did not*.
  I ran the `git status --short` verification afterwards and the file was listed, confirming the
  re-applied edit landed inside the working tree.

## Prevention

- When reviewing a guard, ask: **what pulls each item into the expected set, and is that the
  same thing that justifies it?** Then delete the justification's *other* channel in a sandbox
  and re-derive. If the set moves, the guard is coupled to scaffolding.
- When reviewing a guard, read its **failure message** as an instruction, because that is what
  it is. Does following it literally fix the drift, or cause it?
- When a plan's delivery is a pinned artifact, add one AC: `git show <pin>:<path> | grep <the
  fix>` must be non-zero. Neither "merged" nor "the apply ran" implies it.
- Mutation-check your own new assertions with a near-miss and an empty value before committing
  them, and prefer exact-match primitives (`IN`) over containment ones (`inside`, `contains`)
  whenever the intent is a closed set.
