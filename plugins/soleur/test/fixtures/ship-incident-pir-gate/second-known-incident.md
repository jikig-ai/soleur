# fix: statutory cron stopped working in production after the egress firewall change

Postmortem: the deployed cron stopped working when the egress firewall change
took the WNS push path down. Customers on production received no statutory
notices for the duration. This restores delivery and adds an email fallback.
