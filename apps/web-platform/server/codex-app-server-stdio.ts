import type { CodexCredentialLease } from "./codex-code-adapter";
import { createCodexAppServerEventBridge, type CodexAppServerEventBridge } from "./codex-app-server-event-bridge";
import { decodeCodexJsonlStream } from "./codex-app-server-jsonl";
import { createCodexRpcClient, type CodexRpcChannel, type CodexRpcClient } from "./codex-app-server-rpc-client";

export interface CodexAppServerStdioProcess {
  stdin: CodexRpcChannel;
  stdout: AsyncIterable<string>;
  kill(): Promise<void> | void;
  onExit(handler: (code?: number | null, signal?: string | null) => void): void | (() => void);
}

export interface CodexAppServerStdioLauncher {
  spawn(lease: CodexCredentialLease): Promise<CodexAppServerStdioProcess> | CodexAppServerStdioProcess;
}

export interface CodexAppServerStdioConnection {
  client: CodexRpcClient;
  events: CodexAppServerEventBridge;
  dispose(): Promise<void>;
}

function sourceError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

/**
 * Own the provider process and keep its credentials at the launch boundary.
 * The returned RPC client and event stream contain no process or credential
 * details; callers only control neutral requests and lifecycle disposal.
 */
export function createCodexAppServerStdio(
  launcher: CodexAppServerStdioLauncher,
  options: { maxEventSize?: number } = {},
): { open(lease: CodexCredentialLease): Promise<CodexAppServerStdioConnection> } {
  return {
    open: async (lease) => {
      let process: CodexAppServerStdioProcess;
      try {
        process = await launcher.spawn(lease);
      } catch {
        throw sourceError("Codex App Server process could not be started", "codex_process_launch_failed");
      }

      const events = createCodexAppServerEventBridge({ maxSize: options.maxEventSize });
      const client = createCodexRpcClient(process.stdin, {
        onNotification: events.onNotification,
        onClose: events.onClose,
      });
      let disposed = false;
      const removeExitHandler = process.onExit(() => {
        if (!disposed) client.close(sourceError("Codex App Server process exited", "codex_process_exit"));
      });

      const reader = (async () => {
        try {
          for await (const message of decodeCodexJsonlStream(process.stdout)) client.receive(message);
          if (!disposed) client.close(sourceError("Codex App Server output ended", "codex_process_output_ended"));
        } catch (error) {
          client.close(error);
        }
      })();

      return {
        client,
        events,
        dispose: async () => {
          if (disposed) return;
          disposed = true;
          if (typeof removeExitHandler === "function") removeExitHandler();
          client.close(sourceError("Codex App Server connection disposed", "codex_process_disposed"));
          try {
            await process.kill();
            await reader.catch(() => undefined);
          } catch {
            throw sourceError("Codex App Server process could not be stopped", "codex_process_dispose_failed");
          }
        },
      };
    },
  };
}
