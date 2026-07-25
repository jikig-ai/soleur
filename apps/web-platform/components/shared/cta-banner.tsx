"use client";

import { useState, type FormEvent } from "react";

// web-platform has no public privacy page; the established convention links the
// marketing-site absolute URL (see app/(auth)/signup/page.tsx).
const PRIVACY_POLICY_URL = "https://soleur.ai/pages/legal/privacy-policy.html";

// Per-browser durable marker that THIS browser already joined the waitlist. Set
// only after a confirmed Join (see handleSubmit's res.ok branch); read once at
// mount to suppress the banner entirely for a returning visitor. A boolean "1"
// only — the entered email is NEVER persisted (shared docs open on shared
// machines). Distinct from the in-memory `soleur:shared:cta-dismissed`
// sessionStorage key (a mere collapse is deliberately NOT remembered).
const JOINED_KEY = "soleur:shared:waitlist-joined";

// No `typeof window` guard: CtaBanner is mounted as `{data && <CtaBanner />}` on
// the `"use client"` shared-doc page (app/shared/[token]/page.tsx) after a
// client-side fetch, so it is never in server-rendered HTML and a lazy useState
// initializer cannot hydration-mismatch. A read throw (private mode / disabled
// storage) falls back to `false` → banner SHOWS — the safe direction; a thrown
// read must never suppress the CTA. NB: if this banner ever moves to a
// server-rendered surface, restore an SSR/mount guard.
function readJoinedFlag(): boolean {
  try {
    return localStorage.getItem(JOINED_KEY) === "1";
  } catch {
    return false;
  }
}

// Named (not inlined) so the load-bearing "write only on confirmed success"
// invariant is a single grep-able call site. A swallowed write (private mode /
// quota) just keeps today's in-memory behaviour.
function writeJoinedFlag(): void {
  try {
    localStorage.setItem(JOINED_KEY, "1");
  } catch {
    /* private mode / quota — keep in-memory behaviour */
  }
}

type Status = "idle" | "submitting" | "success" | "error";
type Panel = "expanded" | "collapsed";

