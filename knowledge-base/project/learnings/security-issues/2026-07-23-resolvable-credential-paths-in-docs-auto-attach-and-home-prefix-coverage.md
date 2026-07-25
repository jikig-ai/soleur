# Learning: A literal credential-file path in loaded doc prose is a live exfiltration trigger, and the guard that prevents it must cover every home-prefix variant

## Problem

`plugins/soleur/skills/preflight/SKILL.md` Check 10 — the credentialed-CLI *reject* prose — wrote the literal home-relative path to the operator's live Doppler CLI config under `~/.doppler/` at four sites, plus the names of other credential files (ssh keys, netrc, git-credentials, aws, gcloud, docker). Because preflight loads **on every ship**, Claude Code's harness file-path auto-attachment resolved that path to the real on-disk file and read the operator's live `dp.ct.*` Doppler token into 9 separate session transcripts, rendered to the model as a `type: file` "Read tool result".

The irony: security prose *warning* that commands must not read credential files is exactly what caused the credential file to be read. It was not an external attacker, hook, or MCP — it was the skill's own prose triggering a harness feature.

## Solution

Two deliverables:

1. **Neutralize the trigger.** Replace every literal, home-relative-resolvable credential-file path in the loaded prose with a non-resolvable form — a directory-only path (`~/.doppler/`, which is a directory, not a file, so the harness does not read it), a descriptive name ("SSH private keys", "the Docker config"), or a `<placeholder>` segment — while preserving the security prose's meaning. The runtime denylist (the `CRED_REJECT_RE` verb regex, `CMD_DEQ`, the SSH/`SUBST` rejects) was left byte-identical; only human-readable path literals changed. The parser mirror (`discoverability-test-parser.ts:231`) and two comments were neutralized in lockstep.

2. **Durable guard.** `scripts/lint-credential-path-literals.py` fails any tracked `*.md` under `plugins/**` or `knowledge-base/**` that reintroduces a resolvable credential path. Modeled 1:1 on `lint-infra-no-human-steps.py`: full-scan default + `--changed --base` merge-base grandfathering (historical docs are drained via a consolidated follow-up, #6868); `archive/` excluded; plans/specs kept in scope (they load during `/work`). Home-relative (`~/`, `$HOME/`, `${HOME}/`) forms + the bare Doppler config filename hard-fail; remote-host (`/home/<user>/`, `/root/`) forms are advisory (report-only), because those resolve only on that box and are overwhelmingly remote-host runbook documentation.

## Key Insight

Two generalizable lessons:

1. **Local resolvability is the property, not "mentions a credential".** A path auto-attaches when it resolves *for the loader*. `~/`/`$HOME/`/`${HOME}/` resolve for anyone; the bare Doppler config filename resolves via the repo's own root project-pointer of the same name; a hardcoded `/home/deploy/` resolves only on that host. The guard's hard-fail/advisory split is that distinction encoded, not an arbitrary cut. A directory-only form (trailing slash, no filename) is safe because a directory is not a file.

2. **A home-prefix regex must enumerate every home-resolvable prefix.** The first cut of `_HOME` matched `~` and `$HOME/` but not `${HOME}/` (brace form). Because SSH/netrc/aws/gcloud/docker have no bare-filename fallback arm (only Doppler did), a brace-form `${HOME}/.ssh/`-prefixed private-key path **escaped the hard-fail tier entirely** — a fail-open in the exact guard meant to prevent the leak. This was caught only by **mutation-testing the guard on a sandbox copy** (3 mutations — SSH pattern removed, boundary defanged, hard-fail disabled — all caught) followed by an explicit `${HOME}` edge-probe. A green fixture set is evidence about the fixtures you wrote; the fail-open lived in a prefix variant no fixture exercised. The fix widened `_HOME` to `(?:~|\$HOME|\$\{HOME\})/` and added a P7 fixture pinning the brace-form case.

## Session Errors

- **Edit blocked — main-repo path in a worktree session.** First `preflight/SKILL.md` edit used the main-checkout absolute path; the guardrails hook denied it. Recovery: re-issued with the worktree-absolute path. **Prevention:** already hook-enforced (`guardrails.sh` block-write-to-main-with-worktrees) — the hook is the correct mechanical guard; use worktree-absolute paths from the first edit.
- **`test-all.sh` full-suite timeout from sibling-worktree contention.** A concurrent worktree ran `test-all.sh` simultaneously; the run buffered and hit the 10-min timeout. Recovery: verified all affected suites in isolation, relied on CI for the full-suite gate. **Prevention:** already documented (#6726); before treating a full-suite stall/RED as real, check `ps -ef | grep test-all` for a sibling worktree and re-run the affected suites in isolation.
- **Two inspection commands exited 143/144.** SIGTERM artifacts of the foreground timeout + `pkill`. **Prevention:** one-off; run cleanup (`pkill`) and inspection as separate Bash calls so a kill signal does not propagate into the reader command.
- **shellcheck file-level `disable` directive placement.** Placed after `set -euo pipefail` (applies only to the next command, not file-wide); moved above the first command. **Prevention:** a file-wide `# shellcheck disable=` directive must precede the first command (comments-only between shebang and directive).
- **`${HOME}` brace-form fail-open in the guard.** The initial `_HOME` regex missed the brace form. Recovery: widened `_HOME` + added a pinning fixture. **Prevention:** when authoring a path/prefix matcher, enumerate every equivalent surface form (`~`, `$HOME`, `${HOME}`) and add a fixture per form; mutation-test on a sandbox copy — a green fixture set does not cover a variant no fixture exercises.
- **(Forwarded from session-state.md)** Task tool unavailable in the plan subagent context → plan-review fan-out ran inline. **Prevention:** one-off environment constraint; inline review is a sanctioned fallback.

## Tags
category: security-issues
module: preflight, lint-credential-path-literals
related: [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]]
