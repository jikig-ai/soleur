// The fake git-data transport for real-git suites (Ref #9601): the production push / fetch argv, run by real git
// against local bare stores. It stands in for `gitWithPrivateKeyAuth` only; everything else the code under test
// does runs for real.
//
// Routing: `-c url.file://<storesRoot>/.insteadOf=<git-data URL base>` maps the production ssh URL onto
// `<storesRoot>/<workspaceId>.git`. git takes the LONGEST matching insteadOf, and the workspace's local config is read
// before `-c`, so a carrier planted in the workspace config wins when it is at least as long as that base (the full
// git-data URL is). A SHORTER carrier is masked by this prefix here, although it would take effect in production,
// where no such prefix exists. `-c protocol.ssh.allow=never` makes a routing miss fail loudly instead of dialing the
// real git-data host.
//
// This is not the production transport: `gitWithPrivateKeyAuth` sets `GIT_ALLOW_PROTOCOL=ssh`, so a `file://` carrier
// would not reach a local store there. A B-landing control through this fake therefore proves the carrier is live
// under git's URL resolution, not that production would reach a local file.
//
// Why pushes go through DRAINING_RECEIVE_PACK (the F21 flake, measured 2026-11-11 on git 2.56.0, see the spec's
// measurements.md AC2): a push that has nothing to update but carries push options sends a flush packet, then the
// push-option packets, then a second, separately written flush (send-pack.c). receive-pack reads the first flush,
// finds no commands, and exits without reading the rest. When it exits before the client's last write, the client
// takes EPIPE, which git turns into SIGPIPE: rc 141, empty stderr. Over a direct client-to-receive-pack pipe this hit
// 1972 of 10000 no-op pushes under ten parallel copies; with this wrapper 0 of 10000. The wrapper keeps reading its
// stdin after receive-pack exits and closes its own stdout so the client still sees EOF, the way an ssh-like
// intermediary keeps the pipe open. It MODELS that intermediary; it is not ssh, and the production ssh path was not
// measured. `exit $s` keeps receive-pack's own status (a rejected ref is reported through the status report either
// way; the status only matters if receive-pack dies before reporting). Cost: one extra `sh` per push.
import type { execFileSync as ExecFileSync } from "node:child_process";

export const GIT_DATA_URL_BASE = "ssh://git@10.0.1.20/mnt/git-data/repositories/";

export const DRAINING_RECEIVE_PACK = `sh -c 'git-receive-pack "$0"; s=$?; exec >/dev/null; cat; exit $s'`;

export interface GitDataLocalOptions {
  /** The real execFileSync: suites that mock child_process pass the actual one. */
  exec: typeof ExecFileSync;
  cwd: string;
  /** Directory holding `<workspaceId>.git` bare stores. */
  storesRoot: string;
  /** The fixture root the env is built for (the discovery ceiling). */
  fixtureRoot: string;
  /**
   * The shared fixture-env builder (`plugins/soleur/test/lib/git-fixture-env`), injected as
   * `test/helpers/host-git-carrier-fixture.ts` does, so this helper takes its env from it without importing outside the app.
   */
  gitFixtureEnv: (root: string) => NodeJS.ProcessEnv;
  /** Per-call bound, so a hung transport fails the row instead of the CI job. Default 60 s (production's push bound). */
  timeoutMs?: number;
}

/**
 * Runs the production git argv (`push ...` or `fetch ...`) against the local stores. On failure throws
 * `Command failed: git <verb> (status <n>, signal <s>)` carrying git's stderr, the shape the production retry
 * classifier and the rows read.
 */
export function runGitDataLocal(args: string[], opts: GitDataLocalOptions): Buffer {
  const { gitFixtureEnv } = opts;
  const verb = args[0] ?? "";
  if (verb !== "push" && verb !== "fetch") throw new Error(`runGitDataLocal: unsupported verb ${JSON.stringify(verb)}`);
  // A later --receive-pack / --exec / --upload-pack would supersede or bypass the wrapper; production never passes one.
  if (args.some((a) => /^--(receive-pack|exec|upload-pack)(=|$)/.test(a))) {
    throw new Error("runGitDataLocal: the argv already names a remote program");
  }
  // Only a push talks to receive-pack. A fetch through the receive-pack wrapper would fail, so never splice it there.
  const argv = verb === "push" ? ["push", `--receive-pack=${DRAINING_RECEIVE_PACK}`, ...args.slice(1)] : args;
  try {
    return opts.exec(
      "git",
      ["-c", "protocol.ssh.allow=never", "-c", `url.file://${opts.storesRoot}/.insteadOf=${GIT_DATA_URL_BASE}`, ...argv],
      {
        cwd: opts.cwd,
        env: gitFixtureEnv(opts.fixtureRoot),
        stdio: "pipe",
        timeout: opts.timeoutMs ?? 60_000,
        killSignal: "SIGKILL",
      },
    );
  } catch (e) {
    const { stderr: raw, status, signal } = e as { stderr?: unknown; status?: unknown; signal?: unknown };
    const stderr = String(raw ?? "");
    throw Object.assign(
      new Error(`Command failed: git ${verb} (status ${String(status ?? "none")}, signal ${String(signal ?? "none")})\n${stderr}`),
      { stderr, status, signal },
    );
  }
}
