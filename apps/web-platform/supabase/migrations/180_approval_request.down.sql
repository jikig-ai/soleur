-- 180_approval_request.down.sql
-- NOT A HOT ROLLBACK. Running this while the application that calls the approval RPCs is live breaks account
-- deletion (saga step 5.16 calls anonymise_approval_request and fails closed), strands supabase/verify/068 and
-- verify/180 (they assert this schema), and drops the audit table with every approval record. The production
-- rollback for the approval queue is: turn the `approval-queue` flag OFF and KEEP the schema. This file exists for
-- the DEV reset of an unmerged edit of 180 (delete the _schema_migrations row, re-apply) and for a full revert of
-- the feature after the application code is gone.
--
-- Reverse 180: drop the approval RPCs, the guard trigger function, the table, and restore the narrower
-- inbox_item.source CHECK. The approval-sourced inbox rows are deleted first (they would violate the restored
-- CHECK); they are derived notifications, the approval_request rows (dropped below) are the record.

DROP FUNCTION IF EXISTS public.anonymise_approval_request(uuid);
DROP FUNCTION IF EXISTS public.sweep_approvals();
DROP FUNCTION IF EXISTS public.list_live_approvals(uuid);
DROP FUNCTION IF EXISTS public.get_approval_status(uuid);
DROP FUNCTION IF EXISTS public.consume_approval(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.decide_approval(uuid, text);
DROP FUNCTION IF EXISTS public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer);
DROP FUNCTION IF EXISTS public.approval_request_inbox_settle(uuid, uuid, text);
-- Pre-review signature (a DEV database that applied 180 before the settle function took the workspace id).
DROP FUNCTION IF EXISTS public.approval_request_inbox_settle(uuid, text);

DROP TABLE IF EXISTS public.approval_request;
DROP FUNCTION IF EXISTS public.approval_request_guard();

DELETE FROM public.inbox_item
 WHERE source = 'approval_required';

ALTER TABLE public.inbox_item DROP CONSTRAINT IF EXISTS inbox_item_source_check;
ALTER TABLE public.inbox_item
  ADD CONSTRAINT inbox_item_source_check
  CHECK (source IN ('task_completed', 'system'))
  NOT VALID;
ALTER TABLE public.inbox_item VALIDATE CONSTRAINT inbox_item_source_check;
