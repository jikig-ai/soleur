import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import useSWR, { SWRConfig, useSWRConfig } from "swr";
import { useSignOut } from "@/components/auth/use-sign-out";

// AC3 (FR4 / CPO C2 / GAP A — load-bearing): after sign-out, the in-memory SWR
// cache holds no key from the prior principal, and it is emptied BEFORE the
// /login navigation (a soft router.push would otherwise let the
// module-singleton cache survive into the next principal's first paint).

const { pushMock, signOutMock, removeAllChannelsMock, reportSilentFallbackMock } =
  vi.hoisted(() => ({
    pushMock: vi.fn(),
    signOutMock: vi.fn(
      (): Promise<{ error: Error | null }> => Promise.resolve({ error: null }),
    ),
    removeAllChannelsMock: vi.fn(() => Promise.resolve(["ok"])),
    reportSilentFallbackMock: vi.fn(),
  }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: vi.fn() }),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signOut: signOutMock,
      onAuthStateChange: () => ({
        data: { subscription: { unsubscribe: vi.fn() } },
      }),
    },
    removeAllChannels: removeAllChannelsMock,
  }),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

// A component that (1) populates a user-A cache key on mount, and (2) renders
// the sign-out button. `cacheDataAtPush` records the live cached DATA values at
// the moment router.push fires, proving the clear happened BEFORE navigation.
// (mutate(matcher, undefined) clears each entry's `.data`; the serialized key
// string itself may linger in the Map, so the invariant is "no surviving
// content", asserted against `.data`, not key presence.)
let cacheDataAtPush: unknown[] | null = null;

function snapshotData(cache: Map<string, { data?: unknown }>): unknown[] {
  return [...cache.values()].map((v) => v?.data).filter((d) => d !== undefined);
}

function Harness() {
  const { cache } = useSWRConfig();
  const { handleSignOut } = useSignOut();
  // Seed a user-A key.
  useSWR(["/api/inbox/emails", "user-A-active"], () =>
    Promise.resolve([{ id: "secret-A" }]),
  );
  pushMock.mockImplementation(() => {
    cacheDataAtPush = snapshotData(cache as Map<string, { data?: unknown }>);
  });
  return (
    <button onClick={() => void handleSignOut()}>Sign out</button>
  );
}

beforeEach(() => {
  cacheDataAtPush = null;
  pushMock.mockReset();
  signOutMock.mockReset();
  signOutMock.mockImplementation(() => Promise.resolve({ error: null }));
  removeAllChannelsMock.mockReset();
  removeAllChannelsMock.mockImplementation(() => Promise.resolve(["ok"]));
  reportSilentFallbackMock.mockClear();
});

afterEach(() => cleanup());

describe("SWR cache clear on sign-out", () => {
  it("empties the cache and does so before navigating to /login", async () => {
    const cacheMap = new Map<string, { data?: unknown }>();
    render(
      <SWRConfig value={{ provider: () => cacheMap, dedupingInterval: 0 }}>
        <Harness />
      </SWRConfig>,
    );

    // The user-A content is cached before sign-out.
    await waitFor(() => {
      expect(JSON.stringify(snapshotData(cacheMap))).toContain("secret-A");
    });

    fireEvent.click(screen.getByRole("button", { name: /sign out/i }));

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/login");
    });

    // The snapshot captured AT push time must already be free of user-A content
    // (cleared before navigation), and the live cache holds no content either.
    expect(cacheDataAtPush).not.toBeNull();
    expect(JSON.stringify(cacheDataAtPush)).not.toContain("secret-A");
    expect(JSON.stringify(snapshotData(cacheMap))).not.toContain("secret-A");
  });
});
