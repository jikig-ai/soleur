# Decision challenges: feat-one-shot-9219-inngest-dead-pause-resume

Taste findings from plan review, recorded headless. The plan kept its direction. Each item is
open for the operator to overturn.

## 1. Keep a verb-allowlist guard, or add none (taste)

- **Challenge (code-simplicity-reviewer):** P3 (a regression guard) was not asked for by #9219.
  The reviewer proposed deleting the old `"$INSTALL_PATH" resume` assertion and adding no guard,
  or at most a blacklist grep.
- **Plan's choice:** keep a subset allowlist (`start|version`) with a non-empty floor, about 6
  lines. DHH and the CTO both kept a guard, and it replaces an assertion that must go anyway.
- **Cost if overturned:** none at runtime. Reintroducing a no-op verb would go uncaught.

## 2. Keep the `DRAIN_SLEEP_SEC` sleep, or delete it (taste)

- **Challenge (DHH, advisor consult):** the sleep drains nothing, because the server keeps
  accepting work until the restart, and nothing in the repo sets the variable. Deleting it
  (Alternative C) is the most honest fix.
- **Plan's choice:** keep it, renamed in prose to a "settle delay" with a comment saying the
  name is historical. That avoids an upgrade-timing change the issue did not ask for.
- **Cost if overturned:** about 2 s less on in-place upgrades and one more deleted line.
