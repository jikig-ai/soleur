# Arm 4 probe — re-runnable

The measurement in `../phase-1-measurement.md` §Arm 4. Committed so the claim can be
re-executed rather than believed.

```bash
CLAUDE_PLUGIN_ROOT=/tmp/DECOY-EVIL-ROOT claude -p \
  --plugin-dir "$(pwd)" --allowedTools "Bash,Skill" \
  "Invoke the zzzprobe skill and run its bash block exactly as delivered. Then stop."
cat "${TMPDIR:-/tmp}/arm4-probe-out.txt" "${TMPDIR:-/tmp}/arm4-probe-out.txt.delivered"
```

**Expected, and what each line establishes**

| Line | Expected | Establishes |
| --- | --- | --- |
| `BARE=` | the **real** `--plugin-dir` path | the loader substitutes a bare token on the SKILL surface, at delivery |
| `NEG=` | literal, unsubstituted | the transform is exact-literal, so the `:-` form is never substituted |
| `ENV_GREP=[1]` | `1` | the decoy WAS live in the executing subprocess — the control that makes "ambient ignored" distinguishable from "ambient never propagated" |
| `COLONDASH_EXPANDS_TO=` | `/tmp/DECOY-EVIL-ROOT/...` | the pre-fix form expands to an attacker-chosen root |

This is a **synthetic** plugin, not `incident/SKILL.md`, and it reproduces the
**ambient-environment** variant only. See the scope note in `../phase-1-measurement.md`.
