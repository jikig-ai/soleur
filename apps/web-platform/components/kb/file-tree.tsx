"use client";

import { useRef, useState, useCallback } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useKb } from "./kb-context";
import type { TreeNode } from "@/server/kb-reader";

const ALLOWED_ACCEPT = ".png,.jpg,.jpeg,.gif,.webp,.pdf,.csv,.txt,.docx";
const ALLOWED_EXTENSIONS = new Set([
  "png", "jpg", "jpeg", "gif", "webp", "pdf", "csv", "txt", "docx",
]);
const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20 MB

export function FileTree() {
  const { tree, expanded, toggleExpanded } = useKb();

  if (!tree?.children?.length) return null;

  return (
    <nav aria-label="Knowledge base file tree">
      <ul className="space-y-0.5">
        {tree.children.map((node) => (
          <TreeItem
            key={node.name}
            node={node}
            depth={0}
            parentPath=""
            expanded={expanded}
            onToggle={toggleExpanded}
          />
        ))}
      </ul>
    </nav>
  );
}

type UploadState =
  | { status: "idle" }
  | { status: "uploading" }
  | { status: "error"; message: string }
  | { status: "duplicate"; filename: string; sha: string; file: File; targetDir: string };

function TreeItem({
  node,
  depth,
  parentPath,
  expanded,
  onToggle,
}: {
  node: TreeNode;
  depth: number;
  parentPath: string;
  expanded: Set<string>;
  onToggle: (path: string) => void;
}) {
  const pathname = usePathname();
  const { refreshTree } = useKb();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadState, setUploadState] = useState<UploadState>({ status: "idle" });
  // Cap visual indent at 3 levels
  const indent = Math.min(depth, 3);
  const paddingLeft = `${indent * 12 + 8}px`;

  const uploadFile = useCallback(async (file: File, targetDir: string, sha?: string) => {
    setUploadState({ status: "uploading" });

    const formData = new FormData();
    formData.append("file", file);
    formData.append("targetDir", targetDir);
    if (sha) formData.append("sha", sha);

    try {
      const res = await fetch("/api/kb/upload", {
        method: "POST",
        body: formData,
      });

      if (res.status === 409) {
        const data = await res.json();
        setUploadState({
          status: "duplicate",
          filename: file.name,
          sha: data.sha,
          file,
          targetDir,
        });
        return;
      }

      if (!res.ok) {
        const data = await res.json().catch(() => ({ error: "Upload failed" }));
        setUploadState({ status: "error", message: data.error || "Upload failed" });
        return;
      }

      setUploadState({ status: "idle" });
      await refreshTree();
    } catch {
      setUploadState({ status: "error", message: "Network error. Please try again." });
    }
  }, [refreshTree]);

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Reset input so the same file can be re-selected
    e.target.value = "";

    // Client-side validation
    const ext = file.name.split(".").pop()?.toLowerCase();
    if (!ext || !ALLOWED_EXTENSIONS.has(ext)) {
      setUploadState({ status: "error", message: `Unsupported file type: .${ext || "unknown"}` });
      return;
    }

    if (file.size > MAX_FILE_SIZE) {
      setUploadState({ status: "error", message: "File exceeds 20MB limit" });
      return;
    }

    const dirKey = parentPath ? `${parentPath}/${node.name}` : node.name;
    uploadFile(file, dirKey);
  }, [parentPath, node.name, uploadFile]);

  if (node.type === "directory") {
    const dirKey = parentPath ? `${parentPath}/${node.name}` : node.name;
    const isExpanded = expanded.has(dirKey);
    const isUploading = uploadState.status === "uploading";

    return (
      <li>
        <div className="group relative">
          <button
            onClick={() => onToggle(dirKey)}
            className={`flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-neutral-300 hover:bg-neutral-800/50 ${
              isUploading ? "bg-amber-500/10" : ""
            }`}
            style={{ paddingLeft }}
            aria-expanded={isExpanded}
          >
            {isUploading ? (
              <UploadSpinner />
            ) : (
              <svg
                width="12"
                height="12"
                viewBox="0 0 12 12"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
                className={`shrink-0 transition-transform ${isExpanded ? "rotate-90" : ""}`}
              >
                <path d="M4.5 2.5 8 6 4.5 9.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            )}
            <FolderIcon />
            <span className="truncate font-medium">{node.name}</span>
            {node.modifiedAt && !isUploading && (
              <span className="ml-auto shrink-0 text-xs text-neutral-600">
                {formatRelativeTime(node.modifiedAt)}
              </span>
            )}
          </button>
          {!isUploading && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                fileInputRef.current?.click();
              }}
              className="absolute right-1 top-1/2 -translate-y-1/2 rounded p-1 text-neutral-500 opacity-0 transition-opacity hover:bg-neutral-700 hover:text-neutral-300 group-hover:opacity-100"
              title="Upload file"
              aria-label={`Upload file to ${node.name}`}
            >
              <UploadIcon />
            </button>
          )}
          <input
            ref={fileInputRef}
            type="file"
            accept={ALLOWED_ACCEPT}
            onChange={handleFileSelect}
            className="hidden"
            aria-hidden="true"
          />
        </div>
        {uploadState.status === "error" && (
          <div className="mx-2 mt-1 flex items-center gap-1.5 rounded bg-red-500/10 px-2 py-1 text-xs text-red-400" style={{ marginLeft: paddingLeft }}>
            <span className="flex-1">{uploadState.message}</span>
            <button onClick={() => setUploadState({ status: "idle" })} className="shrink-0 hover:text-red-300" aria-label="Dismiss error">&times;</button>
          </div>
        )}
        {uploadState.status === "duplicate" && (
          <div className="mx-2 mt-1 rounded bg-amber-500/10 px-2 py-1.5 text-xs text-amber-400" style={{ marginLeft: paddingLeft }}>
            <p className="mb-1.5">&ldquo;{uploadState.filename}&rdquo; already exists. Replace?</p>
            <div className="flex gap-2">
              <button
                onClick={() => {
                  const { file, targetDir, sha } = uploadState;
                  uploadFile(file, targetDir, sha);
                }}
                className="rounded bg-amber-500/20 px-2 py-0.5 text-amber-300 hover:bg-amber-500/30"
              >
                Replace
              </button>
              <button
                onClick={() => setUploadState({ status: "idle" })}
                className="rounded px-2 py-0.5 text-neutral-400 hover:text-neutral-300"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
        {isExpanded && node.children && (
          <ul className="space-y-0.5">
            {node.children.map((child) => (
              <TreeItem
                key={child.name}
                node={child}
                depth={depth + 1}
                parentPath={dirKey}
                expanded={expanded}
                onToggle={onToggle}
              />
            ))}
          </ul>
        )}
      </li>
    );
  }

  // File node
  const filePath = `/dashboard/kb/${node.path}`;
  const isActive = pathname === filePath;

  return (
    <li>
      <Link
        href={filePath}
        className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors ${
          isActive
            ? "bg-neutral-800 text-amber-400"
            : "text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200"
        }`}
        style={{ paddingLeft }}
      >
        <FileTypeIcon extension={node.extension} />
        <span className="truncate">{node.name}</span>
        {node.modifiedAt && (
          <span className="ml-auto shrink-0 text-xs text-neutral-600">
            {formatRelativeTime(node.modifiedAt)}
          </span>
        )}
      </Link>
    </li>
  );
}

function formatRelativeTime(iso: string): string {
  const now = Date.now();
  const then = new Date(iso).getTime();
  const diffMs = now - then;
  const diffSec = Math.floor(diffMs / 1_000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);
  const diffWeek = Math.floor(diffDay / 7);

  if (diffSec < 60) return "just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  if (diffDay < 7) return `${diffDay}d ago`;
  if (diffWeek < 52) return `${diffWeek}w ago`;
  return `${Math.floor(diffDay / 365)}y ago`;
}

function FolderIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-amber-500/70">
      <path d="M2 7.5V19a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 4H4a2 2 0 0 0-2 2Z" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function FileTypeIcon({ extension }: { extension?: string }) {
  const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp"]);

  if (extension && IMAGE_EXTENSIONS.has(extension)) {
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-emerald-500/70">
        <rect width="18" height="18" x="3" y="3" rx="2" ry="2" strokeLinecap="round" strokeLinejoin="round" />
        <circle cx="9" cy="9" r="2" strokeLinecap="round" strokeLinejoin="round" />
        <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }

  if (extension === ".pdf") {
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-red-400/70">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M10 13h4" strokeLinecap="round" />
        <path d="M10 17h4" strokeLinecap="round" />
      </svg>
    );
  }

  if (extension === ".csv" || extension === ".txt") {
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-blue-400/70">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M16 13H8" strokeLinecap="round" />
        <path d="M16 17H8" strokeLinecap="round" />
        <path d="M10 9H8" strokeLinecap="round" />
      </svg>
    );
  }

  if (extension === ".docx") {
    return (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-indigo-400/70">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }

  // Default file icon (including .md)
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-neutral-500">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function UploadIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" strokeLinecap="round" strokeLinejoin="round" />
      <polyline points="17 8 12 3 7 8" strokeLinecap="round" strokeLinejoin="round" />
      <line x1="12" y1="3" x2="12" y2="15" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function UploadSpinner() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" className="shrink-0 animate-spin text-amber-400">
      <circle cx="6" cy="6" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.5" opacity="0.3" />
      <path d="M6 1.5a4.5 4.5 0 0 1 4.5 4.5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}
