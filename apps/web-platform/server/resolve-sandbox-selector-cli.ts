// Thin CLI entry for the runtime Bash synthetic (infra/web-bash-synthetic.sh; ADR-079 addendum).
// Prints which seccomp artifact a NO-EGRESS session would be spawned with RIGHT NOW: `unixdeny` when the runtime flag
// `agent-sandbox-unix-deny` resolves ON, else `base`. It calls the dispatcher's own resolver (fails closed to `base`,
// memoised), never the env mirror, so the synthetic tests the artifact production would select after the #10548 flip.
// Bundled to infra/lib/resolve-sandbox-selector.mjs by the Dockerfile builder stage. The answer is ONE sentinel line
// (`SOLEUR_SELECTOR=base|unixdeny`) because the resolver's logger may write to stdout too; the host greps for the sentinel.
import { resolveSandboxUnixDeny } from "./resolve-sandbox-unix-deny";

const on = await resolveSandboxUnixDeny();
process.stdout.write(`SOLEUR_SELECTOR=${on ? "unixdeny" : "base"}\n`);
// Exit explicitly: the flag client and the logger may hold handles that would keep a one-shot process alive.
process.exit(0);
