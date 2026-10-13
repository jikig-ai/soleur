# Phase 3.2 live verification (real npx @playwright/mcp@0.0.78, headless, scratch profiles) — 2026-09-14

Page: data: URL form with password=ZZQP-SENTINEL-7980 and Notes=ZZQP-BENIGN-7980. The surviving sentinel in each snapshot result is in '- Page URL:' (the data: URL itself — the named prose residual); the tree row reads 'textbox "Password" [ref=e4]: <redacted>', Notes intact, trailer appended, tools/list marker present, navigate carries no '### Snapshot', 0 page-*.yml written.

- eof: proxy rc=0, child pgid 1405320, group_after=0; snapshot found=1 isError=false trailer=1 tree-sentinel=0 benign=2; stderr: child exited rc=0 signal=0 (stdin EOF)
- sigterm: proxy rc=0, child pgid 1449562, group_after=0; snapshot found=1 isError=false trailer=1 tree-sentinel=0 benign=2; stderr: child exited rc=0 signal=0 (signal)
- sigkill: proxy rc=-9, child pgid 1411676, group_after=0; snapshot found=1 isError=false trailer=1 tree-sentinel=0 benign=2; stderr: wrapping Playwright 1.62.0-alpha-1783623505000 protocol 2025-06-18
- sigkill: proxy SIGKILLed (rc=-9, no teardown line by construction); the driver ran the wrapper's reaper pattern and the group is empty.
- first attempt used --isolated together with --user-data-dir, which 0.0.78 rejects ('Browser userDataDir is not supported in isolated mode'); the proxy relayed the child's rc=1 and exited 1 — the argv error was mine, not the proxy's.
