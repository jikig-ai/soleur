-- Security correction is monotonic: do not reopen tenant marker spoofing or
-- turn repaired bound rows back into pending. Dev may discard the ledger row;
-- migration 142's applied bytes stay immutable once dev has ledgered them.
SELECT 1;
