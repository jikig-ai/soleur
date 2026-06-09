"use client";

import { useEffect, useState, type FormEvent, type ReactNode } from "react";

// web-platform has no public privacy page; the established convention links the
// marketing-site absolute URL (see app/(auth)/signup/page.tsx).
const PRIVACY_POLICY_URL = "https://soleur.ai/pages/legal/privacy-policy.html";

type Status = "idle" | "submitting" | "success" | "error";
type Panel = "expanded" | "collapsed";

// Eases its children in on mount: a freshly-mounted element starts slightly
// offset + transparent, then a one-frame flag flips it to its resting state so
// the named transform/opacity transition plays. Conditional-rendered panels
// mount a fresh Reveal on every collapse/expand, so the slide/fade plays each
// time. `motion-reduce:` makes the change instant under prefers-reduced-motion.
function Reveal({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  const [entered, setEntered] = useState(false);
  useEffect(() => {
    const id = requestAnimationFrame(() => setEntered(true));
    return () => cancelAnimationFrame(id);
  }, []);
  return (
    <div
      className={`${className} transition-[transform,opacity] duration-300 ease-out motion-reduce:transition-none motion-reduce:duration-0 ${
        entered ? "translate-y-0 opacity-100" : "translate-y-1 opacity-0"
      }`}
    >
      {children}
    </div>
  );
}

export function CtaBanner() {
  // In-memory only — closing collapses to a thin re-openable bar; a page
  // reload restores the full banner (the dismissal is never persisted).
  const [panel, setPanel] = useState<Panel>("expanded");
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<Status>("idle");

  function handleCollapse() {
    setPanel("collapsed");
  }

  function handleExpand() {
    setPanel("expanded");
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
      setStatus(res.ok ? "success" : "error");
    } catch {
      setStatus("error");
    }
  }

  const shellClass =
    "fixed bottom-0 left-0 right-0 z-40 border-t border-soleur-border-default bg-soleur-bg-surface-1/95 backdrop-blur-sm";

  // Collapsed — a slim full-width strip; clicking anywhere re-expands.
  if (panel === "collapsed") {
    return (
      <div className={`${shellClass} px-4 py-2`}>
        <Reveal className="mx-auto max-w-3xl">
          <button
            type="button"
            onClick={handleExpand}
            aria-label="Reopen Soleur signup banner"
            aria-expanded={false}
            data-testid="cta-banner-reopen"
            className="flex w-full items-center justify-between gap-4 rounded text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
          >
            <span className="text-sm">
              Built with{" "}
              <span className="font-medium text-soleur-accent-gold-fg">
                Soleur
              </span>
            </span>
            {/* Up-chevron (⌃) — reopen affordance. */}
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
              className="shrink-0"
            >
              <polyline points="18 15 12 9 6 15" />
            </svg>
          </button>
        </Reveal>
      </div>
    );
  }

  // Expanded — the full two-tier banner.
  return (
    <div className={`${shellClass} px-4 py-3`}>
      <Reveal className="mx-auto flex max-w-3xl flex-col gap-2">
        {/* Tier 1 — message + collapse */}
        <div className="flex items-start justify-between gap-4">
          <p className="text-sm text-soleur-text-secondary">
            Built with{" "}
            <span className="font-medium text-soleur-accent-gold-fg">Soleur</span>{" "}
            — AI agents for every department of your startup.
          </p>
          <button
            type="button"
            onClick={handleCollapse}
            aria-label="Collapse signup banner"
            aria-expanded={true}
            className="shrink-0 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
            data-testid="cta-banner-dismiss"
          >
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
            >
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        {/* Tier 2 — inline waitlist form, or success confirmation */}
        {status === "success" ? (
          <p role="status" className="text-sm font-medium text-soleur-text-secondary">
            <span className="text-soleur-accent-gold-fg">You&apos;re on the list ✓</span>{" "}
            — check your inbox to confirm.
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="flex flex-col gap-1.5">
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
      </Reveal>
    </div>
  );
}
