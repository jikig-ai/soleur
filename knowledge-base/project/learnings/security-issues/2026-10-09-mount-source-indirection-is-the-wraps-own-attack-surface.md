---
module: web-platform agent sandbox (apps/web-platform/server/agent-outer-wrap.ts)
date: 2026-10-09
problem_type: security_issue
component: service_object
symptoms:
  - "a mountns wrap whose bind SOURCES are tenant-controlled is an arbitrary-mount primitive"
  - "an existsSync-gated argv makes the committed fixture a function of the build host"
  - "a shared-procfs residual silently depends on kernel.yama.ptrace_scope with nothing asserting it"
root_cause: code
resolution_type: fix
severity: high
issue: 5863
pr: 9767
tags: [bwrap, sandbox, tenant-isolation, mount-namespace, review-panel, guard-shape, ptrace_scope]
---

# A mount namespace's bind *sources* are its own attack surface — denylisting the workspaces parent still bound `/`

## Problem

PR #9767's outer wrap landed its isolation guarantee by construction: "the only
entry under the workspaces parent the session ever sees is its own workspace".
The `.git` coverage block then violated that invariant *through the same argv*:
a `.git` symlink or `gitdir:` pointer file is **tenant-controlled workspace
content**, and its resolved target was bound `--bind` rw with only a denylist
guard (`!== wsParent`). `gitdir: /` passed the check — the whole container root
mounted over the assembled namespace, shadowing the `--dir $HOME` + credential
binds that mounted earlier.

