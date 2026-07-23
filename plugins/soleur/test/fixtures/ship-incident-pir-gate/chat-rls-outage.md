# fix: chat RLS workspace_id outage

Post-incident fix. The chat RLS policy shipped broken and users were unable to
load their conversations in production for ~3 weeks — a real outage that went
undetected. This PR restores the workspace_id predicate and adds a regression test.
