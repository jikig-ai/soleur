# Decision Challenges — feat-one-shot-9963-syslog-systemd-journald-path

Headless one-shot planning run for issue #9963. This harness has no Agent/Task
tool, so the `soleur:plan-review` panel and any CTO rulings could not be
spawned. Technical rows therefore carry `pending - assumed: <default>` per the
technical-ruling-delegation contract; ship renders these into the PR body.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Control row emitted as `logger -t systemd -p err` (spoofed `SYSLOG_IDENTIFIER=systemd`) inside `inngest-server-probe.sh`, vs a dedicated `soleur-systemd-journald-control.{service,timer}` unit, vs generating real PID-1 failure rows | technical | pending - assumed: spoofed-tag emit inside the existing hourly probe script. Rationale: the discriminator consumers filter on `"SYSLOG_IDENTIFIER":"systemd"` — the control must prove THAT field shape transits; a dedicated unit buys no property (cadence + unconditional emit already exist); real-failure generation would pollute `systemctl --failed` and risk failure-pattern consumers. |
| New ADR (provisional 286) vs amending ADR-192 to record the OR-over-fields mechanism + control convention | technical | pending - assumed: new short ADR. Rationale: the finding binds three open issues (#6551, #8875, #9963) and is a delivery-path fact with a deferral decision, broader than ADR-192's read-side three-state scope. |
| Scope: document + control only; semantic re-architecture of Sources 1/2 deferred to #6551/#8875 | technical | pending - assumed: defer. Rationale: issue #9963 asks to "pin" (identify + document + control); the OR-arm is already load-bearing on purpose for Source 2's #7898 crit-row sink, so a semantics change is a separate quota/behaviour decision. |
| `--control-require` flag added to betterstack-assert-absence.sh (beyond the literal ask) | technical | pending - assumed: include. Rationale: marker-substring controls are satisfiable by the measured webhook/issue-body contamination class (10 false matches on #9939's own title); field-scoping is the only form that binds the systemd path (ADR-192 I-2). |
| Brand-survival threshold `none` | taste | assumed: none — infra-internal observability machinery; worst outcome is a wrong verdict in an operator-facing assertion, no user-facing artifact or data exposure. Challengeable per the template's own marker. |
| `plan-review` reviewer panel not spawned (no Agent tool in this harness); self-review applied instead | operator (process) | pending - the parent pipeline may re-run `soleur:plan-review` on the plan file if a richer review is wanted; the plan's Guard Contract and mutation matrix were written to compensate for the missing adversarial seats. |
