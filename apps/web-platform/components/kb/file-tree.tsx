"use client";

import { useRef, useState, useCallback, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useKb } from "./kb-context";
import { UploadProgress } from "./upload-progress";
import type { TreeNode } from "@/server/kb-reader";
import { classifyByExtension } from "@/lib/kb-file-kind";

const ALLOWED_ACCEPT = ".png,.jpg,.jpeg,.gif,.webp,.pdf,.csv,.txt,.docx";
const ALLOWED_EXTENSIONS = new Set([
  "png", "jpg", "jpeg", "gif", "webp", "pdf", "csv", "txt", "docx",
]);
const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20 MB

function xhrUpload(
  url: string,
  formData: FormData,
  onProgress: (percent: number) => void,
): Promise<{ status: number; body: unknown }> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      } else {
        // Signal indeterminate mode
        onProgress(-1);
      }
    };

    xhr.onload = () => {
      try {
        const body = JSON.parse(xhr.responseText);
        resolve({ status: xhr.status, body });
      } catch {
        resolve({ status: xhr.status, body: { error: "Invalid response" } });
      }
    };

    xhr.onerror = () => reject(new Error("Network error"));
    xhr.ontimeout = () => reject(new Error("Upload timed out"));
    xhr.timeout = 120_000; // 2 minutes for large files

    xhr.send(formData);
  });
}

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
  | { status: "uploading"; progress: number }
  | { status: "processing" }
  | { status: "error"; message: string }
  | { status: "duplicate"; filename: string; sha: string; file: File; targetDir: string };

type DeleteState =
  | { status: "idle" }
  | { status: "confirming" }
  | { status: "deleting" }
  | { status: "error"; message: string };

type RenameState =
  | { status: "idle" }
  | { status: "editing" }
  | { status: "renaming" }
  | { status: "error"; message: string };

type TreeItemProps = {
  node: TreeNode;
  depth: number;
  parentPath: string;
  expanded: Set<string>;
  onToggle: (path: string) => void;
};

type FileNodeProps = {
  node: TreeNode;
  depth: number;
};

