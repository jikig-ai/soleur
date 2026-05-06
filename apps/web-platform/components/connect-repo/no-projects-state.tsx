"use client";

import { FolderIcon, RefreshIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface NoProjectsStateProps {
  onUpdateAccess: () => void;
  onBack: () => void;
  onRefresh?: () => void;
}

export function NoProjectsState({ onUpdateAccess, onBack, onRefresh }: NoProjectsStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div className="flex items-center gap-3">
        <Badge>CONNECT PROJECT</Badge>
      </div>

      <div className="space-y-2">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          Select a Project
        </h1>
      </div>

      <Card className="flex flex-col items-center py-12 text-center">
        <FolderIcon className="mb-4 h-12 w-12 text-soleur-text-muted" />
        <h3 className="text-lg font-medium text-soleur-text-primary">No projects found</h3>
        <p className="mt-2 max-w-sm text-sm text-soleur-text-muted">
          We could not find any repositories you have granted access to. You may
          need to update the GitHub App permissions to include the repositories
          you want to connect.
        </p>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onUpdateAccess}>Update Access on GitHub</GoldButton>
        {onRefresh && (
          <OutlinedButton onClick={onRefresh}>
            <RefreshIcon className="mr-1.5 inline h-4 w-4" />
            Refresh
          </OutlinedButton>
        )}
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}
