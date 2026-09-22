import { composeReviewedEngineFactories } from "./agent-engine-adapter-composition";
import type { CodexAuthMode, CodexAuthProvider, CodexCodeAdapterTransport } from "./codex-code-adapter";
import type { EngineAdapterFactory } from "./agent-engine-adapter-factory";
import { createCodexApiKeyProviderForUser } from "./codex-credential-provider";

interface CodexWebRuntimeOptions {
  userId: string;
  authMode: CodexAuthMode;
  transport: CodexCodeAdapterTransport;
  /** Injected by the approved managed-account Web authorization flow. */
  managedProvider?: CodexAuthProvider;
  /** Test/runtime override for the encrypted Web-settings API-key provider. */
  apiKeyProvider?: CodexAuthProvider;
  additionalFactories?: Readonly<Record<string, EngineAdapterFactory>>;
}

/** Select exactly the persisted auth mode; never fall back between credential modes. */
export function createCodexWebEngineFactories(options: CodexWebRuntimeOptions): Partial<Record<string, EngineAdapterFactory>> {
  const auth = options.authMode === "api-key"
    ? (options.apiKeyProvider ?? createCodexApiKeyProviderForUser(options.userId))
    : options.managedProvider;
  if (!auth) {
    throw Object.assign(new Error("Managed Codex credentials are not configured"), {
      code: "codex_managed_credentials_unconfigured",
    });
  }
  if (auth.mode !== options.authMode) {
    throw Object.assign(new Error("Codex credential mode does not match persisted auth mode"), {
      code: "codex_auth_mode_mismatch",
    });
  }
  return composeReviewedEngineFactories({
    additionalFactories: options.additionalFactories,
    codexTransport: options.transport,
    codexAuth: auth,
  });
}
