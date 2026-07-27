---
date: 2026-07-27
issue: 6981
pr: 6984
tags: [cloud-init, doppler, shell, testing, mutation-testing, git, infra, boot-path]
category: infra
---

# My assertion pinned the text, not the shell that runs it

`soleur-web-2` booted dark three times. The third boot finally named its cause —
`Doppler Error: $HOME is not defined` — because `cloud-final.service` runs `runcmd` as root with no
`User=`, and systemd synthesises `$HOME` only for units that declare one. The Doppler CLI resolves
its home directory *before* it reads `DOPPLER_CONFIG_DIR`, so the config dir cloud-init already sets
is not a substitute.

The one-line fix was right. Almost everything I said *about* it was wrong, and a six-agent review
found all of it. This is the part worth keeping.

## 1. A search over a FILE cannot pin a property of one SHELL

`AC-HOME1/2` asserted `export HOME=/root` appears in `cloud-init.yml` before the first doppler call.
That reads like a guard. It is a guard over the wrong domain: the property is "the line executes in
the runcmd shell before doppler runs", and the assertion's search space was the whole file.

Three mutations kept it green while the fix was completely inert:

| Mutation | Still "textually first"? | Actually executes? |
|---|---|---|
| move into `bootcmd:` | yes | no — separate cloud-init process |
| move into a `write_files:` payload | yes | no — it is file content |
| wrap in a heredoc **body** | yes | no — it is data, not shell |

The fix is to make the search space equal the property's domain: scope to the `runcmd` region,
separately forbid the line *above* `runcmd:`, and **elide heredoc bodies** before searching.

**The tell:** when an assertion greps a file for a line whose meaning depends on *where* it runs,
ask "name a place this line could sit that satisfies the grep and never executes." If you can name
one, the assertion pins spelling.

## 2. `: "${VAR:=default}"` sets a SHELL variable — the `export` is the load-bearing half

The baked helper carried both lines:

```sh
: "${HOME:=/root}"
export HOME
```

`AC-HOME3` pinned only the first. Deleting `export HOME` left the whole suite green at 104/0 while
the helper's entire second layer was dead — a child process does not inherit a non-exported shell
variable. Measured:

```
$ env -u HOME sh -c ': "${HOME:=/root}"; env | grep "^HOME="'
(nothing)
```

**Generalisation:** when a fix is a pair where one line *computes* a value and the other *publishes*
it to the consumer, the publishing half is the one that carries the behaviour. Test that one. The
same shape recurs as `set -a` vs a bare `.`, `local` vs a function's return, and a computed variable
never passed to the subprocess that needs it.

## 3. A fix that clears the error you saw is not a fix for the path

I claimed the export fixed all 11 doppler call sites in `runcmd`. `HOME` was one of **two**
independent blockers. Sites above the exporting `set -a; . /etc/default/webhook-deploy; set +a` use
a bare `.`, which sets shell variables without exporting them, so those calls reach doppler with no
`DOPPLER_TOKEN` and exit *"you must provide a token"* — still `|| true`, still silent. Measured:

```
$ sh -c '. env; env | grep -c "^DOPPLER_TOKEN="'      # 0   (bare .)
$ sh -c 'set -a; . env; set +a; env | grep -c ...'    # 1   (set -a)
```

