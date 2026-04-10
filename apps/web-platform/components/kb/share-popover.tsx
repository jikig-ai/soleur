"use client";

import { useState, useRef, useEffect, useCallback } from "react";

interface SharePopoverProps {
  documentPath: string;
}

interface ShareState {
  status: "idle" | "loading" | "active";
  token: string | null;
  url: string | null;
  copied: boolean;
  confirmRevoke: boolean;
}

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

  // Check existing share status when popover opens.
  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    async function checkShare() {
      setState((s) => ({ ...s, status: "loading" }));
      try {
        const res = await fetch(`/api/kb/share?documentPath=${encodeURIComponent(documentPath)}`);
        if (!res.ok) {
          setState((s) => ({ ...s, status: "idle" }));
          return;
        }
        const data = await res.json();
        const existing = data.shares?.find(
          (s: { revoked: boolean }) => !s.revoked,
        );
        if (!cancelled && existing) {
          setState({
            status: "active",
            token: existing.token,
            url: `${window.location.origin}/shared/${existing.token}`,
            copied: false,
            confirmRevoke: false,
          });
        } else if (!cancelled) {
          setState({ status: "idle", token: null, url: null, copied: false, confirmRevoke: false });
        }
      } catch {
        if (!cancelled) setState((s) => ({ ...s, status: "idle" }));
      }
    }
    checkShare();
    return () => { cancelled = true; };
  }, [open, documentPath]);

  const generateLink = useCallback(async () => {
    setState((s) => ({ ...s, status: "loading" }));
    try {
      const res = await fetch("/api/kb/share", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ documentPath }),
      });
      if (!res.ok) {
        setState((s) => ({ ...s, status: "idle" }));
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
      setState((s) => ({ ...s, status: "idle" }));
    }
  }, [documentPath]);

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
        className="inline-flex items-center gap-1.5 rounded-lg border border-neutral-700 px-3 py-1.5 text-xs font-medium text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
          <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" strokeLinecap="round" strokeLinejoin="round" />
          <polyline points="16 6 12 2 8 6" strokeLinecap="round" strokeLinejoin="round" />
          <line x1="12" y1="2" x2="12" y2="15" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        Share
      </button>

      {open && (
        <div className="absolute right-0 top-full z-50 mt-2 w-80 rounded-lg border border-neutral-700 bg-neutral-900 p-4 shadow-xl">
          {state.status === "loading" && (
            <p className="text-sm text-neutral-400">Loading...</p>
          )}

          {state.status === "idle" && (
            <div>
              <p className="mb-3 text-sm text-neutral-300">
                Generate a public link to share this document with anyone.
              </p>
              <button
                type="button"
                onClick={generateLink}
                className="w-full rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black transition-colors hover:bg-amber-400"
              >
                Generate link
              </button>
            </div>
          )}

          {state.status === "active" && state.url && (
            <div>
              <p className="mb-2 text-xs text-neutral-400">Share link</p>
              <div className="mb-3 flex items-center gap-2">
                <input
                  type="text"
                  readOnly
                  value={state.url}
                  className="flex-1 truncate rounded border border-neutral-700 bg-neutral-800 px-2 py-1.5 text-xs text-neutral-200"
                />
                <button
                  type="button"
                  onClick={copyLink}
                  className="shrink-0 rounded border border-neutral-600 px-3 py-1.5 text-xs text-neutral-300 transition-colors hover:border-neutral-400 hover:text-white"
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
                      className="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-500"
                    >
                      Revoke
                    </button>
                    <button
                      type="button"
                      onClick={() => setState((s) => ({ ...s, confirmRevoke: false }))}
                      className="rounded border border-neutral-600 px-3 py-1 text-xs text-neutral-300 hover:border-neutral-400"
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
