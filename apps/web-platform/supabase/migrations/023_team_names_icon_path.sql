-- Add custom_icon_path column to team_names table.
-- Stores a relative KB path (e.g., 'settings/team-icons/cto.png').
-- Existing RLS policy on team_names covers this column automatically.
ALTER TABLE team_names ADD COLUMN IF NOT EXISTS custom_icon_path text;
