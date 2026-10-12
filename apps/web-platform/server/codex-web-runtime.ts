import { composeReviewedEngineFactories } from "./agent-engine-adapter-composition";
import type { CodexAuthMode, CodexAuthProvider, CodexCodeAdapterTransport, CodexAuthBoundary } from "./codex-code-adapter";
import type { EngineAdapter, EngineEvent, EngineRunContext } from "./agent-engine-contract";
import type { EngineAdapterFactory } from "./agent-engine-adapter-factory";
import { createCodexApiKeyProviderForUser } from "./codex-credential-provider";
import type { CodexAppServerStdioLauncher } from "./codex-app-server-stdio";
import { createCodexWebTransport } from "./codex-web-transport";
import type { EngineObservability } from "./agent-engine-observability";

export interface CodexWebRuntimeOptions {
  userId: string;
  authMode: CodexAuthMode;
  transport?: CodexCodeAdapterTransport;
  launcher?: CodexAppServerStdioLauncher;
  nextRequestId?: () => string;
  cwd?: string;
  maxEventSize?: number;
  observability?: EngineObservability;
  /** Revalidate server-owned admission before each provider request, including auth retries. */
  authorizeRequest?: (context: EngineRunContext) => Promise<void>;
  /** Injected by the approved managed-account Web authorization flow. */
  managedProvider?: CodexAuthProvider;
  /** Test/runtime override for the encrypted Web-settings API-key provider. */
  apiKeyProvider?: CodexAuthProvider;
  additionalFactories?: Readonly<Record<string, EngineAdapterFactory>>;
  createCodex?: (transport: CodexCodeAdapterTransport, auth: CodexAuthBoundary) => EngineAdapter;
}

export interface CodexWebBinding {
  engineId: string;
  authMode: string;
}

function authorizeCodexTransport(
  transport: CodexCodeAdapterTransport,
  authorizeRequest: (context: EngineRunContext) => Promise<void>,
): CodexCodeAdapterTransport {
  async function* stream(context: EngineRunContext, load: () => AsyncIterable<EngineEvent>): AsyncIterable<EngineEvent> {
    await authorizeRequest(context);
    yield* load();
  }
  return {
    start: (context, input, lease) => stream(context, () => transport.start(context, input, lease)),
    continue: (context, session, input, lease) => stream(context, () => transport.continue(context, session, input, lease)),
    resumeFromCursor: (context, cursor, lease) => stream(context, () => transport.resumeFromCursor(context, cursor, lease)),
    reconcile: async (context, session, lease) => {
      await authorizeRequest(context);
      return transport.reconcile(context, session, lease);
    },
    respondToApproval: async (context, requestId, decision, lease) => {
      await authorizeRequest(context);
      return transport.respondToApproval(context, requestId, decision, lease);
    },
    // A stale generation must still be able to stop or erase its admitted native session.
    cancel: (context, session, lease) => transport.cancel(context, session, lease),
    erase: (context, session, lease) => transport.erase(context, session, lease),
    dispose: () => transport.dispose(),
  };
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
  const transport = options.transport ?? (options.launcher && options.nextRequestId
    ? createCodexWebTransport({
      launcher: options.launcher,
      nextRequestId: options.nextRequestId,
      cwd: options.cwd,
      maxEventSize: options.maxEventSize,
      observability: options.observability,
    })
    : null);
  if (!transport) {
    throw Object.assign(new Error("Codex transport is not configured"), {
      code: "codex_transport_unconfigured",
    });
  }
  return composeReviewedEngineFactories({
    additionalFactories: options.additionalFactories,
    codexTransport: options.authorizeRequest ? authorizeCodexTransport(transport, options.authorizeRequest) : transport,
    codexAuth: auth,
    createCodex: options.createCodex,
  });
}

/** Build the Codex runtime from persisted binding metadata without accepting a client-selected mode. */
export function createCodexWebEngineFactoriesForBinding(
  options: Omit<CodexWebRuntimeOptions, "authMode"> & { binding: CodexWebBinding },
): Partial<Record<string, EngineAdapterFactory>> {
  if (options.binding.engineId !== "codex") {
    throw Object.assign(new Error("persisted binding is not Codex"), { code: "codex_binding_mismatch" });
  }
  if (options.binding.authMode !== "api-key" && options.binding.authMode !== "managed") {
    throw Object.assign(new Error("persisted Codex auth mode is invalid"), { code: "codex_auth_mode_invalid" });
  }
  const authMode = options.binding.authMode;
  const { binding, ...runtime } = options;
  return createCodexWebEngineFactories({
    ...runtime,
    authMode,
  });
}
