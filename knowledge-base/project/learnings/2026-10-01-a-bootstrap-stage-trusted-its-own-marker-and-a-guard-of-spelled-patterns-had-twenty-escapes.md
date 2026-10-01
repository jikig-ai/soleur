---
title: A bootstrap stage trusted its own marker, and a guard of spelled patterns had twenty escapes
date: 2026-10-01
category: security-issues
tags: [operator-bootstrap, doppler, census-guard, mutation-testing, idempotence]
issue: 9321
---

# Learning: a bootstrap stage trusted its own marker, and a guard of spelled patterns had twenty escapes

## Problem

PR 9349 (PR-1 of 2 for #9321) added an operator bootstrap script that copies two Doppler values, mints a
read token and stores it as an environment secret, plus a census guard (Guard 7) that keeps the new
Doppler project a bare container. The author's own checks were green: shellcheck, a stubbed end-to-end run,
the census at 190/0 with six mutation rows all RED. A 12-seat review then found 58 items, none P1, 14 P2,
and they reduced to two classes.

1. **Local state standing in for vendor state.** The "already satisfied" skip required only a recorded
   slug in a gitignored `.env`, one live token and an environment secret of that NAME. Environment secrets
   are write-only, so the name proves nothing about the value: a crash between recording the slug and the
   store left a dead token stored, and the re-run printed the READY marker over it. The same stage ran
   `revoke ... || true` and then printed "revoked", and an unreadable environment-secret list was treated
   as "no secret" (which then told the operator to revoke the live token).
2. **A guard that scans spellings, not the property.** G7c hard-coded the project's Terraform address and
   G7d matched one line shape. Fed to the pristine guard, twenty-odd inputs passed: a renamed label, an
   environment alias of the project, a data source, a project-less token, a quoted project argument, a
   store through the library's repository-level helper, a REST PUT, a `--env` that sat only in a trailing
   comment, and a declaration that existed only inside a block comment. Every one of them was invisible to
   the author's battery, because each row edited the value a guard keys on and never the address, the
   population or the form.

## Solution

- Prove stored state by a marker written only AFTER the store and its listing check succeed
  (`TOKEN_STORED`), and when one token exists that the run cannot show is the stored one, rotate new before
  old rather than dead-ending. A revoke is confirmed by re-listing, never by its exit code. An unreadable
  list is INCONCLUSIVE and stops the stage.
- Derive the guard's tainted address set from the declaring block (a fixpoint over environments and configs
  that reference the project), scan for the non-literal and quoted forms, join continuation lines and strip
  trailing comments before judging a store, and add a must-pass fixture so a guard that rejects everything
  cannot score full marks. The guard's header now states what it does not cover.
- `doppler secrets download --no-file` writes an encrypted copy of the secrets under `~/.doppler/fallback`
  unless `--no-fallback` is given (measured against a loopback mock by the security seat). `secrets get`
  does not. A verification step that downloads a project holding a private key needs the flag.

## Key Insight

A script's own bookkeeping is a claim about the vendor, and an environment secret's NAME is a claim about
nothing. Ask of every "already satisfied" precondition: which read from the vendor establishes this, and what
does the stage do when that read is unreadable? And a census guard is only as strong as the inputs it was fed:
before crediting a green mutation battery, feed the pristine guard the escapes (add a member, rename a label,
change the quoting) rather than only breaking its target.

## Session Errors

1. **Plan write blocked by the infra-routing hook** (forwarded from the planning subagent) — Recovery: terraform-architect confirmed routing, plan rewritten with the ack comment — Prevention: none needed, the hook did its job.
2. **Census could not run locally: no python `yaml` module** — Recovery: a throwaway venv under the scratchpad — Prevention: the census needs PyYAML; note it in the plan's verification line instead of discovering it at the first run.
3. **A self-matching process probe and a long foreground sleep were blocked by hooks** — Recovery: a Monitor loop on report files — Prevention: already hook-enforced.
4. **A nested heredoc ended the outer one** (a quoted heredoc inside a python heredoc with the same delimiter) — Recovery: a distinct outer delimiter and a script file — Prevention: use a unique delimiter for the outer heredoc whenever the payload contains heredocs.
5. **A mutation row expected 2 diff lines and landed 4** (a two-address sed edit changes two lines) — Recovery: corrected the count; the `mutate` landing assertion caught it — Prevention: none, the instrument worked.
6. **Stub harness mismatches cost two runs** (the stub curl returned an id different from the fixture value; the gh stub had no env-secrets file, which the NEW unreadable-list check correctly refused) — Recovery: aligned the fixture; kept the second as evidence the check works — Prevention: derive stub answers from the same fixture values.
7. **Two sentences inherited from the plan were false and I repeated them in D11** (the census "forbids references into isolated projects", which only matched the other project; `notify-apply-failure` as a Slack path, it is an email) — Recovery: added G7e and corrected the text — Prevention: for every causal claim an ADR/runbook adds, run the command that would falsify it before writing it.
8. **The review monitor emitted a line every 15 seconds with no change** — Recovery: stopped it and waited on the agent notifications — Prevention: poll only on a change, not on a clock.
9. **The primary working directory switched to another session's worktree mid-run and a hook injected that tree's context** — Recovery: kept every command on absolute paths in this worktree; touched nothing of the other branch — Prevention: none, environmental.
