---
title: "A stub that exits without reading stdin races its piped writer into EPIPE — and a paginate-sweep keyed on the flag misses every sibling spelled differently"
date: 2026-09-30
category: test-failures
module: apps/web-platform/infra test harnesses + gh api list reads
issues: [9245, 9232]
---

# Stub drain fidelity (EPIPE under pipefail) and endpoint-keyed sweep completeness

## Problem

Two defects shipped and were fixed on `feat-one-shot-9245-luks-epipe-flake`
(PR #9261), each carrying a generalizable lesson.

### 1. The "heartbeat push race" was never a push — it was a stub that didn't read

`deploy-script-tests` flaked on `printf: write error: Broken pipe` at
`luks-monitor.test.sh`. The issue hypothesized a heartbeat-push race. The real
site: `printf '%s' "$key" | cryptsetup luksOpen --test-passphrase --key-file -`
in `luks-monitor.sh`, whose PATH-shimmed `cryptsetup` stub exited without
reading stdin. Under `xargs -P4`, the writer's `printf` occasionally landed
after the stub exited → EPIPE → `pipefail` folded it into a fake
`escrow_passphrase_mismatch`. The `pushes=0` in the failed run was a symptom —
the case died at escrow *before* reaching the push.

Real `cryptsetup --key-file -` reads stdin to EOF, so production was never
broken; the defect was stub fidelity. The fix is a guarded drain
(`{ [ ! -t 0 ] && cat >"$CALLS.escrow-stdin"; }`) plus a wire assert comparing
captured bytes to the key — converting a probabilistic flake into a
deterministic red.

**Drain on the flag, not the verb.** The first cut drained on the `luksOpen`
verb; the review panel's counterpoint (and the better property) is gating on
`--key-file -` in argv — both spellings (`--key-file -` and `--key-file=-`).
A verb-gated drain *masks* a mutation that drops the flag (it drains anyway,
where real cryptsetup would not read and the writer would EPIPE); a
flag-gated drain is both more faithful and mutation-detecting.

### 2. A "paginate every list read" sweep keyed on `per_page=100` missed six sites

The plan's census enumerated sites carrying `per_page=100`/`artifacts` and
fixed them — but the structural-enumeration review seat found the sweep had
missed every sibling spelled differently: a `jobs` call with *no* `per_page`
(default 30/page) in `zot-mirror-connector-6416.sh`, two more `jobs` reads in
followthroughs, a `jobs?per_page=100` inside `apply-web-platform-infra.yml`'s
failure-notification step, and — invisible to any `gh api` grep —
`apps/web-platform/server/ci-tools.ts` fetching `/actions/runs/<id>/jobs`
through a TypeScript `githubApiGet` helper. Also invisible to the code sweep:
two doc snippets that *taught* the `--paginate --jq` anti-shape.

This is the same class as the `2026-09-25` sigpipe census miss ("census a
defect class with the drift guard's own PATTERN"), one level wider: enumerate
by the *endpoint and every transport that reaches it* (`gh api`, `gh run view`,
raw `fetch`), never by a flag the buggy form happens to carry.

## Solution

- Stubs for commands that read stdin conditionally: drain exactly when argv
  carries the consuming flag, capture the bytes to a `$CALLS.*` side-file for
  a wire assert, and keep `[ ! -t 0 ]` so an unpiped interactive stdin is never
  consumed.
- Wire asserts compare `$(cat capture)` to `${KNOB:-default}` — the `:-` form,
  because an exported-empty knob would otherwise compare `"" = ""` and read
  undelivered bytes as delivered.
- Pagination on `gh api` list endpoints: `--paginate` + `jq -s` slurp (never
  `--jq` under `--paginate` — gh applies it *per page*). In fetch-based code,
  a `page=N` loop terminating on short page or `total_count`, with `seen`-set
  dedupe against boundary rows resurfacing mid-enumeration.
- URL-matching stub patterns need two-sided anchoring: `*'&page=2'*` on the
  left (so `per_page=100` can't false-match `page=1` inside it) and
  end-anchored or digit-bounded on the right (so `&page=1` can't serve
  `&page=10`).
- `$(fn "$@")` failure messages that name `'$1'` rot the moment callers gain
  flag arguments — use `${!#}` for the endpoint.

## Session Errors

1. **Sweep census keyed on flag-shape, not endpoint+transport** — six
   same-class sites escaped (`jobs` without `per_page`, a workflow step, a TS
   fetch, two docs). **Prevention:** enumerate the *endpoint* under every
   transport (`gh api`, `gh run view --json`, `fetch`), then disposition each
   hit; the fix shape is the sweep's proof, not its boundary. A structural-
   enumeration seat on guard-shaped diffs catches exactly this.
2. **Fixture stub `*page=1*` matched `per_page=**1**00`** — the page-2 request
   got page 1's payload and the fixture went green on the wrong reason.
   **Prevention:** anchor URL patterns on the `&`/`?` parameter boundary AND
   end-anchor digit values; mutation-test the pattern by requesting the
   collision spelling.
3. **`git-data-runcmd-rehearsal.test.sh` hit a 300s timeout with an empty
   log; first read as "my drain change hangs it."** It doesn't source the
   edited harness at all — it defines its own `run_case` driving real docker
   spins, and 300s was simply too short on a contended box (the suite passed
   108/108 unbounded). **Prevention:** before blaming a new code path for a
   silent timeout, grep the suite for `docker run`/`source <harness>` — and
   never bound a container-spinning suite by a wall-clock tuned for unit
   suites.
4. **`gh_api`'s fail message named `'$1'`** — became `'--paginate'` once
   callers passed flags. **Prevention:** `${!#}` for the endpoint arg when a
   wrapper takes flags-first argv.
5. **lefthook pre-commit ran ~12 min under five concurrent sessions' load**
   on the shared box. **Prevention:** environmental; `--no-verify` with
   operator authorization is the sanctioned escape — CI is the backstop.
6. **Resume-prompt prose claimed a PR "in-flight" that was already merged**
   (#7463). **Prevention:** already covered by
   `hr-before-asserting-github-issue-status` — `gh pr view --json state`
   before trusting carried-forward status.

## Key Insight

A test stub's job is fidelity to the *real binary's* I/O contract, not to the
call sites that exist today. `cryptsetup` reads stdin iff `--key-file -` —
drain exactly then, capture for the wire assert, and let every other shape
behave (and fail) exactly as the real binary would. And a defect-class sweep
is only as complete as its enumerator: grep the endpoint and every transport
that reaches it, not the flag the buggy call happened to carry.

## Tags

epipe, pipefail, test-stubs, stdin-drain, cryptsetup, pagination, gh-api,
sweep-completeness, wire-assert, luks-monitor
