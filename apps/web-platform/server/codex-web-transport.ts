import type { EngineObservability } from "./agent-engine-observability";
import { createCodexAppServerTransport, type CodexCodeAdapterTransport } from "./codex-code-adapter";
import { createCodexAppServerLifecycleSource } from "./codex-app-server-lifecycle-source";
import { createCodexAppServerStdio, type CodexAppServerStdioLauncher } from "./codex-app-server-stdio";

export interface CodexWebTransportOptions {
  launcher: CodexAppServerStdioLauncher;
  nextRequestId: () => string;
  cwd?: string;
  maxEventSize?: number;
  observability?: EngineObservability;
}

/** Compose the server-owned process boundary into the neutral Codex adapter. */
export function createCodexWebTransport(options: CodexWebTransportOptions): CodexCodeAdapterTransport {
  const stdio = createCodexAppServerStdio(options.launcher, { maxEventSize: options.maxEventSize });
  const source = createCodexAppServerLifecycleSource({
    open: stdio.open,
    nextRequestId: options.nextRequestId,
    cwd: options.cwd,
    observability: options.observability,
  });
  return createCodexAppServerTransport(source);
}
