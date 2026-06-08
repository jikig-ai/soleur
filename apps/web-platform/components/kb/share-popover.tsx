"use client";

import { useState, useRef, useEffect, useCallback } from "react";

interface SharePopoverProps {
  documentPath: string;
}

interface ShareState {
  status: "idle" | "loading" | "active" | "error";
  token: string | null;
  url: string | null;
  copied: boolean;
  confirmRevoke: boolean;
}

// Generic, hoisted error copy. Never echo raw server error strings, DB SQLSTATE
// codes, or filesystem paths to the user — keep this constant the only thing the
// error branch renders (AC2).
export const SHARE_ERROR_MESSAGE =
  "Couldn't generate a link. Please try again.";

export function SharePopover({ documentPath }: SharePopoverProps) {
  const [open, setOpen] = useState(false);
  const [state, setState] = useState<ShareState>({
    status: "idle",
    token: null,
    url: null,
    copied: false,
    confirmRevoke: false,
  });
  const popoverRef = useRef<HTMLDivElement>(null);

  // Close on outside click.
  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
        setOpen(false);
        setState((s) => ({ ...s, confirmRevoke: false }));
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  // Read existing share status. Returns true if an active share was found
  // (state set to "active"), false otherwise (state set to "idle"). Reusable
  // by both the open effect and the 409 concurrent-retry recovery path.
  // `isCurrent` guards against a stale in-flight response clobbering newer
  // state when the popover is closed/reopened or `documentPath` changes mid-
  // flight (the open effect passes its own liveness flag; the 409 recovery
  // caller owns its synchronous flow and uses the default always-current).
  const checkShare = useCallback(
    async (isCurrent: () => boolean = () => true): Promise<boolean> => {
      setState((s) => ({ ...s, status: "loading" }));
      try {
        const res = await fetch(`/api/kb/share?documentPath=${encodeURIComponent(documentPath)}`);
        if (!isCurrent()) return false;
        if (!res.ok) {
          setState((s) => ({ ...s, status: "idle" }));
          return false;
        }
        const data = await res.json();
        if (!isCurrent()) return false;
        const existing = data.shares?.find(
          (s: { revoked: boolean }) => !s.revoked,
        );
        if (existing) {
          setState({
            status: "active",
            token: existing.token,
            url: `${window.location.origin}/shared/${existing.token}`,
            copied: false,
            confirmRevoke: false,
          });
          return true;
        }
        setState({ status: "idle", token: null, url: null, copied: false, confirmRevoke: false });
        return false;
      } catch {
        if (isCurrent()) setState((s) => ({ ...s, status: "idle" }));
        return false;
      }
    },
    [documentPath],
  );

  // Check existing share status when the popover opens. The liveness flag is
  // flipped on cleanup so a response that resolves after close/reopen or a
  // documentPath switch cannot overwrite the newer state.
  useEffect(() => {
    if (!open) return;
    let active = true;
    void checkShare(() => active);
    return () => {
      active = false;
    };
  }, [open, checkShare]);

  const generateLink = useCallback(async () => {
    setState((s) => ({ ...s, status: "loading" }));
    try {
      const res = await fetch("/api/kb/share", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ documentPath }),
      });
      if (!res.ok) {
        // A 409 means a concurrent request already created the share — re-read
        // so the user lands on the active link instead of an error. Any other
        // failure (or a 409 with no recoverable row) surfaces the error state.
        if (res.status === 409) {
          const recovered = await checkShare();
          if (recovered) return;
        }
        setState((s) => ({ ...s, status: "error" }));
        return;
      }
      const data = await res.json();
      setState({
        status: "active",
        token: data.token,
        url: `${window.location.origin}/shared/${data.token}`,
        copied: false,
        confirmRevoke: false,
      });
    } catch {
      setState((s) => ({ ...s, status: "error" }));
    }
  }, [documentPath, checkShare]);

  const copyLink = useCallback(async () => {
    if (!state.url) return;
    try {
      await navigator.clipboard.writeText(state.url);
      setState((s) => ({ ...s, copied: true }));
      setTimeout(() => setState((s) => ({ ...s, copied: false })), 2000);
    } catch {
      // Fallback for browsers where clipboard API fails.
    }
  }, [state.url]);

  const revokeLink = useCallback(async () => {
    if (!state.token) return;
    try {
      const res = await fetch(`/api/kb/share/${state.token}`, {
        method: "DELETE",
      });
      if (res.ok) {
        setState({ status: "idle", token: null, url: null, copied: false, confirmRevoke: false });
      }
    } catch {
      // Silently fail — user can retry.
    }
  }, [state.token]);

  return (
    <div className="relative" ref={popoverRef}>
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-secondary transition-colors hover:border-soleur-border-emphasized hover:text-soleur-text-primary"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
          <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" strokeLinecap="round" strokeLinejoin="round" />
          <polyline points="16 6 12 2 8 6" strokeLinecap="round" strokeLinejoin="round" />
          <line x1="12" y1="2" x2="12" y2="15" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Share
      </button>

      {open && (
        <div className="absolute right-0 top-full z-50 mt-2 w-80 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4 shadow-xl">
          {state.status === "loading" && (
            <p className="text-sm text-soleur-text-secondary">Loading...</p>
          )}

          {state.status === "idle" && (
            <div>
              <p className="mb-3 text-sm text-soleur-text-secondary">
                Generate a public link to share this document with anyone.
              </p>
              <button
                type="button"
                onClick={generateLink}
                className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:bg-amber-400"
              >
                Generate link
              </button>
            </div>
          )}

          {state.status === "error" && (
            <div>
              <p className="mb-3 text-sm text-red-300">{SHARE_ERROR_MESSAGE}</p>
              <button
                type="button"
                onClick={generateLink}
                className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:bg-amber-400"
              >
                Try again
              </button>
            </div>
          )}

          {state.status === "active" && state.url && (
            <div>
              <p className="mb-2 text-xs text-soleur-text-secondary">Share link</p>
              <div className="mb-3 flex items-center gap-2">
                <input
                  type="text"
                  readOnly
                  value={state.url}
                  className="min-w-0 flex-1 truncate rounded border border-soleur-border-default bg-soleur-bg-surface-2 px-2 py-1.5 text-xs text-soleur-text-primary"
                />
                <button
                  type="button"
                  onClick={copyLink}
                  className="shrink-0 rounded border border-soleur-border-default px-3 py-1.5 text-xs text-soleur-text-secondary transition-colors hover:border-soleur-border-emphasized hover:text-soleur-text-primary"
                >
                  {state.copied ? "Copied!" : "Copy"}
                </button>
              </div>
              {!state.confirmRevoke ? (
                <button
                  type="button"
                  onClick={() => setState((s) => ({ ...s, confirmRevoke: true }))}
                  className="text-xs text-red-400 hover:text-red-300"
                >
                  Revoke access
                </button>
              ) : (
                <div className="rounded border border-red-800 bg-red-950/50 p-2">
                  <p className="mb-2 text-xs text-red-300">
                    Anyone with this link will lose access. This cannot be undone.
                  </p>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={revokeLink}
                      className="rounded bg-red-600 px-3 py-1 text-xs text-soleur-text-on-accent hover:bg-red-500"
                    >
                      Revoke
                    </button>
                    <button
                      type="button"
                      onClick={() => setState((s) => ({ ...s, confirmRevoke: false }))}
                      className="rounded border border-soleur-border-default px-3 py-1 text-xs text-soleur-text-secondary hover:border-soleur-border-emphasized"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
