import { SWRConfig } from "swr";

/**
 * Wraps a component subtree in an SWRConfig with a FRESH, test-local cache
 * Map. SWR's default cache is a module singleton — without an explicit
 * provider, cache entries leak between test cases (and between files) in the
 * shared happy-dom worker, producing order-dependent flakes. `provider: () =>
 * new Map()` gives each render its own isolated cache.
 *
 * `dedupingInterval: 0` and `provider` aside, the production defaults
 * (`revalidateOnReconnect: false`) are mirrored so tests exercise the same
 * config the app ships. Pass `value` to override per-test (e.g. force
 * `revalidateOnFocus: false`).
 */
export function SwrTestProvider({
  children,
  value,
}: {
  children: React.ReactNode;
  value?: Record<string, unknown>;
}) {
  return (
    <SWRConfig
      value={{
        provider: () => new Map(),
        dedupingInterval: 0,
        revalidateOnReconnect: false,
        ...value,
      }}
    >
      {children}
    </SWRConfig>
  );
}
