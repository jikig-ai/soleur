// Server-side: compute a layouted LikeC4 model from raw `.c4` source.
// `likec4` bundles langium + a graphviz-wasm layouter and is registered in
// next.config.ts `serverExternalPackages`. Imported dynamically so routes that
// don't render a diagram never pay its load cost, and so this module stays
// unit-testable in the node test env. Only imported by server route handlers.

export type C4Diagnostic = {
  message: string;
  line: number;
  sourceFsPath: string;
};

export type C4ComputeResult = {
  /** Layouted model data (`LikeC4Model.$data`), JSON-serializable. Null on fatal parse error. */
  dump: Record<string, unknown> | null;
  /** Named view ids available for embedding (excludes the auto `index` overview is kept too). */
  viewIds: string[];
  /** Parse/validation diagnostics. Non-empty does not necessarily mean `dump` is null. */
  diagnostics: C4Diagnostic[];
};

/**
 * Parse + layout a combined LikeC4 source string into a serializable dump.
 * Never throws on invalid DSL — returns diagnostics so the UI can render them
 * inline. Throws only on unexpected internal failures.
 */
export async function computeC4Model(source: string): Promise<C4ComputeResult> {
  const { LikeC4 } = await import("likec4");

  const likec4 = await LikeC4.fromSource(source);
  const diagnostics: C4Diagnostic[] = likec4.getErrors().map((e) => ({
    message: e.message,
    line: e.line,
    sourceFsPath: e.sourceFsPath,
  }));

  if (likec4.hasErrors()) {
    return { dump: null, viewIds: [], diagnostics };
  }

  const model = await likec4.layoutedModel();
  const dump = model.$data as unknown as Record<string, unknown>;
  const viewIds = [...model.views()].map((v) => v.id);

  return { dump, viewIds, diagnostics };
}