The boot fix works only because the *fatal* site sits below the `set -a`. Roughly ten others stay
inert (the #6090 GHCR-token refetch, the ADR-096 zot `ZURL` reads). Deferred as #6985 — a two-line
change that alters **which registry the host pulls from** is not a two-line change, and a hotfix for
a host that is dark right now is not where you first-run that path.

**Generalisation:** when a fix makes a previously-fatal path reach further, enumerate everything
*else* that path needs and verify each. "It now gets past the error I fixed" is not "it works".

## 4. A class fixed per-unit recurs in the context nobody opted into

This was the **fourth** occurrence of "root context runs Doppler with no resolvable `HOME`":

| # | Where | Fix shape |
|---|---|---|
| #4116 | inngest heartbeat | `User=deploy` |
| #6196 | registry + git-data cloud-inits | `HOME=/root` in the env file |
| #6669 | web-1 probe units | `Environment=HOME=/root` |
| #6981 | cloud-init `runcmd` | this PR |

Eight systemd units already carried `Environment=HOME=/root`, five per-unit drift tests guarded
them, and `inngest-bootstrap.sh` writes the rule down verbatim: *"If a future edit adds `doppler run`
here, it MUST also set `Environment=HOME=/root`."* Every guard was **opt-in** — so the one root
execution context nobody enrolled is precisely where it bit again.

The durable fix is an **opt-out sweep** (`AC-HOME6`): every doppler-invoking unit must resolve `HOME`
via `User=` or `Environment=HOME=/root`, with a ≥8-unit non-vacuity floor so a broken glob fails
loudly instead of reporting a clean sweep of nothing.

**Generalisation:** the second occurrence of a class is the signal to switch from opt-in guards to an
opt-out sweep. A per-unit guard can only protect units someone remembered to enrol; the failure
always lands on the one they didn't.

## 5. A shallow clone is not the project's history

`git log` for `cloud-init.yml` showed 21 commits starting 2026-07-11. I concluded the March-era
config was unknowable and hypothesised a March-vs-July `ubuntu-24.04` image difference — then wrote
that hypothesis into **three durable artifacts** (the issue, the PR body, the post-mortem).

The repo is a shallow clone: `git rev-parse --is-shallow-repository` → `true`, graft at `09e9a3e82`.
`git log --all` recovers **113 commits** back to 2026-02-10, and the real answer is unambiguous:
`cloud-init.yml` was added 2026-03-18, ~28 hours *after* web-1 was created; Doppler was adopted
2026-03-20; and `lifecycle.ignore_changes = [user_data]` means web-1 has **never re-run cloud-init**.
web-2's July births are the first execution of the current `runcmd` on any web host. There was no
image difference to find.

**Before writing "the history does not contain X":** run `git rev-parse --is-shallow-repository` and
retry with `--all`. An absent commit and an unfetched commit are indistinguishable in `git log`, and
only one of them is a fact about the project.

## 6. Relaying an agent's claim is asserting it

A review agent reported that the fix "activates the zot-primary boot path for the first time and
silently repairs the #6278 alarm baseline." I passed that to the operator as a finding. A second
agent contradicted it; the second agent was right (the `ZURL` reads sit above the `set -a`, so they
stay inert), and I had to retract.

It was *good news*, which is exactly why it went unchecked. **Verify a cross-cutting behavioural
claim before relaying it — especially a favourable one.** Agent convergence is not evidence when the
agents share a premise, and a single agent's claim is a hypothesis regardless of how confident the
prose is.

## Session Errors

1. **The PR's central claim was asserted, not measured** — I wrote "all 11 doppler call sites" from
   the shape of the fix rather than from the sourcing semantics. **Prevention:** for any claim of the
   form "this fixes N sites", enumerate the N and verify one property per site before writing it.

2. **Six surviving mutants in my own assertions** (§1, §2) — the suite was 104/0 over guards that
   pinned spelling. **Prevention:** for each new assertion, name a mutation that satisfies it while
   violating the property; if you can name one, the assertion is not done.

3. **My first mutation battery ran against a RED baseline** (29/61, sandbox missing repo shape) — every
   result void, and a void result reads exactly like a clean one. **Prevention:** already documented;
   run the un-mutated baseline first and require it green before any mutation result is credited.

4. **I filled the `/tmp` tmpfs** with `cp -r apps` (which pulled `node_modules`) building that sandbox,
   and a later command died `ENOSPC`. **Prevention:** copy only the paths the suite resolves; check
   `du -sh` on the source before a recursive copy into a tmpfs.

5. **Comments blew the `user_data` byte budget** — 33 lines took the rendered size from 23,016 B to
   23,852 B against a 23,700 B sub-cap. **Prevention:** folded into
   [[2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays]] — check
   the budget before adding prose to a byte-capped template.

6. **I measured the budget with the wrong instrument** — raw `gzip | base64 | wc -c` on the source read
   23,444 (under budget) because the file is a terraform *template* the test renders first. I would
   have declared it fixed on a number ~400 B low. **Prevention:** when a gate owns a measurement, run
   the gate; a hand-rolled equivalent is a different measurement until proven identical.

7. **I relayed an unverified agent claim** to the operator (§6). **Prevention:** verify before relaying,
   especially favourable claims.

8. **I cited #6985 in a production code comment before filing it**, predicting the next number after the
   PR. It happened to be correct — luck, not method. **Prevention:** file first, then write the number.

9. **Every line number in my new comment resolved to the wrong line** — captured against an intermediate
   revision and never re-resolved (violates `cq-cite-content-anchor-not-line-number`). **Prevention:**
   cite content anchors, never line numbers, in any comment that outlives the edit.

10. **I wrote that `ProtectHome=read-only` makes `/root` unreadable.** It makes it read-only; the 0700
    root-owned DAC mode is the actual barrier. Right conclusion, wrong mechanism, in a load-bearing
    rationale a future editor would trust. **Prevention:** when a comment names a *control* as the
    reason, verify that control produces the effect claimed.

11. **`gh pr diff --name-status` is not a real flag** — my file-freshness loop got empty input and printed
    a vacuous `missing count: 0` that read like a pass. **Prevention:** a loop over an empty list is a
    null result; assert the input is non-empty before trusting the verdict.

12. **`git merge-base --is-ancestor HEAD origin/main` is the wrong safety test for a squash merge** — no
    branch commit is ever an ancestor, so it reported "work would be lost" on fully-merged work.
    **Prevention:** for squash merges, test content equivalence (`git diff --name-only origin/main HEAD`),
    not ancestry.

## Related

- [[2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays]] — the
  other reason a cloud-init comment is not free
- [[2026-07-27-the-safety-rationale-i-wrote-was-false-and-the-gate-it-justified-failed-open-three-ways]]
  — same incident chain, the `web-host-replace` gate that produced the diagnosable boot
- [[2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot]] — the
  sibling class: an assertion whose *position* is part of its correctness
