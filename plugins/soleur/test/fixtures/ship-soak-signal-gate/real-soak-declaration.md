# plan: widen the retry budget for the queue drainer

## Close criteria

The tracker closes after a 7-day post-deploy soak during which the drainer's
retry rate stays at ~0. If a single retry storm occurs inside that window the
criterion resets and the soak restarts from the redeploy.

Soak/follow-through enrollment: enrolled, probe lands with this change.