Two review seats (security-sentinel + pattern-recognition) found this
independently. Both recommended the same fix shape: **allowlist, not denylist —
and in this layout, nothing legitimate escapes, so drop the external binds
entirely.** Platform readiness already heals escaping pointers by re-clone
(#5733), agent-made worktrees resolve inside the ws bind, and submodule
`gitdir:` pointers land under `<ws>/.git/modules/` — all inside the bind.

## Solution

The external-target bind arms are ABSENT (see `agent-outer-wrap.ts` module
comment). Companion hardening in the same round:

- **Symlink rejection on mutable binds** (`lstatSync(p).isSymbolicLink()`) —
  `~/.claude/.credentials.json`, `.claude.json`, `.gitconfig`, the transcript
  dir: a planted symlink would otherwise bind an arbitrary host file rw at the
  dest (writes land on the *target*).
- **`--ro-bind-try`/`--bind-try` for ambient sources** — the committed fixture
  is a pure function of the builder only if existence is not consulted at
  build time for paths that vary per distro (`/etc/terminfo` exists on Debian
  hosts, not this one). Try-binds give the same mount semantics with a
  host-stable argv, so Guard-2's byte-pin holds on any CI host.
- **The transcript-slug bind stays existence-gated** — the slug encodes the
  absolute ws path, so an unconditional try-bind would still vary argv per
  tmpdir name and un-pin the fixture. (The trap is subtle: `--bind-try`
  tolerates the absent SOURCE at mount time, but the TOKEN is emitted either
  way — existence of the token is what the pin reads.)
- **`ptrace_scope` + `CapBnd` bit-21 asserted inside the shared payload** — the
  shared-`/proc` residual (#9723) is only acceptable while yama restricts
  ptrace; a sysctl drift to 0 makes `/proc/<pid>/root` a full mountns oracle
  into every sibling session. The assertion makes the canary/boot probe *page*
  on drift instead of silently voiding the wrap.
- **`CapBnd` bit-21 (cap_sys_admin) checked inside the wrap** — `--cap-drop
  ALL` clears eff/perm/inh/ambient on every bwrap, but bounding-set clearing
  needs `PR_CAPBSET_DROP` which newer bwrap does; if it ever survives, the
  file-cap'd `bwrap` inside the ro-bound `/usr` re-elevates to the full set.
- **The `getcap -r /` audit runs as the last root layer** — a mid-build audit
  can't catch cap'd binaries installed by later layers (gh, playwright deps).
- **`emitExit` early-returns on `signal != null`** — `code` is null on signal
  kills (Stop, deploy swap, idle reaper), and `null !== 0` reported every
  routine abort as a failure with a Sentry warn.
- **`SpawnedProcess.off()` tracks wrapper↔listener pairs** — `on`/`once`
  register *wrapper closures* on the real child; passing the caller's original
  listener to `child.off` removed nothing.
- **PASS bound to the latest verdict + a 7-day `checked_at` freshness window**
  in the soak — `canary_infra_error` holds `consecutive_pass`, so counters
  alone could promote while the current observation was a flake.

## Key Insight

A mountns build's argv is **input→output across a trust boundary**. Every
string it consumes (a symlink's target, a `gitdir:` body, a `existsSync` on a
distro-specific path) is either tenant-controlled input or ambient environment
— and the former is a mount primitive, the latter is a fixture-poisoning
dependency. The two-seat P0 convergence was on the same sentence shape: "the
guard prevents sibling visibility" is about *what's mounted*; it says nothing
about *what the mount source points at*. Verify both sides of `--bind src dst`.

## Session Errors (this review round — Phase 0.5 inventory)

1. **`--cap-add SYS_ADMIN` missing on both `ci-deploy.sh` `docker run` sites** —
   cloud-init covered first boot only; every subsequent deploy would drop the
   bounding cap the file-cap'd `bwrap` exec requires. **Prevention:** the
   soak test now asserts `grep -c -- '--cap-add SYS_ADMIN' >= 2` on the deploy
   script + presence in cloud-init — a static parity guard over all three
   privilege sites.
2. **`.dockerignore` excluded `infra/` and `scripts/`** — the new `COPY
   --from=builder` sources would have been absent at image build; the canary
   would hit `fixture_missing`/`probe_output_missing` forever.
   **Prevention:** the image-build COPY set is a third leg the same parity
   block could pin (currently asserted only via the runbook table; a
   `docker build` integration test or a COPY-vs-dockerignore grep is the
   cheap version).
3. **`.git` indirection → arbitrary rw bind** (the headline above).
   **Prevention:** the builder carries no external-target bind arms at all —
   there is nothing to weaken, only the "no outside-ws binds" invariant to
   re-derive if a future mount is added.
4. **A `# comment` inside a `\`-continued `docker run` truncated the command**
   at the comment — bash line continuation is literal, comments swallow the
   rest of the line. **Prevention:** `bash -n` catches the syntax but not the
   *truncated semantics*; the harness's docker-trace assertion caught the
   shape. Keep comments ABOVE continued commands.
5. **Removed the `exists` DI seam while its body still called it** —
   `ReferenceError` at runtime. **Prevention:** `tsc`/`eslint` don't fire on a
   missing *local* closure when the name falls through to a module import;
   the runtime smoke (the wrap build) caught it — a `bun -e` builder call
   in the test loop is the cheap pre-land check.
6. **Test-local `const fixture` shadowed the `fixture()` helper** — renaming
   the JSON variable to `fx` un-shadowed it. **Prevention:** prefer `fx`/`F`
   for parsed-fixture locals when a builder helper shares the name; a lint
   rule on `no-shadow` for test files would catch it.
7. **Host-dependent fixture** (headline above).
8. **Strict-elevation classifier landed ahead of the test rows** — the
   existing "plain isolation_ok → pass" row went red the moment the
   `elevation=privileged` requirement landed. **Prevention:** classifier
   tightening and its test rows belong in the SAME commit — the
   data-integrity seat caught the live red between them.
9. **`emitExit` signal kills misclassified** (headline above).
   **Prevention:** `code` on signal termination is `null`, not the signal
   number — any `code !== 0` gate must first exclude `signal != null`. This
   is a per-project Node API trap; the pattern-recognition seat's finding is
   the durable record.
10. **`SpawnedProcess.off()` was a no-op** — caller's listener was never
    registered on the child, so nothing could be removed; SDK listener
    detaches stayed live and would double-fire on every exit.
    **Prevention:** the wrapper↔caller map; the `off`/`once`/`on` trio on a
    wrapped EventEmitter always needs it, or the docs' "listener identity is
    caller-side" assumption breaks silently.
11. **Shared `/proc` residual's soundness depended on `ptrace_scope`** —
    nothing asserted it until the payload added the sysctl check.
    **Prevention:** every residual named in an ADR should name the *invariant
    that holds it* (not just the mechanism), so a reviewer can ask "what
    enforces the invariant" — here the answer is the payload assertion.
12. **`getcap -r /` audit ran mid-build** — a later apt/npm/playwright layer
    could introduce a file-cap binary past it. **Prevention:** audits over
    "the final image shape" belong at the last root layer, after every
    install; the RUN position is now load-bearing and documented.
13. **`classifyShared` dedup initially changed inner-arm ordering** — moving
    the stderr arms before the `exit-0→pass` check would have made a clean
    pass with stray stderr a `sandbox_broken`. Gating the stderr arms on
    `exit !== 0` preserved both arms' original ordering exactly.
    **Prevention:** when extracting a shared head from two callers, the
    caller's control-flow position is part of the contract — write the
    dedup's order as an explicit arm sequence, not "same statements in a
    shared helper".
14. **`warnSilentFallback` mock bled across tests** — no `beforeEach` reset,
    so the third emit-fork test read the second's call count.
    **Prevention:** any `vi.mock`ed sink read by call-count needs a
    `mockClear()` in `beforeEach` — or assert `mock.calls.at(-1)` instead of
    the count.
15. **Founder/debug scripts probed PATH-resolved `bwrap`, not the pinned
    binary** — on a host where the #8752 shim is on PATH, `getcap` inspects
    the shim (always capless → always measures the userns arm) and `bwrap`
    execs through the NEWUSER-deny filter that exists to reject the INNER
    sandbox's argv. **Prevention:** both scripts pin `/usr/bin/bwrap`
    (overridable via `BWRAP_PATH`) — the absolute path the production spawn
    uses, matching `BWRAP_PATH` in `agent-outer-wrap.ts`.

## Prevention (meta)

The three P0s (cap-add sites, `.dockerignore`, `.git` binds) all came from the
same review failure mode: a mechanism-level diff where the seats checked the
*new* code but the *enabling assumptions* lived in files the diff touched
only incidentally (Dockerfile, cloud-init, the workspaces-dir layout). For
design-risk PRs the design-validity pass explicitly names those "what must
be true outside the diff" questions — the `--cap-add` and `.dockerignore`
finds are exactly what it exists for. The `.git` find is a new reusable
shape: **any mount source a tenant can write is a mount primitive** — the
denylist that was already there proved insufficient to notice it.
