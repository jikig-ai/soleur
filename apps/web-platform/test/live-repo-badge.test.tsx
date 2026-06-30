import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
import { __resetActiveRepoCoalesceForTests } from "@/hooks/use-active-repo";

// LiveRepoBadge is now INTERSTITIAL-ONLY: the "Working on: owner/repo" string
// moved into the workspace pill subtitle (org-switcher.tsx, fed by the shared
// useActiveRepo hook). This component renders the J5 revocation alert when the
// API reports fellBackToSolo, else nothing.

function mockActiveRepo(payload: Record<string, unknown>) {
  return vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve(payload),
  });
}

describe("LiveRepoBadge — J5 revocation interstitial", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    __resetActiveRepoCoalesceForTests();
  });

  it("renders NOTHING on the happy path (repo name now lives in the pill, not here)", async () => {
    // Flag when the poll's body settles so the absence assertions below run
    // AFTER the state commit — a bare wait-on-absence passes on the first
    // tick (pre-poll) and proves nothing. (The re-arm test below anchors on the
    // stronger fetch-call-count signal because it has no positive DOM observable
    // for its regain state; here the terminal empty-DOM assertion suffices.)
    let pollCommitted = false;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: "https://github.com/bob/team",
            repoName: "bob/team",
            repoStatus: "ready",
            fellBackToSolo: false,
          }).finally(() => {
            pollCommitted = true;
          }),
      }),
    );
    const { container } = render(<LiveRepoBadge />);
    // let the poll resolve, then assert no repo badge + no interstitial
    await vi.waitFor(() => expect(pollCommitted).toBe(true), {
      // #5113 — tolerate CPU starvation of the forked worker under
      // full-suite load (vi.waitFor default is 1000ms; see #4128).
      timeout: 10_000,
    });
    expect(screen.queryByTestId("revocation-interstitial")).toBeNull();
    expect(screen.queryByTestId("live-repo-badge")).toBeNull();
    expect(container).toBeEmptyDOMElement();
  });

  it("J5: renders the revocation interstitial when the API reports fellBackToSolo", async () => {
    vi.stubGlobal(
      "fetch",
      mockActiveRepo({
        workspaceId: "solo-1",
        repoUrl: "https://github.com/alice/solo",
        repoName: "alice/solo",
        repoStatus: "ready",
        fellBackToSolo: true,
      }),
    );
    render(<LiveRepoBadge />);
    const interstitial = await screen.findByTestId("revocation-interstitial");
    expect(interstitial).toHaveTextContent(/no longer have access/i);
    expect(interstitial).toHaveTextContent(/personal workspace/i);
    // the component no longer surfaces the repo name — that's the pill's job now
    expect(screen.queryByTestId("live-repo-badge")).toBeNull();
  });

  it("re-arms the interstitial on a fresh fellBackToSolo transition after dismissal (J5 safety)", async () => {
    const solo = {
      workspaceId: "solo-1",
      repoUrl: "https://github.com/alice/solo",
      repoName: "alice/solo",
      repoStatus: "ready",
      fellBackToSolo: true,
    };
    const team = {
      workspaceId: "team-1",
      repoUrl: "https://github.com/team/repo",
      repoName: "team/repo",
      repoStatus: "ready",
      fellBackToSolo: false,
    };
    // #5796 — the active-repo poll fires on mount AND on every window focus
    // (use-active-repo.ts), so a consume-once `mockResolvedValueOnce` queue is
    // order-fragile: a stray focus/poll during the dismiss-wait would consume
    // the next queued response out of band, and the boolean-dep false→true
    // re-arm effect would re-surface the interstitial — the intermittent
    // vi.waitFor.timeout flake this issue tracks. Drive every fetch off a
    // mutable `current` instead: the value is read at `.json()` time, so stray
    // and in-flight polls are idempotent (they return the current phase's
    // state), and no spurious transition can occur. The test advances `current`
    // explicitly at each phase boundary.
    let current = solo; // mount: revoked
    const fetchMock = vi.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve(current) }),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(<LiveRepoBadge />);
    await screen.findByTestId("revocation-interstitial");

    // user dismisses the notice — dismissal is an async state commit
    // (setDismissed(true) → re-render → return null), so poll until the node
    // is gone rather than asserting on an arbitrary tick (vacuous-absence-wait
    // class, #5234/#5113).
    fireEvent.click(screen.getByRole("button", { name: /dismiss notice/i }));
    await vi.waitFor(
      () => expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
      { timeout: 10_000 }, // #5113 — tolerate forked-worker CPU starvation
    );

    // regained access (fellBackToSolo:false) — stays hidden, no re-arm. Advance
    // the phase to `team` and force a fresh focus poll. Reset the coalescing
    // latch first: in production distinct focus events are seconds apart so the
    // in-flight latch is always clear; here they fire back-to-back.
    const callsBeforeRegain = fetchMock.mock.calls.length;
    current = team;
    __resetActiveRepoCoalesceForTests();
    fireEvent.focus(window);
    // Gate on the fetch-mock call count ADVANCING past the pre-focus baseline (a
    // delta, not an absolute ==2: stray mount/focus polls are now harmless but
    // would break an absolute count). The dispatched poll is strictly downstream
    // of the focus, so an advance proves the regain `poll()` ran.
    await vi.waitFor(
      () =>
        expect(fetchMock.mock.calls.length).toBeGreaterThan(callsBeforeRegain),
      { timeout: 10_000 }, // #5113 — tolerate forked-worker CPU starvation
    );
    // Drain the setData(team) commit + the boolean-dep fellBackToSolo:false
    // effect so the `false` value observably renders before the re-revoke.
    // `act` flushes microtasks AND React's effect queue in one deterministic
    // drain — no wall-clock dependency (rejected: setTimeout / vi.advanceTimers*,
    // which would re-arm the flake and pump the hook's real cloning-poll).
    await act(async () => {});
    // Regain provably rendered the `false` state (interstitial absent) before
    // the re-revoke — supplies the transition-through-`false` evidence that
    // distinguishes a genuine re-arm from "never left" (mount-`solo` and
    // re-revoke-`solo` are otherwise identical).
    expect(screen.queryByTestId("revocation-interstitial")).toBeNull();

    // a FRESH revocation (false→true transition) must re-surface the alert.
    // Reset the latch AFTER the act flush (never before): resetting `inFlight`
    // while the prior poll's setData(team) continuation is still pending would
    // let two setData continuations run concurrently with no ordering guarantee
    // (the coalesce-reset/continuation interleave hazard, #5297).
    const callsBeforeRevoke = fetchMock.mock.calls.length;
    current = solo;
    __resetActiveRepoCoalesceForTests();
    fireEvent.focus(window);
    await vi.waitFor(
      () =>
        expect(
          screen.getByTestId("revocation-interstitial"),
        ).toBeInTheDocument(),
      { timeout: 10_000 }, // #5113 — see first vi.waitFor in this file
    );
    // The re-surfaced interstitial was driven by a re-revoke poll AFTER the
    // regain committed (a fresh false→true transition), not a lingering
    // mount-state render — proven by the dismiss→null→reappear sequence plus a
    // poll dispatched past the regain baseline.
    expect(fetchMock.mock.calls.length).toBeGreaterThan(callsBeforeRevoke);
  });

  it("dismissing the interstitial hides it", async () => {
    vi.stubGlobal(
      "fetch",
      mockActiveRepo({
        workspaceId: "solo-1",
        repoUrl: "https://github.com/alice/solo",
        repoName: "alice/solo",
        repoStatus: "ready",
        fellBackToSolo: true,
      }),
    );
    render(<LiveRepoBadge />);
    // prove the interstitial was present before dismissal, then poll until the
    // async dismissal commit removes it — a bare synchronous check races the
    // re-render under load (vacuous-absence-wait class, #5234/#5113).
    await screen.findByTestId("revocation-interstitial");
    fireEvent.click(
      screen.getByRole("button", { name: /dismiss notice/i }),
    );
    await vi.waitFor(
      () => expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
      { timeout: 10_000 }, // #5113 — tolerate forked-worker CPU starvation
    );
  });

  it("renders nothing until the first poll resolves (no flash for solo users)", () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
    const { container } = render(<LiveRepoBadge />);
    expect(container).toBeEmptyDOMElement();
  });
});