function TreeItem({
  node,
  depth,
  parentPath,
  expanded,
  onToggle,
}: TreeItemProps) {
  const { refreshTree } = useKb();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploadState, setUploadState] = useState<UploadState>({ status: "idle" });

  // Cap visual indent at 3 levels
  const indent = Math.min(depth, 3);
  const paddingLeft = `${indent * 12 + 8}px`;

  const uploadFile = useCallback(async (file: File, targetDir: string, sha?: string) => {
    setUploadState({ status: "uploading", progress: 0 });

    const formData = new FormData();
    formData.append("file", file);
    formData.append("targetDir", targetDir);
    if (sha) formData.append("sha", sha);

    try {
      const { status, body } = await xhrUpload(
        "/api/kb/upload",
        formData,
        (percent) => setUploadState({ status: "uploading", progress: percent }),
      );

      if (status === 409) {
        const sha409 = typeof body === "object" && body && "sha" in body
          ? (body as { sha: string }).sha : undefined;
        if (sha409) {
          setUploadState({ status: "duplicate", filename: file.name, sha: sha409, file, targetDir });
        } else {
          setUploadState({ status: "error", message: "File already exists but server response was malformed" });
        }
        return;
      }

      if (status < 200 || status >= 300) {
        const errBody = typeof body === "object" && body && "error" in body
          ? (body as { error: string }).error : undefined;
        setUploadState({ status: "error", message: errBody || "Upload failed" });
        return;
      }

      // Show processing state only for successful uploads while refreshing tree
      setUploadState({ status: "processing" });
      await refreshTree();
      setUploadState({ status: "idle" });
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

  const dirKey = parentPath ? `${parentPath}/${node.name}` : node.name;
  const isExpanded = expanded.has(dirKey);
  const isBusy = uploadState.status === "uploading" || uploadState.status === "processing";

  return (
    <li>
      <div className="group relative">
        <button
          onClick={() => onToggle(dirKey)}
          className={`flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-neutral-300 hover:bg-neutral-800/50 ${
            isBusy ? "bg-amber-500/10" : ""
          }`}
          style={{ paddingLeft }}
          aria-expanded={isExpanded}
        >
          {uploadState.status === "uploading" ? (
            <UploadProgress percent={uploadState.progress} />
          ) : uploadState.status === "processing" ? (
            <UploadProgress percent={-1} />
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
          {node.modifiedAt && !isBusy && (
            <span className="ml-auto shrink-0 text-xs text-neutral-600 group-hover:opacity-0 transition-opacity">
              {formatRelativeTime(node.modifiedAt)}
            </span>
          )}
        </button>
        {!isBusy && (
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
            child.type === "directory" ? (
              <TreeItem
                key={child.name}
                node={child}
                depth={depth + 1}
                parentPath={dirKey}
                expanded={expanded}
                onToggle={onToggle}
              />
            ) : (
              <FileNode
                key={child.name}
                node={child}
                depth={depth + 1}
              />
            )
          ))}
        </ul>
      )}
    </li>
  );
}

function FileNode({
  node,
  depth,
}: FileNodeProps) {
  const pathname = usePathname();
  const { refreshTree } = useKb();
  const [deleteState, setDeleteState] = useState<DeleteState>({ status: "idle" });
  const [renameState, setRenameState] = useState<RenameState>({ status: "idle" });
  const renameInputRef = useRef<HTMLInputElement>(null);
  const renameSubmittedRef = useRef(false);

  // Cap visual indent at 3 levels
  const indent = Math.min(depth, 3);
  const paddingLeft = `${indent * 12 + 8}px`;

  const renameFile = useCallback(async (filePath: string, newName: string) => {
    setRenameState({ status: "renaming" });
    try {
      const res = await fetch(`/api/kb/file/${filePath}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ newName }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({ error: "Rename failed" }));
        setRenameState({ status: "error", message: body.error || "Rename failed" });
        return;
      }
      setRenameState({ status: "idle" });
      await refreshTree();
    } catch {
      setRenameState({ status: "error", message: "Network error. Please try again." });
    }
  }, [refreshTree]);

  const deleteFile = useCallback(async (filePath: string) => {
    setDeleteState({ status: "deleting" });
    try {
      const res = await fetch(`/api/kb/file/${filePath}`, { method: "DELETE" });
      if (!res.ok) {
        const body = await res.json().catch(() => ({ error: "Delete failed" }));
        setDeleteState({ status: "error", message: body.error || "Delete failed" });
        return;
      }
      setDeleteState({ status: "idle" });
      await refreshTree();
    } catch {
      setDeleteState({ status: "error", message: "Network error. Please try again." });
    }
  }, [refreshTree]);

  const filePath = `/dashboard/kb/${node.path}`;
  const isActive = pathname === filePath;
  const isAttachment = node.extension !== ".md";
  const isDeleting = deleteState.status === "deleting";
  const isRenaming = renameState.status === "renaming";
  const isEditing = renameState.status === "editing";

  // Extract basename without extension for the rename input
  const ext = node.extension || "";
  const baseName = ext ? node.name.slice(0, -ext.length) : node.name;

  const handleRenameConfirm = useCallback((inputValue: string) => {
    if (renameSubmittedRef.current) return;
    const trimmed = inputValue.trim();
    if (!trimmed || trimmed === baseName) {
      setRenameState({ status: "idle" });
      return;
    }
    renameSubmittedRef.current = true;
    if (node.path) {
      renameFile(node.path, trimmed + ext);
    }
  }, [baseName, ext, node.path, renameFile]);

  const handleRenameKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      handleRenameConfirm((e.target as HTMLInputElement).value);
    } else if (e.key === "Escape") {
      e.preventDefault();
      setRenameState({ status: "idle" });
    }
  }, [handleRenameConfirm]);

  // Auto-focus and select input text when entering edit mode
  useEffect(() => {
    if (isEditing && renameInputRef.current) {
      renameInputRef.current.focus();
      renameInputRef.current.select();
    }
  }, [isEditing]);

  return (
    <li>
      <div className="group relative">
        {isEditing ? (
          <div
            className="flex items-center gap-2 rounded-md px-2 py-1.5 text-sm text-neutral-300"
            style={{ paddingLeft }}
          >
            <FileTypeIcon extension={node.extension} />
            <input
              ref={renameInputRef}
              type="text"
              defaultValue={baseName}
              onKeyDown={handleRenameKeyDown}
              onBlur={(e) => handleRenameConfirm(e.target.value)}
              className="min-w-0 flex-1 rounded border border-neutral-600 bg-neutral-800 px-1.5 py-0.5 text-sm text-neutral-200 outline-none focus:border-amber-500"
            />
            <span className="shrink-0 text-sm text-neutral-500">{ext}</span>
          </div>
        ) : (
          <Link
            href={filePath}
            className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors ${
              isActive
                ? "bg-neutral-800 text-amber-400"
                : "text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200"
            } ${isDeleting || isRenaming ? "opacity-50" : ""}`}
            style={{ paddingLeft }}
          >
            <FileTypeIcon extension={node.extension} />
            <span className="truncate">{node.name}</span>
            {node.modifiedAt && !isDeleting && !isRenaming && (
              <span className={`ml-auto shrink-0 text-xs text-neutral-600${isAttachment ? " group-hover:opacity-0 transition-opacity" : ""}`}>
                {formatRelativeTime(node.modifiedAt)}
              </span>
            )}
            {isDeleting && (
              <span className="ml-auto shrink-0 text-xs text-neutral-500">
                Deleting...
              </span>
            )}
            {isRenaming && (
              <span className="ml-auto shrink-0 text-xs text-neutral-500">
                Renaming...
              </span>
            )}
          </Link>
        )}
        {isAttachment && deleteState.status === "idle" && renameState.status === "idle" && (
          <div className="absolute right-1 top-1/2 flex -translate-y-1/2 gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
            <button
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                renameSubmittedRef.current = false;
                setRenameState({ status: "editing" });
              }}
              className="rounded p-1 text-neutral-500 hover:bg-neutral-700 hover:text-neutral-300"
              title="Rename file"
              aria-label={`Rename ${node.name}`}
            >
              <PencilIcon />
            </button>
            <button
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                setDeleteState({ status: "confirming" });
              }}
              className="rounded p-1 text-neutral-500 hover:bg-neutral-700 hover:text-red-400"
              title="Delete file"
              aria-label={`Delete ${node.name}`}
            >
              <TrashIcon />
            </button>
          </div>
        )}
      </div>
      {deleteState.status === "confirming" && (
        <div className="mx-2 mt-1 rounded bg-red-500/10 px-2 py-1.5 text-xs text-red-400" style={{ marginLeft: paddingLeft }}>
          <p className="mb-1.5">Delete &ldquo;{node.name}&rdquo;?</p>
          <div className="flex gap-2">
            <button
              onClick={() => node.path && deleteFile(node.path)}
              className="rounded bg-red-500/20 px-2 py-0.5 text-red-300 hover:bg-red-500/30"
            >
              Delete
            </button>
            <button
              onClick={() => setDeleteState({ status: "idle" })}
              className="rounded px-2 py-0.5 text-neutral-400 hover:text-neutral-300"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
      {deleteState.status === "error" && (
        <div className="mx-2 mt-1 flex items-center gap-1.5 rounded bg-red-500/10 px-2 py-1 text-xs text-red-400" style={{ marginLeft: paddingLeft }}>
          <span className="flex-1">{deleteState.message}</span>
          <button onClick={() => setDeleteState({ status: "idle" })} className="shrink-0 hover:text-red-300" aria-label="Dismiss error">&times;</button>
        </div>
      )}
      {renameState.status === "error" && (
        <div className="mx-2 mt-1 flex items-center gap-1.5 rounded bg-red-500/10 px-2 py-1 text-xs text-red-400" style={{ marginLeft: paddingLeft }}>
          <span className="flex-1">{renameState.message}</span>
          <button onClick={() => setRenameState({ status: "idle" })} className="shrink-0 hover:text-red-300" aria-label="Dismiss error">&times;</button>
        </div>
      )}
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
  if (extension && classifyByExtension(extension) === "image") {
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

function PencilIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" strokeLinecap="round" strokeLinejoin="round" />
      <path d="m15 5 4 4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M3 6h18" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
