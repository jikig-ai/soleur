// Thin CLI entry for the runtime Bash synthetic (infra/web-bash-synthetic.sh; ADR-079 "Addendum — 2026-10-22 (#10455 b)").
// Prints which seccomp artifact a NO-EGRESS session would be spawned with RIGHT NOW: `unixdeny` when the runtime flag
// `agent-sandbox-unix-deny` resolves ON, `base` when it resolves OFF, `unresolved` when Flagsmith did not answer (see
// ./resolve-sandbox-selector). Never the env mirror: the synthetic tests the artifact production would select after the #10548
// flip, or it skips the run.
// Bundled to infra/lib/resolve-sandbox-selector.mjs by the Dockerfile builder stage. The answer is ONE sentinel line
// (`SOLEUR_SELECTOR=base|unixdeny|unresolved`) because the resolver's logger may write to stdout too; the host greps for it.
import { selectorSentinel } from "./resolve-sandbox-selector";

process.stdout.write(`SOLEUR_SELECTOR=${await selectorSentinel()}\n`);
// Exit explicitly: the flag client and the logger may hold handles that would keep a one-shot process alive.
process.exit(0);
