---
description: Command-surface loader-substitution probe (#8308 Phase 0, Arm 5)
---

# Loader substitution probe — command surface (#8308 Arm 5)

Sibling of `../skills/zzzprobe/SKILL.md`, which measures the SKILL surface. This one
measures the **command** surface, because `plugins/soleur/commands/go.md` is a command
and #8308's whole question is which expansion forms the loader substitutes there.

Run this bash block EXACTLY as delivered, with no edits:

```bash
OUT="${TMPDIR:-/tmp}/arm5-probe-out.txt"
{
  echo "RUNTIME_ENV_RAW=[${CLAUDE_PLUGIN_ROOT:-<UNSET-AT-RUNTIME>}]"
  echo "ENV_GREP=[$(env | grep -c CLAUDE_PLUGIN_ROOT)]"
} > "$OUT"
cat > "$OUT.delivered" <<'PROBE_EOF'
BARE=${CLAUDE_PLUGIN_ROOT}
FORM_8061=${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}
UNBRACED=$CLAUDE_PLUGIN_ROOT
SINGLEQ='${CLAUDE_PLUGIN_ROOT}'
PROBE_EOF
echo PROBE_WRITTEN
```
