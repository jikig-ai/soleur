---
name: clean-third-party
description: "This is a clean third-party fixture for skill-security-scan calibration. Should pass all five categories with no findings."
---

# Clean Third-Party Skill

A simple example skill with no security concerns. Reads configuration from a
local file, makes a single allowlisted HTTP request, and writes output to
stdout.

## Example usage

```bash
echo "hello" | ./scripts/process.sh
```

## Configuration

```yaml
threshold: 0.5
output: stdout
```

Documentation: see https://example.org/docs (not first-party but no utm tag,
not a redirect host, no beacon — should remain LOW-RISK).
