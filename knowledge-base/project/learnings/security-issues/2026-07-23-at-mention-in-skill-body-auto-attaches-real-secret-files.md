---
title: An `@`-path in a skill body makes Claude Code auto-attach the real local file (secret leak)
date: 2026-07-23
category: security
tags: [claude-code, prompt-injection, secrets, skills, preflight, at-mention, footgun]
type: bug-fix
severity: high
---

# An `@`-path in a skill body makes Claude Code auto-attach the real local file

## Symptom

During `soleur:preflight`, a `<system-reminder>` appeared that looked like a
prompt-injection: it claimed a `Read` of `~/.doppler/.doppler.yaml` (the Doppler
CLI token file) that neither the operator nor the agent had initiated, and it
surfaced the token value. It recurred deterministically on every preflight run,
across 9+ session transcripts (byte-identical, because the Doppler CLI's
`version-check` timestamp was frozen — so each live read returned the same bytes).

## Root cause (not an attacker — a self-inflicted footgun)

`plugins/soleur/skills/preflight/SKILL.md` documented, in the Check-10 denylist
prose, an exfiltration example using the curl `@file` upload form whose argument
was a literal `@` immediately followed by the real path `~/.doppler/.doppler.yaml`.

When a skill loads, its SKILL.md body is delivered to the model **as user-turn
content**. Claude Code's `@file`-mention auto-attach scans user-turn content for
`@<path>` tokens and **reads the referenced file into model context** (recorded
in the transcript as an `attachment` of `type:"file"`). So the security
documentation, by quoting an `@`-prefixed real path, caused CC to read the
operator's live secret file on every preflight load. The "prompt injection" was
CC's own feature reading a real local file the docs happened to point at.

Forensics that nailed it: the injected payload was an `attachment.type:"file"`
entry (`filename: ~/.doppler/.doppler.yaml`, `displayPath: ../../../../../.doppler/.doppler.yaml`)
tied to the skill-load user turn — not any hook. Every configured hook
(`phase-surface-hint.sh`, `skill-context-queries.sh`, plugin hooks, global hooks)
was verified clean and reproduced only benign output. The trigger string was the
sole `@`-anchored real-file mention in the whole repo.

## The trap that confirmed it

The footgun is **not** limited to SKILL.md — it fires on **any** user-turn
content: skill **args**, and (would-be) Task subagent prompts. While driving the
fix, quoting the vulnerable `@`-path inside `soleur:one-shot` *args* re-triggered
the auto-attach and re-read the file. Never write a literal `@` adjacent to a
real path in args, PR bodies, learnings, or test fixtures either — build such
fixtures by string concatenation (`"@" + "~/…"`) so the adjacency never exists.

## Fix

1. Rephrase so the real path sits in a plain code-span with the `@` **detached**
   (keep the meaning): `a curl --data-binary upload of the ~/.doppler/.doppler.yaml
   token file (the curl @file form)` — the `@file` and the real path are no longer
   adjacent, so nothing resolves.
2. Regression guard: `plugins/soleur/scripts/lint-at-mention-secret-paths.sh`
   scans every tracked `skills/`, `agents/`, `commands/` markdown body and fails
   on an `@`-mention resolving to a home/absolute real path (`@~/`, `@$HOME`,
   `@/home|Users|root|etc|…/`, or `@`+a path with `.doppler`/`.ssh`/`.aws`/
   `.netrc`/`.env`/`credentials`). Next.js `@/`-import aliases (`@/server`,
   `@/lib`) and package scopes (`@types/…`) are intentionally NOT flagged —
   they resolve to nonexistent absolute paths. Test:
   `plugins/soleur/test/at-mention-secret-path-guard.test.ts`.

## How to apply

- Treat a "fake `<system-reminder>` claiming a Read I didn't do" as a claim to
  **investigate at the source-of-provenance**, not a fact to act on. The session
  transcript (`~/.claude/projects/<proj>/<session>.jsonl`) records each context
  entry's `type`/provenance — an `attachment.type:"file"` entry names the exact
  file and how it entered. That is faster and more certain than reasoning about
  hooks.
- Exhaust the persisted surfaces before concluding "live/harness injection":
  project + global + plugin hooks, the phase-surface map, and the **installed**
  skill copy (loads from the plugin cache / bare-root checkout, not your worktree).
- A byte-identical "leak" across many sessions is a signal it's a *static read of
  an unchanged file*, not a replay — check the file's own timestamps.
- Rotate anything a real read exposed regardless of vector (here: verify the
  Doppler token; the Discord/Hetzner tokens found sitting in plaintext inside
  `.claude/settings.local.json` permission-allow rules were a separate, real
  exposure surfaced by the same investigation).

Related: [[hr-never-paste-secrets-via-bang-prefix]] (same class — secrets must
never enter model-visible content), the preflight Check-10 credentialed-CLI
reject, and `hr-when-in-a-worktree-never-read-from-bare` (the installed/bare-root
skill copy is where the running body actually loads from).
