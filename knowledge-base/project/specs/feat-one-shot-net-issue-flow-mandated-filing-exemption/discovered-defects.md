# Discovered defects — feat-one-shot-net-issue-flow-mandated-filing-exemption

Found while implementing. Each is dispositioned here at discovery time so the
Phase 4 net-flow filing gate has a work-list rather than a memory.

---

## DD-1 — `lint-agents-enforcement-tags.py` lints a file that no longer holds the tags

**Status:** **RESOLVED 2026-08-03 in PR #7194 (closes #7172, #6751, #4622).**
Originally: pre-existing, unrelated subsystem, NOT fixed in this PR → filed as #7172.

> **Diagnosis correction (recorded because the filed issue propagated it).**
> The account below is accurate that the gate validated nothing, but its
> explanation and its prescribed remedy were both wrong, and #7172 inherited
> them:
>
> - **The default was not the whole cause.** `lefthook.yml` already passed
>   `AGENTS.md AGENTS.rules.md` explicitly. The real defect was that the linter
>   ran in **no CI workflow at all** — pre-commit was the only site that saw
>   the real corpus, so `--no-verify` (or any bot commit) let `main` drift.
> - **"12 unresolved, ten of them wording drift" was wrong.** Live count was
>   **13**. Only **2** were wording drift (one a single capital letter). **9**
>   were parser-grammar limits — the corpus uses `/` for a skill list, ` + `
>   for enforcer segments, and file-form tokens for lib/test enforcers, none of
>   which the one-skill-one-anchor grammar could express. The 13th was the
>   linter parsing the `> **Tag legend.**` blockquote *this very PR added*.
> - **Zero tags named a nonexistent skill.** `components.test.ts` and
>   `workflow-fidelity.ts` name real files; `SKILL_TAG_RE` captured their
>   leading `[a-z][a-z0-9-]*` and mistook the prefix for a skill slug. The
>   "retire the rule or repoint the tag" disposition would have been applied to
>   two tags that were already correct.
>
> Every enforcer named by all 13 tags exists and enforces. The fix extends the
> parser (ADR-158) and adds a vacuity floor, needing **zero** rule-body edits
> for this defect — not the "three or more ack rows" #7172 budgeted.

The linter's argparse default is `["AGENTS.md"]`. ADR-151 made `AGENTS.md`
pointer-only and moved every rule body — and therefore every `[skill-enforced:]`
/ `[hook-enforced:]` tag — into `AGENTS.rules.md`. So the gate reports:

```
OK: all 0 hook + 0 skill + 0 anchor parity check(s) resolve
```

Zero checks. It has been vacuous since the ADR-151 split.

Pointed at the real corpus it fails immediately:

```
$ python3 scripts/lint-agents-enforcement-tags.py AGENTS.rules.md
FAIL: 12 unresolved enforcement tag(s)
```

Ten are anchor-wording drift against `plan`/`brainstorm` SKILL.md headings; two
(`[skill-enforced: components ...]` at line 26, `[skill-enforced: workflow-fidelity ...]`
at line 54) name skills that do not exist on disk at all, so resolving them is a
retire-or-rewrite decision on the rule body — which needs an ADR-092 ack, not a
one-line edit.

**Why it is not fixed inline.** The cost-of-filing auto-flip is `<=100 lines AND
<=4 files`. This touches `scripts/lint-agents-enforcement-tags.py` plus at least
`plan/SKILL.md` and `brainstorm/SKILL.md`, plus two `AGENTS.rules.md` body edits
each carrying a WORM ack row and a mandatory-human-review annotation. It also
cannot be done silently in this PR: flipping the default to include
`AGENTS.rules.md` turns 12 pre-existing drifts into a red required check on a PR
about something else.

**Why it matters here specifically.** The plan's FR10 rests on the premise
*"Do not rename the `[skill-enforced: ship Phase 5.5 Undeferred Operator-Step Gate]`
anchor (`lint-agents-enforcement-tags.py` validates it)."* Measurement falsifies
that premise: nothing validates it today. FR10 still must not rename the anchor —
`ship/SKILL.md` genuinely keys off that heading — but the stated *reason* was
wrong, and this PR must not repeat it as fact. Corrected in the FR10 comment.

Note the tag this PR adds (`[mandates-filing]`) is NOT an enforcement tag and is
not parsed by this linter, so this PR neither worsens nor is blocked by DD-1.
Verified: `lint-rule-ids.py` exits 0 and the enforcement linter's own default
invocation still exits 0 with the corpus edits applied.
