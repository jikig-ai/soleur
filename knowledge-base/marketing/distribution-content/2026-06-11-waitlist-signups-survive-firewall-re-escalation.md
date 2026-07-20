---
title: "Waitlist signups now survive vendor firewall re-escalation"
type: feature-launch
publish_date: 2026-07-16
channels: x
status: published
pr_reference: "#5153"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

Our waitlist silently rejected every signup for 65 hours. The code was fine. The server was fine. The blocker: our email vendor's own anti-spam firewall was risk-scoring our datacenter IP — because we weren't telling it who the actual visitor was.

2/ An AI agent diagnosed it with no SSH and no dashboard: read the error stream, replayed the exact API call with the real key from the secret store, and got the vendor's hidden error body in one curl. Recovery was a one-field API PATCH.

3/ Just shipped the hardening: the signup route now forwards each visitor's real IP, so the vendor scores the human, not our server. Signups survive even if the firewall re-escalates on its own. Full build-in-public post-mortem coming this week.
