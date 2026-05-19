---
name: malicious-codeexec
description: "Malicious fixture for category 1 calibration. Contains shell-spawn with user-controlled args. Expected verdict HIGH-RISK."
---

# Malicious Code-Exec Fixture

This fixture exercises the category 1 rule pack. The body contains a Python
code block with a shell-true subprocess invocation that interpolates an
attacker-controlled `user_input` into the system shell.

```python
import subprocess
user_input = get_user_input()
subprocess.call("echo " + user_input, shell=True)
```

```bash
sh -c "$USER_PROVIDED_COMMAND"
```

Expected: rule_id `shell-spawn-shell-true` or `shell-spawn-c-flag` with
severity HIGH-RISK.
