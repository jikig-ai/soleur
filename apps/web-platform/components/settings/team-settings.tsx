"use client";

import { useState, useRef, useCallback } from "react";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { useTeamNames } from "@/hooks/use-team-names";
import { validateCustomName } from "@/server/team-names-validation";
import { LeaderAvatar } from "@/components/leader-avatar";
import type { DomainLeaderId } from "@/server/domain-leaders";

const MAX_ICON_SIZE = 100 * 1024; // 100KB
const MAX_ICON_DIMENSION = 256;
const ACCEPTED_ICON_TYPES = ["image/png", "image/webp"];

export function TeamSettingsContent() {
  const { names, updateName, updateIcon, getIconPath, loading } = useTeamNames();

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <span className="text-sm text-soleur-text-secondary">Loading team...</span>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wider text-soleur-accent-gold-fg">
        Your Team
      </div>
      <h1 className="mb-2 text-2xl font-semibold text-soleur-text-primary">Domain Leaders</h1>
      <p className="mb-8 text-sm text-soleur-text-secondary">
        Give your leaders custom names and icons. Names display as &quot;Name (Role)&quot; across conversations and mentions.
      </p>

      <div className="space-y-1">
        {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
          <LeaderRow
            key={leader.id}
            leaderId={leader.id as DomainLeaderId}
            title={leader.title}
            name={leader.name}
            customName={names[leader.id] ?? ""}
            customIconPath={getIconPath(leader.id as DomainLeaderId)}
            onNameChange={updateName}
            onIconChange={updateIcon}
          />
        ))}
      </div>

      <p className="mt-6 text-xs text-soleur-text-muted">Changes save automatically</p>
    </div>
  );
}

function LeaderRow({
  leaderId,
  title,
  name,
  customName,
  customIconPath,
  onNameChange,
  onIconChange,
}: {
  leaderId: DomainLeaderId;
  title: string;
  name: string;
  customName: string;
  customIconPath: string | null;
  onNameChange: (leaderId: string, name: string) => Promise<void>;
  onIconChange: (leaderId: string, path: string | null) => Promise<void>;
}) {
  const [value, setValue] = useState(customName);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      setValue(newValue);
      setError("");

      if (debounceRef.current) clearTimeout(debounceRef.current);

      debounceRef.current = setTimeout(() => {
        const trimmed = newValue.trim();
        if (trimmed !== "") {
          const result = validateCustomName(trimmed);
          if (!result.valid) {
            setError(result.error);
            return;
          }
        }
        onNameChange(leaderId, newValue);
      }, 500);
    },
    [leaderId, onNameChange],
  );

  const handleAvatarClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileSelect = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;

      // Reset input so same file can be re-selected
      e.target.value = "";

      // Client-side validation
      if (!ACCEPTED_ICON_TYPES.includes(file.type)) {
        setError("Only PNG and WebP images are accepted");
        return;
      }
      if (file.size > MAX_ICON_SIZE) {
        setError("Icon must be under 100KB");
        return;
      }

      // Dimension check (skip for SVG)
      if (file.type !== "image/svg+xml") {
        const valid = await checkDimensions(file);
        if (!valid) {
          setError("Icon must be 256x256 pixels or smaller");
          return;
        }
      }

      setError("");
      setUploading(true);

      try {
        const ext = file.name.split(".").pop() ?? "png";
        const iconFilename = `${leaderId}.${ext}`;
        const targetDir = "settings/team-icons";
        // Create a new File with the desired filename (upload API uses file.name)
        const renamedFile = new File([file], iconFilename, { type: file.type });
        const formData = new FormData();
        formData.append("file", renamedFile);
        formData.append("targetDir", targetDir);

        const res = await fetch("/api/kb/upload", {
          method: "POST",
          body: formData,
        });

        if (!res.ok) {
          throw new Error(`Upload failed: ${res.status}`);
        }

        await onIconChange(leaderId, `${targetDir}/${iconFilename}`);
      } catch (err) {
        console.error("[team-settings] icon upload error:", err);
        setError("Upload failed. Please try again.");
      } finally {
        setUploading(false);
      }
    },
    [leaderId, onIconChange],
  );

  const handleReset = useCallback(async () => {
    await onIconChange(leaderId, null);
  }, [leaderId, onIconChange]);

  return (
    <div className="flex items-center gap-4 rounded-lg px-2 py-3">
      <button
        type="button"
        onClick={handleAvatarClick}
        className="relative shrink-0 cursor-pointer rounded-lg focus:outline-none focus:ring-2 focus:ring-soleur-border-emphasized"
        aria-label={`${name} avatar — click to upload custom icon`}
      >
        <LeaderAvatar leaderId={leaderId} size="lg" customIconPath={customIconPath} />
        {uploading && (
          <span className="absolute inset-0 flex items-center justify-center rounded-lg bg-black/50">
            <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
          </span>
        )}
      </button>
      <input
        ref={fileInputRef}
        type="file"
        accept="image/png,image/webp"
        className="hidden"
        onChange={handleFileSelect}
      />
      {customIconPath && (
        <button
          type="button"
          onClick={handleReset}
          className="shrink-0 text-xs text-soleur-text-muted hover:text-soleur-text-secondary"
          aria-label={`Reset ${name} icon to default`}
        >
          Reset
        </button>
      )}
      <span className="min-w-0 flex-1 text-sm text-soleur-text-secondary">{title}</span>
      <div className="w-48">
        <input
          type="text"
          value={value}
          onChange={handleChange}
          placeholder="Enter a name..."
          maxLength={30}
          className={`w-full rounded-lg border bg-soleur-bg-surface-2/50 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted outline-none transition-colors focus:border-soleur-border-emphasized ${
            error ? "border-red-500" : "border-soleur-border-default"
          }`}
        />
        {error && <p className="mt-1 text-xs text-red-400">{error}</p>}
      </div>
    </div>
  );
}

function checkDimensions(file: File): Promise<boolean> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(img.src);
      resolve(img.width <= MAX_ICON_DIMENSION && img.height <= MAX_ICON_DIMENSION);
    };
    img.onerror = () => {
      URL.revokeObjectURL(img.src);
      resolve(false);
    };
    img.src = URL.createObjectURL(file);
  });
}
