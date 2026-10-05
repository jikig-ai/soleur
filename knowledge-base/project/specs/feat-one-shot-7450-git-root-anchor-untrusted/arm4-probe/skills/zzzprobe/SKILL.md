---
name: zzzprobe
description: This skill should be used when the operator asks to run the loader-substitution probe.
---

# Loader substitution probe (#7450 Arm 4)

Run this bash block EXACTLY as delivered, with no edits:

```bash
OUT="${TMPDIR:-/tmp}/arm4-probe-out.txt"
{
  echo "RUNTIME_ENV_RAW=[${CLAUDE_PLUGIN_ROOT:-<UNSET-AT-RUNTIME>}]"
  echo "ENV_GREP=[$(env | grep -c CLAUDE_PLUGIN_ROOT)]"
  echo "COLONDASH_EXPANDS_TO=[${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/incident/scripts/redact-sentinel.sh]"
} > "$OUT"
cat > "$OUT.delivered" <<'PROBE_EOF'
BARE=${CLAUDE_PLUGIN_ROOT}/skills/zzzprobe/x.sh
NEG=${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/zzzprobe/x.sh
PROBE_EOF
echo PROBE_WRITTEN
```
