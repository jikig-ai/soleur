# Browser-Readiness Preflight (unsupported-host guard)

Loaded by `qa`'s nav-states gate — run this BEFORE the first Playwright
invocation. On a host newer than the pinned Playwright officially supports
(e.g. Ubuntu 26.04 vs the `apps/web-platform` `@playwright/test` pin), a
plain `playwright install` fails with `does not support chromium ... on
<os>` and every test then dies at `browserType.launch: Executable doesn't
exist` **before any navigation** — the false-fail that repeatedly costs a
QA session its whole run. Recover automatically by retrying the install
with the host-platform override, which pulls the nearest supported fallback
build (verified `ubuntu26.04-x64` → `ubuntu24.04-x64`; once the fallback
build is in cache the launcher resolves it at runtime with NO override, so
the override stays out of the run command and can never leak onto a
supported host like CI's Jammy container):

```bash
cd apps/web-platform
QA_PW_LOG=$(mktemp -p "$(mktemp -d -t soleur-run.$$.XXXXXXXX)")
npx playwright install chromium >"$QA_PW_LOG" 2>&1 \
  || PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64 npx playwright install chromium
# on failure read it for the diagnosis, then `rm -f "$QA_PW_LOG"` (#10017).
```

**Node 26 stalls the install above instead of failing it** (0% CPU after the download reaches 100%, the zip extractor stops mid-file), so the `||` fallback does not fire until the hang is killed: the log stops growing for 60 s while the process sits idle means stalled, so kill it. Bound the install by prefixing `timeout 300` and, from `apps/web-platform` (where `bunx` resolves the local `playwright`), run it under Bun: `timeout 300 bunx --bun playwright install chromium`, with `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64` in front on an unsupported host as below. Without Bun: unzip the archive into `~/.cache/ms-playwright/<revision directory>` and create an empty `INSTALLATION_COMPLETE` there (`knowledge-base/project/learnings/2026-11-09-playwright-browser-install-stalls-under-node-26-and-completes-under-bun.md`).
