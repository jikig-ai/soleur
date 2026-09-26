"use client";

import { FolderIcon, RefreshIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

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
        <h1 className="text-3xl font-semibold">
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
        <Button variant="gold" type="button" onClick={onUpdateAccess}>Update Access on GitHub</Button>
        {onRefresh && (
          <Button variant="outlined" type="button" onClick={onRefresh}>
            <RefreshIcon className="mr-1.5 inline h-4 w-4" />
            Refresh
          </Button>
        )}
        <Button variant="outlined" type="button" onClick={onBack}>Go Back</Button>
      </div>
    </div>
  );
}
