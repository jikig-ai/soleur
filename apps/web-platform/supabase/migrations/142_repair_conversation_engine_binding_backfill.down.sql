-- Security correction is monotonic: do not reopen tenant marker spoofing or
-- turn repaired bound rows back into pending. Dev may discard the ledger row;
-- reapplying 142 replaces its INSERT trigger inside one transaction.
SELECT 1;