export function CtaBanner() {
  // In-memory only — closing collapses the body to a thin header bar; a page
  // reload restores the full banner (the dismissal is never persisted).
  const [panel, setPanel] = useState<Panel>("expanded");
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  // Read once at mount (lazy initializer, not useEffect). All hooks above run
  // unconditionally; the early-return below is stable per mount, so it does not
  // violate rules-of-hooks.
  const [joined] = useState(() => readJoinedFlag());

  // A returning visitor who already joined on this browser sees no banner at all
  // (wireframe State C). Suppress entirely rather than collapse to the thin bar.
  if (joined) return null;

  const expanded = panel === "expanded";

  function toggle() {
    setPanel((p) => (p === "expanded" ? "collapsed" : "expanded"));
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (status === "submitting") return;
    const honeypot =
      (e.currentTarget.elements.namedItem("url") as HTMLInputElement | null)
        ?.value ?? "";
    setStatus("submitting");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, url: honeypot }),
      });
      // Any non-2xx (rate-limited, upstream 502, bad request) and any fetch
      // rejection (offline / DNS / abort) land in `error` with the form
      // re-enabled — never a permanent disabled `submitting` freeze.
      if (res.ok) {
        // Confirmed 2xx (new join OR Buttondown already-subscribed, both
        // {ok:true}) — remember it so the banner doesn't return on next mount.
        // LOAD-BEARING: the write lives ONLY in this branch. Writing on a failed
        // signup would silently suppress the CTA and lose a real lead.
        writeJoinedFlag();
        setStatus("success");
      } else {
        setStatus("error");
      }
    } catch {
      setStatus("error");
    }
  }

  return (
    <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-soleur-border-default bg-soleur-bg-surface-1/95 px-4 py-3 safe-bottom backdrop-blur-sm">
      <div className="mx-auto flex max-w-3xl flex-col gap-2">
        {/* Persistent header row — message + the single rotating-arrow toggle. */}
        <div className="flex items-start justify-between gap-4">
          <p className="text-sm text-soleur-text-secondary">
            Built with{" "}
            <span className="font-medium text-soleur-accent-gold-fg">Soleur</span>{" "}
            — AI agents for every department of your startup.
          </p>
          <button
            type="button"
            onClick={toggle}
            aria-expanded={expanded}
            aria-label={expanded ? "Collapse signup banner" : "Reopen Soleur signup banner"}
            className="shrink-0 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
            data-testid="cta-banner-toggle"
          >
            {/* One chevron, rotated 180° between states — the arrow points toward
                the action. COLLAPSED = rotate-0 (chevron points UP = "expand");
                EXPANDED = rotate-180 (points DOWN = "collapse"). */}
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
              className={`transition-transform duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0 ${
                expanded ? "rotate-180" : "rotate-0"
              }`}
            >
              <polyline points="18 15 12 9 6 15" />
            </svg>
          </button>
        </div>

        {/* Collapsible body — grid-template-rows 0fr↔1fr animates height in BOTH
            directions. When collapsed it is inert + aria-hidden so the form is
            out of the tab order and silent to assistive tech. */}
        <div
          data-testid="cta-banner-body"
          inert={!expanded || undefined}
          aria-hidden={!expanded || undefined}
          className={`grid transition-[grid-template-rows] duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0 ${
            expanded ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
          }`}
        >
          <div className="overflow-hidden">
            {/* Inline waitlist form, or success confirmation. */}
            {status === "success" ? (
              <p role="status" className="text-sm font-medium text-soleur-text-secondary">
                <span className="text-soleur-accent-gold-fg">You&apos;re on the list ✓</span>{" "}
                — check your inbox to confirm.
              </p>
            ) : (
              /* pt-0.5 keeps the first row's focus ring off the overflow-hidden
                 clip boundary during the grid-rows collapse transition. */
              <form
                onSubmit={handleSubmit}
                className="flex flex-col gap-1.5 pt-0.5"
              >
                <label
                  htmlFor="waitlist-email"
                  className="text-sm font-medium text-soleur-text-primary"
                >
                  Join the waitlist for early access.
                </label>
                <div className="flex flex-col gap-2 sm:flex-row">
                  <input
                    id="waitlist-email"
                    name="email"
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="you@company.com"
                    autoComplete="email"
                    inputMode="email"
                    disabled={status === "submitting"}
                    className="w-full rounded-lg border border-soleur-border-default bg-transparent px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted sm:flex-1"
                  />
                  {/* Honeypot — a real browser never fills this. autoComplete=off +
                      tabIndex=-1 keeps password-manager/email autofill out of it. */}
                  <input
                    type="text"
                    name="url"
                    tabIndex={-1}
                    autoComplete="off"
                    aria-hidden="true"
                    className="hidden"
                  />
                  <button
                    type="submit"
                    disabled={status === "submitting"}
                    className="shrink-0 rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:bg-amber-400 disabled:opacity-60 sm:w-auto"
                  >
                    {status === "submitting" ? "Joining…" : "Join"}
                  </button>
                </div>
                <p className="text-xs text-soleur-text-muted">
                  No spam. We email you once when early access opens.{" "}
                  <a
                    href={PRIVACY_POLICY_URL}
                    className="text-soleur-accent-gold-fg underline"
                  >
                    Privacy Policy
                  </a>
                </p>
                {/* Persistent aria-live region (empty in idle) so assistive tech
                    announces the error text when it is swapped in. */}
                <p
                  role="status"
                  aria-live="polite"
                  className="min-h-[1rem] text-xs text-soleur-accent-gold-fg"
                >
                  {status === "error" ? "Something went wrong. Please try again." : ""}
                </p>
              </form>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
