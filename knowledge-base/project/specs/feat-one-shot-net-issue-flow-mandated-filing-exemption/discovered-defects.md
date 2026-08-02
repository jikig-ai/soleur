# Discovered defects — feat-one-shot-net-issue-flow-mandated-filing-exemption

Found while implementing. Each is dispositioned here at discovery time so the
Phase 4 net-flow filing gate has a work-list rather than a memory.

---

## DD-1 — `lint-agents-enforcement-tags.py` lints a file that no longer holds the tags

**Status:** pre-existing, unrelated subsystem, NOT fixed in this PR → **filed as #7172**
(verified OPEN, `type/chore`, milestone `Post-MVP / Later`).

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
