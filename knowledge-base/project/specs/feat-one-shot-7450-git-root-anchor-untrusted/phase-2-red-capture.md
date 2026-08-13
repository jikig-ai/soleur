# Phase 2 — RED capture for Guard 2 (cq-write-failing-tests-before)

Run against `feat-one-shot-7450-git-root-anchor-untrusted` **before** any migration, i.e. with
all five sites still carrying `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`.

```
$ bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh; echo "EXIT=$?"

PASS: Test 19a: decoy is a live hazard (real sentinel exit=1 on the fixture, decoy exit=0)
PASS: Test 19b: anchor expression extracted from the committed incident/SKILL.md
FAIL: Test 19c: committed anchor resolves INTO the reviewed party's tree — a hostile PR's
      redact-sentinel.sh would run as the gate
      (resolved=/tmp/tmp.XxyBHx8cde/t19-contributor-tree/plugins/soleur/skills/incident/scripts/redact-sentinel.sh,
       decoy=/tmp/tmp.XxyBHx8cde/t19-contributor-tree/plugins/soleur/skills/incident/scripts/redact-sentinel.sh)

Total: 86 pass, 1 fail
EXIT=1
```

## What the RED proves

`resolved` and `decoy` are **the same path, byte for byte**. The anchor as committed does not
merely resolve somewhere untrustworthy — it resolves onto the exact file a hostile PR would
plant. This is the vulnerability demonstrated, not modelled.

The three sub-assertions are load-bearing in different ways:

- **19a is the positive control.** The real sentinel exits 1 on the synthesized fixture and the
  decoy exits 0 on the same fixture. Without this the decoy could be an inert file and 19c would
  be asserting containment against nothing.
- **19b is the anti-vacuity gate on the oracle.** The expected value is extracted from the
  committed `incident/SKILL.md` at runtime and must be found in it. A future edit that stops
  reading the producer and pins a literal here goes RED as soon as the SKILL.md drifts.
- **19c is the property.** Plugin root unresolved, CWD inside the checked-out contributor tree —
  the state `review/SKILL.md`'s `gh pr checkout` instruction actually produces.

Tests 1-18 are unaffected (86 pass), so the migration is not being validated by a suite that
changed underneath it.
