// Lock-free, host-side atomic writer for `.git/config` identity seeds (#6191,
// ADR-099 §Known latent surfaces). Replaces the raw `git config user.name/email`
// writes that seed the workspace OWNER as the local identity in `workspace.ts`.
//
// Design — copy-then-edit-then-rename (lock-free BY CONSTRUCTION, never touches
// `.git/config.lock`):
//   1. Resolve the repo's `.git/config`.
//   2. `cp -p` the current config → a same-dir temp. LOAD-BEARING: `git config
//      --file <tmp>` starts from an EMPTY file, so seeding the temp with the
//      current contents first is what prevents dropping every OTHER config key.
//   3. Edit the temp with git's own INI writer (`git config --file <tmp> …`).
//   4. `renameSync(tmp, config)` — POSIX-atomic; readers see either the old or
//      the new file, never a torn write, and `config.lock` is never involved.
// Mirrors the two blessed in-repo idioms: `worktree-manager.sh`'s bash
// `atomic_git_config` (cp-first → `git config --file` → `mv -f`) and
// `workspace-permission-lock.ts`'s `renameSync` atomicity.
//
// CONCURRENCY: safe under its call sites because it is SYNCHRONOUS (`void` /
// `renameSync`) and the platform runs a SINGLE Next.js worker per container —
// two calls cannot interleave in the event loop. Atomic `rename(2)` prevents a
// TORN write but does NOT serialize a concurrent read-modify-write: a
// multi-process deployment or any future `async` variant that awaited between
// the `cp` and the `rename` would inherit a silent lost-update. Multi-process
// coordination is OUT OF SCOPE at current scale (mirrors
// `workspace-permission-lock.ts:1-10`); no in-process Mutex is added. Do NOT
// re-state this safety as "lock-free ⇒ safe under >1 caller".
//
// DURABILITY: like the bash precedent (and unlike `workspace-permission-lock.ts`,
// which owns its write fd and `fdatasync`es before rename), this helper cannot
// fsync — git owns the temp fd inside `execFileSync`. So the forgone window is
// POST-rename / pre-flush: a machine crash after the dir-entry swap but before
// the data blocks journal could leave a torn config. Accepted at this severity
// (best-effort, re-seedable owner seed; ADR-099 low-severity). The PRE-rename
// window is safe regardless — a crash there discards the temp, leaving the old
// config intact.
//
// Best-effort: NEVER throws (preserves `workspace.ts`'s current non-stranding
// behavior). Because it never throws, the caller cannot distinguish "seeded"
// from "aborted, unseeded" — which is WHY BOTH failure branches emit a CAPTURED
// `reportSilentFallback` Sentry event (cq-silent-fallback-must-mirror-to-sentry):
// the masked-target pre-check (op="masked-target") AND the generic cp/write/rename
// failure (op="write", covering disk/perms/rename-EBUSY). Together they are the
// loud signal for ANY cause of a workspace provisioning with an unseeded identity
// — no unseed outcome degrades to a droppable breadcrumb.

import {
  chmodSync,
  copyFileSync,
  renameSync,
  statSync,
  unlinkSync,
} from "fs";
import { execFileSync } from "child_process";
import path from "path";
import { randomUUID } from "crypto";

import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const moduleLog = createChildLogger("git-config-atomic");

type Logger = ReturnType<typeof createChildLogger>;

/**
 * Resolve `<cwd>`'s `.git/config` path. Uses `git rev-parse --git-dir` when it
 * works (handles gitlink `.git` files / non-default git dirs), falling back to
 * `<cwd>/.git` — the normal non-bare clone `workspace.ts` produces — when git
 * cannot answer (e.g. an anomalous config the caller is about to refuse).
 */
function resolveGitConfigPath(cwd: string): string {
  let gitDir: string;
  try {
    const out = execFileSync("git", ["rev-parse", "--git-dir"], {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
    })
      .toString()
      .trim();
    gitDir = path.isAbsolute(out) ? out : path.join(cwd, out);
  } catch {
    gitDir = path.join(cwd, ".git");
  }
  return path.join(gitDir, "config");
}

/**
 * Atomically apply a `git config` write to `<cwd>`'s `.git/config`.
 *
 * @param cwd  Working directory of the repo whose `.git/config` to edit.
 * @param args The git-config argv, e.g. `["config", "user.email", "a@b.com"]`.
 *             A leading `"config"` token is optional (stripped if present).
 * @param opts `log` overrides the module logger (structured, → Better Stack).
 *
 * Never throws. On a masked / non-regular config target (must never occur
 * host-side) it fires a captured `reportSilentFallback` event + error log and
 * aborts WITHOUT the rename. On any other failure it cleans up the temp and
 * warns — the workspace falls through to today's non-stranding behavior.
 */
export function atomicGitConfig(
  cwd: string,
  args: string[],
  opts?: { log?: Logger },
): void {
  const log = opts?.log ?? moduleLog;
  const config = resolveGitConfigPath(cwd);

  // Defensive masked-target check. A non-regular node AT the config target
  // (character device from the sandbox mask, directory, fifo, …) must never
  // occur host-side; if it does, this is a real anomaly — fail LOUD via a
  // captured Sentry event and abort without renaming over it.
  let configExists = false;
  let configMode: number | undefined;
  try {
    const st = statSync(config);
    if (!st.isFile()) {
      log.error(
        { config, op: "masked-target" },
        "git-config-atomic: refusing non-regular .git/config target; identity not seeded",
      );
      reportSilentFallback(
        new Error("git-config-atomic: non-regular config target"),
        {
          feature: "git-config-atomic",
          op: "masked-target",
          extra: { config },
        },
      );
      return; // abort WITHOUT the rename
    }
    configExists = true;
    configMode = st.mode;
  } catch {
    // ENOENT — no config yet; the temp starts empty and git creates it.
  }

  // `git config --file <tmp>` starts from an EMPTY file, so seed the temp with
  // the current contents first or every other key is dropped.
  const tmp = `${config}.soleur-tmp.${process.pid}.${randomUUID().slice(0, 8)}`;
  try {
    if (configExists) {
      copyFileSync(config, tmp);
      if (configMode !== undefined) {
        try {
          chmodSync(tmp, configMode); // preserve mode (cp -p parity)
        } catch {
          // best-effort — mode preservation is not load-bearing.
        }
      }
    }
    // Strip a leading "config" subcommand token if the caller included one.
    const configArgs = args[0] === "config" ? args.slice(1) : args;
    execFileSync("git", ["config", "--file", tmp, ...configArgs], {
      stdio: "pipe",
    });
    // POSIX-atomic replace. Never touches `.git/config.lock`.
    renameSync(tmp, config);
  } catch (err) {
    try {
      unlinkSync(tmp);
    } catch {
      // tmp may not exist (cp/open failed) or was already renamed — ignore.
    }
    // Non-stranding: provisioning falls through to today's behavior with an
    // UNSEEDED identity — the same user-invisible degraded outcome as the
    // masked-target branch. So mirror a CAPTURED Sentry event with the same
    // queryable vocabulary (cq-silent-fallback-must-mirror-to-sentry); a bare
    // log.warn yields only a droppable breadcrumb. This does NOT add an alert
    // rule — a transient disk/perms blip stays queryable, not paging.
    reportSilentFallback(err, {
      feature: "git-config-atomic",
      op: "write",
      extra: { config },
    });
    log.error(
      { err, config, op: "write" },
      "git-config-atomic: write failed; identity seed skipped (non-stranding)",
    );
  }
}
