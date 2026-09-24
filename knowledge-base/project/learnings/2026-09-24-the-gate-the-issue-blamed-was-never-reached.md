---
title: The gate the issue blamed was never reached — a tokenless Doppler read kept every fresh web boot on a dead registry
date: 2026-09-24
category: runtime-errors
module: apps/web-platform/infra (cloud-init.yml web seed pull)
tags: [cloud-init, doppler, zot, ghcr, fresh-boot, nic, observability, ratchets]
issues: [8651, 6985, 6438, 6500, 6122, 8539]
---

# Learning: the gate the issue blamed was never reached

## Problem

Every fresh web-host boot went dark at `stage=pull`. The issue named the mechanism as "a
3-second `/v2/` probe loses, so REF silently stays on GHCR, and the GHCR PAT is revoked
(AP-016)". That mechanism was plausible, came with a measured run (35912244388), and matched a
known race (#8539).

It was wrong. The probe sat behind `[ -n "$ZURL" ]`, and `ZURL` came from
`doppler secrets get ZOT_REGISTRY_URL`, run in the runcmd parent shell with no `DOPPLER_TOKEN`
exported. The token file had only ever been sourced with a bare `.` inside subshells, which
assigns without exporting (#6985). Every call was tokenless, its error was swallowed by
`|| true`, and ZURL was empty on every boot. **The probe was never evaluated.** Sentry over 90
days: 0 `app_zot`, 3 `app_ghcr_served`. The zot path had never served a single fresh web boot.

## Solution

Bake instead of looking up, copying the dedicated inngest host (`inngest-host.tf`):

- The endpoint is `local.registry_endpoint` and the pull credential is
  `random_password.zot_pull`, both rendered into `user_data` via `templatefile`. No Doppler read
  and no probe on the resolution path. A census test pins 0 `doppler` calls above the terminal
  exporting source (11 before).
- Only `ghcr.io/*@sha256:*` refs are rewritten to zot, because the digest pin is the integrity
  guarantee on the plain-HTTP link. The zot pull runs only after a successful zot login, and a
  timed-out attempt stops the retries. The GHCR leg runs only after a successful GHCR login, so a
  dead PAT fails loud at login (the #6500 asymmetry), not as a 401 at pull.
- Failures name both legs, fixed fields first, and redact before the 200-char cut:
  `nic=… zot=[login,n,cause] ghcr=[login,pull] pull_err: …`.
- #6438 (CTO ruling): ship the inngest `99-soleur-private-fallback.network` byte-identical, run
  one early `networkctl reload`, then a bounded, fail-open pre-pull NIC wait. The reload reuses
  `private_nic_probe_fault` (detail `gate=reload`), so the merge changes no alert.
- The closure probe grades the dispatched replace job's own GitHub log, not Sentry. The
  web-platform DSN is public, so a Sentry event alone is forgeable.

## Key Insight

**Before fixing the mechanism a report names, measure whether that mechanism's branch ever
executed.** A gate with a zero success count over its whole life is a gate whose *input* never
arrived. Look upstream of the gate, not at the gate's timing. One Sentry count (0 `app_zot` in 90
days) separated "the probe sometimes loses" from "the probe never runs". The fix for the second
is structural: bake, don't fetch, at cold boot.

Corollary: in a POSIX runcmd, `. file` inside `( … )` sets nothing for the parent, and sets
variables for the subshell without exporting them to children like `doppler`. Any tool that
reads credentials from its environment is tokenless there, and `2>/dev/null || true` turns that
into a silent empty string.

## Session Errors

1. **A nested heredoc closed the outer heredoc early** while writing a scratch edit script. **Recovery:** wrote the scripts to scratchpad files. **Prevention:** never nest heredocs in one Bash call; write the inner program to a file.
2. **Mutation anchors assumed source indentation**, but rendered YAML blocks lose it, so the mutations did not land. **Recovery:** re-anchored on `\nZL=fail`. **Prevention:** derive mutation anchors from the RENDERED artifact, and keep the "mutation did not land → harness failure" guard (it caught this).
3. **The awk block extractor used `sentry_issue_alert`**; the resource is `sentry_alert`. **Recovery:** fixed. **Prevention:** grep the resource type before writing an extractor.
4. **The G2.6 mutation survived** because the order check compared counts, not sequence. **Recovery:** added `ip present/absent` to the ORDER log. **Prevention:** an ordering claim needs a sequence log, never a count.
5. **The size test AC4d pinned the old `until docker pull` form** and went red after the rewrite. **Recovery:** repinned it, then strengthened it to the fatal detail line before `exit 1`. **Prevention:** grep sibling suites for the exact line being rewritten before editing a hot site.
6. **A stray `)` from Python string quoting** broke the test file's syntax. **Recovery:** sed fix. **Prevention:** run `bash -n` after any scripted edit of a shell file.
7. **Scratch probe scripts tripped the credential-refusal lint.** **Recovery:** deleted them. **Prevention:** keep scratch scripts in the scratchpad, never the worktree.
8. **shellcheck SC2115** on `rm -rf "$sb/…"`. **Recovery:** `${sb:?}`. **Prevention:** run shellcheck at warning level per edit.
9. **A SIGPIPE flake from piping into `grep -q` under `pipefail`** (AC22 intermittently red). **Recovery:** a `_qgrep` helper that reads the whole stream; 14 sites rewritten. **Prevention:** in `pipefail` suites, never pipe into `grep -q`; use a here-string or `_qgrep`.
10. **guard-vacuity-floor run from a guessed path.** **Recovery:** `scripts/guard-vacuity-floor.test.sh`. **Prevention:** `git ls-files | grep` before running a suite by name.
11. **A PyYAML sanity check crashed** after I rewrote `%{` to `{`, which broke the template directives. **Recovery:** dropped the directive lines instead. **Prevention:** validate via the terraform render (the suites do), not an ad-hoc textual rewrite.
12. **A full-command-line process match was blocked by the self-match hook** (and a heredoc merely *containing* that flag spelling was blocked too). **Recovery:** name-only match; the Write tool for prose. **Prevention:** already hook-enforced.
13. **File-selected suites missed three repo-global ratchets** (`lint-shell-capture-exit` +3, `lint-trap-tempfile-ownership` rule (c), `fixture-relative-assert` +3). All were caught only by running the ratchets explicitly before commit. **Recovery:** fixed the code (a trap-owned tempfile, explicit `|| x=""` fallbacks, and WORK-rooted mutant paths), never the baselines. **Prevention:** recurring; see work/SKILL.md "A FILE-SELECTED SUITE SET CANNOT SEE A REPO-GLOBAL RATCHET". Run the ratchet lines of `scripts/test-all.sh` (grep `run_suite "scripts/lint-`, plus `plugins/soleur/test/fixture-*-assert.test.sh`) before every commit that adds a test or a regex.
14. **The `credentials_required` corpus baseline (`BASELINE_DECLARED_PROBES`) went red only at the merge commit.** The earlier commit ran with `LEFTHOOK_EXCLUDE=bun-test`, which skipped `plugin-component-test`. **Recovery:** bumped 22→23 with the PLACEMENT/TRUTH/NO SUBSTITUTE justification. **Prevention:** routed to `plan/references/plan-sharp-edges.md`: a plan that declares `credentials_required` bumps that baseline in the same PR.
15. **The first commit lacked the `Co-Authored-By` trailer.** **Recovery:** included it on the review commit. **Prevention:** write commit messages from a template file.
16. **Prose asserted false facts that review caught:** "image bytes are public OCI layers" (the package is private), "THE ONLY REMAINING hetzner -> ghcr edge" (the seed pull keeps a login-gated leg), "on web-1 it can emit" (web-1 never re-runs cloud-init), and the amendment's first mechanism sentence. **Recovery:** each was falsified by one grep and rewritten. **Prevention:** existing review Sharp Edge ("check every claim the diff's PROSE asserts").
17. **I ran the C4 `.sh` tests with `bun test`** (wrong runner, false RC=1). **Recovery:** re-ran them with bash. **Prevention:** dispatch on the extension.
18. **The reload emitter wrote no stage detail**, while the prose I had just written said "a web event's detail says which one". **Recovery:** the reload now writes `gate=reload` before `_emit`. **Prevention:** when prose claims a field discriminates, grep each emitter for the write.
19. **The issue's root-cause framing (probe timing) was inherited unverified by the planning handoff.** It was falsified by a 90-day Sentry count and a tokenless reproduction before any fix. **Prevention:** the Key Insight above.

## Tags
category: runtime-errors
module: apps/web-platform/infra
