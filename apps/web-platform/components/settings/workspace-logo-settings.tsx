"use client";

import { useCallback, useRef, useState } from "react";
import { WorkspaceIdentityTile } from "@/components/dashboard/workspace-identity-tile";

// Workspace logo settings control (#4916), co-located with RenameWorkspaceAction
// on the Team settings page. Owner-only: a non-owner sees a disabled control
// with an owners-only tooltip (never a visible control that 403s on click —
// spec-flow P1-1). The route is the authoritative validator (sharp re-encode,
// square, format, size); these client checks are fast UX feedback only.
//
// Status is a 4-value union (idle｜uploading｜success｜error), not a boolean
// (cq-union-widening).

const ACCEPTED_TYPES = ["image/png", "image/webp"];
const MAX_BYTES = 1_048_576; // 1 MB
const OWNER_ONLY_COPY = "Only workspace owners can change the logo";

type Status = "idle" | "uploading" | "success" | "error";

function loadDimensions(file: File): Promise<{ w: number; h: number } | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(img.src);
      resolve({ w: img.width, h: img.height });
    };
    img.onerror = () => {
      URL.revokeObjectURL(img.src);
      resolve(null); // can't determine — let the server be authoritative
    };
    img.src = URL.createObjectURL(file);
  });
}

export function WorkspaceLogoSettings({
  workspaceId,
  workspaceName,
  isOwner,
  initialHasLogo,
}: {
  workspaceId: string;
  workspaceName: string;
  isOwner: boolean;
  initialHasLogo: boolean;
}) {
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState("");
  const [hasLogo, setHasLogo] = useState(initialHasLogo);
  const [preview, setPreview] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFile = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      e.target.value = ""; // allow re-selecting the same file
      if (!file) return;
      setError("");

      if (!ACCEPTED_TYPES.includes(file.type)) {
        setStatus("error");
        setError("SVG and JPG aren't accepted — upload a square PNG or WebP");
        return;
      }
      if (file.size > MAX_BYTES) {
        setStatus("error");
        setError("Logo must be under 1 MB");
        return;
      }
      const dim = await loadDimensions(file);
      if (dim && dim.w !== dim.h) {
        setStatus("error");
        setError("Logo must be a square image");
        return;
      }

      setStatus("uploading");
      try {
        const fd = new FormData();
        fd.append("file", file);
        const res = await fetch("/api/workspace/logo", { method: "POST", body: fd });
        if (!res.ok) {
          const body = (await res.json().catch(() => ({}))) as { error?: string };
          setStatus("error");
          setError(body.error ?? "Upload failed. Please try again.");
          return;
        }
        setPreview(URL.createObjectURL(file)); // optimistic — beats the 300s proxy cache
        setHasLogo(true);
        setStatus("success");
      } catch {
        setStatus("error");
        setError("Upload failed. Please try again.");
      }
    },
    [],
  );

  const handleRemove = useCallback(async () => {
    setStatus("uploading");
    setError("");
    try {
      const res = await fetch("/api/workspace/logo", { method: "DELETE" });
      if (!res.ok) {
        setStatus("error");
        setError("Couldn't remove the logo. Please try again.");
        return;
      }
      setPreview(null);
      setHasLogo(false);
      setStatus("idle");
    } catch {
      setStatus("error");
      setError("Couldn't remove the logo. Please try again.");
    }
  }, []);

  const avatar = preview ? (
    <span className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-md">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={preview} alt="" className="h-full w-full object-cover" />
    </span>
  ) : (
    <WorkspaceIdentityTile
      name={workspaceName}
      size="md"
      workspaceId={workspaceId}
      hasLogo={hasLogo}
    />
  );

  if (!isOwner) {
    return (
      <section
        data-testid="workspace-logo-settings"
        className="mb-6 rounded-lg border border-soleur-border-default px-6 py-4"
      >
        <div className="flex items-center gap-4">
          {avatar}
          <div className="min-w-0 flex-1">
            <h2 className="text-base font-semibold text-soleur-text-primary">Workspace logo</h2>
            <p className="mt-0.5 text-xs text-soleur-text-muted">{OWNER_ONLY_COPY}</p>
          </div>
          <button
            type="button"
            data-testid="workspace-logo-upload-btn"
            disabled
            aria-disabled="true"
            title={OWNER_ONLY_COPY}
            className="shrink-0 cursor-not-allowed rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-muted opacity-60"
          >
            Upload logo
          </button>
        </div>
      </section>
    );
  }

  return (
    <section
      data-testid="workspace-logo-settings"
      className="mb-6 rounded-lg border border-soleur-border-default px-6 py-4"
    >
      <div className="flex items-center gap-4">
        {avatar}
        <div className="min-w-0 flex-1">
          <h2 className="text-base font-semibold text-soleur-text-primary">Workspace logo</h2>
          <p className="mt-0.5 text-xs text-soleur-text-muted">
            Square PNG or WebP, up to 1 MB. Falls back to the initial monogram.
          </p>
          {status === "uploading" && (
            <p data-testid="workspace-logo-status-uploading" className="mt-1 text-xs text-soleur-text-secondary">
              Working…
            </p>
          )}
          {status === "success" && (
            <p data-testid="workspace-logo-status-success" className="mt-1 text-xs text-soleur-accent-gold-fg">
              Logo updated.
            </p>
          )}
          {status === "error" && (
            <p data-testid="workspace-logo-status-error" className="mt-1 text-xs text-red-400">
              {error}
            </p>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            data-testid="workspace-logo-upload-btn"
            onClick={() => fileInputRef.current?.click()}
            disabled={status === "uploading"}
            className="rounded-md border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-primary hover:bg-soleur-bg-surface-2 disabled:opacity-60"
          >
            {hasLogo ? "Replace" : "Upload logo"}
          </button>
          {hasLogo && (
            <button
              type="button"
              data-testid="workspace-logo-remove-btn"
              onClick={handleRemove}
              disabled={status === "uploading"}
              className="text-xs text-soleur-text-muted hover:text-soleur-text-secondary disabled:opacity-60"
            >
              Remove
            </button>
          )}
        </div>
      </div>
      <input
        ref={fileInputRef}
        data-testid="workspace-logo-file-input"
        type="file"
        accept="image/png,image/webp"
        className="hidden"
        onChange={handleFile}
      />
    </section>
  );
}
