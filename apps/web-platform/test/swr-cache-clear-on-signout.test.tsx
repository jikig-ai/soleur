import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import useSWR, { SWRConfig, useSWRConfig } from "swr";
import { useSignOut } from "@/components/auth/use-sign-out";

// AC3 (FR4 / CPO C2 / GAP A/C — load-bearing): after sign-out, the in-memory SWR
// cache holds no key from the prior principal, and it is emptied BEFORE the
// navigation to /login. Under ADR-067's Router-Cache staleTimes amendment the
// navigation is now a HARD nav (`window.location.assign("/login")`, GAP C) — the
// only wipe of the App Router Router Cache — not a soft `router.push`. This test
// re-pins the clear-before-nav ordering proof to a stubbed `window.location.assign`.

const { signOutMock, removeAllChannelsMock, reportSilentFallbackMock } =
  vi.hoisted(() => ({
    signOutMock: vi.fn(
      (): Promise<{ error: Error | null }> => Promise.resolve({ error: null }),
    ),
    removeAllChannelsMock: vi.fn(() => Promise.resolve(["ok"])),
    reportSilentFallbackMock: vi.fn(),
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

// happy-dom's `window.location.assign` is not a vi-spyable method by default;
// replace `window.location` with a minimal stub carrying the spy. useSignOut
// only reads `.assign` (hard nav) and `.pathname` (GAP D sibling-tab guard).
const assignMock = vi.fn();
let originalLocation: Location;

// A component that (1) populates a user-A cache key on mount, and (2) renders
// the sign-out button. `cacheDataAtNav` records the live cached DATA values at
// the moment `window.location.assign` fires, proving the clear happened BEFORE
// navigation. (mutate(matcher, undefined) clears each entry's `.data`; the
// serialized key string itself may linger in the Map, so the invariant is "no
// surviving content", asserted against `.data`, not key presence.)
let cacheDataAtNav: unknown[] | null = null;

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
  assignMock.mockImplementation(() => {
    cacheDataAtNav = snapshotData(cache as Map<string, { data?: unknown }>);
  });
  return (
    <button onClick={() => void handleSignOut()}>Sign out</button>
  );
}

beforeEach(() => {
  cacheDataAtNav = null;
  assignMock.mockReset();
  signOutMock.mockReset();
  signOutMock.mockImplementation(() => Promise.resolve({ error: null }));
  removeAllChannelsMock.mockReset();
  removeAllChannelsMock.mockImplementation(() => Promise.resolve(["ok"]));
  reportSilentFallbackMock.mockClear();
  originalLocation = window.location;
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: { assign: assignMock, pathname: "/dashboard" } as unknown as Location,
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: originalLocation,
  });
  cleanup();
});

describe("SWR cache clear on sign-out", () => {
  it("empties the cache and does so before HARD-navigating to /login (GAP C)", async () => {
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

    // GAP C: navigation is a HARD nav, not a soft router.push.
    await waitFor(() => {
      expect(assignMock).toHaveBeenCalledWith("/login");
    });

    // The snapshot captured AT navigation time must already be free of user-A
    // content (cleared before nav), and the live cache holds no content either.
    expect(cacheDataAtNav).not.toBeNull();
    expect(JSON.stringify(cacheDataAtNav)).not.toContain("secret-A");
    expect(JSON.stringify(snapshotData(cacheMap))).not.toContain("secret-A");
  });

  it("still HARD-navigates to /login when signOut throws AND the local fallback fails (spec-flow P1-5)", async () => {
    // Server signOut throws, and the local-scope fallback also throws: the
    // teardown failed, but the user must still LEAVE the authenticated app — the
    // finally block clears SWR and hard-navigates to /login regardless, so the
    // user lands on the sign-in form (not a stuck /dashboard). The failure is
    // mirrored to Sentry via reportSilentFallback (the not-only-user-visible
    // signal). login-form.tsx does NOT loop authenticated users back to
    // /dashboard (middleware has no inverse auth redirect), so /login is terminal.
    signOutMock.mockImplementation(() => {
      throw new Error("network down");
    });
    removeAllChannelsMock.mockImplementation(() =>
      Promise.reject(new Error("channels down")),
    );

    const cacheMap = new Map<string, { data?: unknown }>();
    render(
      <SWRConfig value={{ provider: () => cacheMap, dedupingInterval: 0 }}>
        <Harness />
      </SWRConfig>,
    );
    await waitFor(() => {
      expect(JSON.stringify(snapshotData(cacheMap))).toContain("secret-A");
    });

    fireEvent.click(screen.getByRole("button", { name: /sign out/i }));

    // Despite the throw, the hard nav to /login still fires (lands on /login),
    // the cache is empty, and the failure was reported.
    await waitFor(() => {
      expect(assignMock).toHaveBeenCalledWith("/login");
    });
    expect(JSON.stringify(snapshotData(cacheMap))).not.toContain("secret-A");
    expect(reportSilentFallbackMock).toHaveBeenCalled();
  });
});
