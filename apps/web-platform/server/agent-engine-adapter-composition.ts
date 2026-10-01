import type { EngineAdapter } from "./agent-engine-contract";
import { createClaudeCodeAdapter, type ClaudeCodeAdapterTransport } from "./claude-code-adapter";
import { createCodexAuthBoundary, createCodexCodeAdapter, type CodexAuthProvider, type CodexCodeAdapterTransport } from "./codex-code-adapter";
import type { EngineAdapterFactory } from "./agent-engine-adapter-factory";

export function composeReviewedEngineFactories(options: {
  /** Additive registrations for reviewed engines beyond the built-in adapters. */
  additionalFactories?: Readonly<Record<string, EngineAdapterFactory>>;
  claudeTransport?: ClaudeCodeAdapterTransport;
  codexTransport?: CodexCodeAdapterTransport;
  codexAuth?: CodexAuthProvider;
  createClaude?: (transport: ClaudeCodeAdapterTransport) => EngineAdapter;
  createCodex?: (transport: CodexCodeAdapterTransport, auth: ReturnType<typeof createCodexAuthBoundary>) => EngineAdapter;
}): Partial<Record<string, EngineAdapterFactory>> {
  const factories: Partial<Record<string, EngineAdapterFactory>> = { ...options.additionalFactories };
  if (options.claudeTransport) {
    const create = options.createClaude ?? createClaudeCodeAdapter;
    factories["claude-code"] = () => create(options.claudeTransport!);
  }
  if (options.codexTransport && options.codexAuth) {
    const create = options.createCodex ?? createCodexCodeAdapter;
    factories.codex = () => create(options.codexTransport!, createCodexAuthBoundary(options.codexAuth!));
  }
  return factories;
}
