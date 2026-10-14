import type { CodexCredentialLease } from "./codex-code-adapter";
import type { CodexAppServerStdioLauncher, CodexAppServerStdioProcess } from "./codex-app-server-stdio";

interface ChildProcessLike {
  stdin: { write(chunk: string, callback: (error?: Error | null) => void): void };
  stdout: AsyncIterable<Buffer | string>;
  stderr: AsyncIterable<Buffer | string>;
  kill(signal?: string): boolean;
  once(event: "error" | "exit", listener: (...args: unknown[]) => void): void;
  on(event: "error" | "exit", listener: (...args: unknown[]) => void): void;
}

interface CodexAppServerLauncherOptions {
  command: string;
  cwd: string;
  environment: (lease: CodexCredentialLease) => Record<string, string>;
  spawn: (command: string, args: readonly string[], options: { cwd: string; env: Record<string, string>; stdio: ["pipe", "pipe", "pipe"] }) => ChildProcessLike;
}

/**
 * Server-owned launcher contract. The caller supplies the approved binary,
 * working directory, and minimal environment; no ambient process environment
 * or credential storage is inherited by the provider process.
 */
export function createCodexAppServerLauncher(options: CodexAppServerLauncherOptions): CodexAppServerStdioLauncher {
  return {
    spawn: (lease) => {
      const child = options.spawn(options.command, ["app-server", "--stdio"], {
        cwd: options.cwd,
        env: options.environment(lease),
        stdio: ["pipe", "pipe", "pipe"],
      });
      let exited = false;
      const exitListeners = new Set<(code?: number | null, signal?: string | null) => void>();
      const notifyExit = (...args: unknown[]) => {
        if (exited) return;
        exited = true;
        for (const listener of exitListeners) listener(args[0] as number | null, args[1] as string | null);
      };
      child.on("exit", notifyExit);
      child.on("error", notifyExit);
      // Drain provider diagnostics without forwarding them to logs; stderr may
      // otherwise fill and stall the App Server while prompts remain private.
      void (async () => {
        for await (const _chunk of child.stderr) { /* intentionally discarded */ }
      })();
      return {
        stdin: {
          write: (chunk) => new Promise<void>((resolve, reject) => {
            child.stdin.write(chunk, (error) => error ? reject(error) : resolve());
          }),
        },
        stdout: (async function* () {
          for await (const chunk of child.stdout) yield typeof chunk === "string" ? chunk : chunk.toString("utf8");
        })(),
        kill: () => { child.kill("SIGTERM"); },
        onExit: (handler) => {
          exitListeners.add(handler);
          return () => exitListeners.delete(handler);
        },
      } satisfies CodexAppServerStdioProcess;
    },
  };
}
