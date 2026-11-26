# Decision challenges: feat-one-shot-12931-zone-rest-settings-probe

Every decision for this plan is persisted here. `soleur:ship` renders this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| How the `zones/<zone>/settings\|PATCH` write row establishes its 403 deny control, given PATCH /zones/<z>/settings parses JSON before authorization | technical | Ruled by CTO agent, 2026-11-26: settings PATCH row sends a fixed JSON SETTINGS_PROBE_BODY naming a nonexistent probe-prefixed setting id, with the guards listed - JSON parsing precedes authorization on PATCH /zones/<z>/settings, so no non-JSON body can establish the 403 control |
