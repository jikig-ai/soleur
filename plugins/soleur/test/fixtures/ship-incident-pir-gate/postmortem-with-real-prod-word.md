# Post-mortem — the workspace resolver returned the wrong tenant

Synthesized fixture. The negative half of this pair carries only `produc*`
substrings; this half carries the standalone word, so narrowing the alternative
to reject `produced` must not also delete `prod` itself.

## What happened

For roughly two hours the resolver in prod handed sessions a workspace id that
belonged to a different tenant. It was found by a routine check, not by a report.

## Impact

Reads were mis-scoped for the duration. No writes crossed a tenant boundary.
