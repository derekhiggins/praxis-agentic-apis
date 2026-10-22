# Known issues

Open and monitored issues for the shop platform. Full reports are in the
incident report documents.

## INC-4867: checkout-api keeps stale database password after rotation

Status: open, action item pending
Affected: checkout-api

checkout-api reads `orders-db-credentials` through environment variables and
does not reload after the weekly Vault rotation. Workaround: restart
checkout-api pods after rotation. Permanent fix (Stakater Reloader annotation
on the Deployment) is not deployed yet.

## INC-4933: orders-db volume filled by WAL

Status: monitoring
Affected: orders-db, checkout-api

Replication slot left behind by a decommissioned replica retained WAL. Disk
usage alert lowered to 70%.

## INC-4755: payments-worker duplicate jobs after node drain

Status: monitoring
Mitigated by a 30s `terminationGracePeriodSeconds`. See the payments-worker
runbook.

## Resolved

- INC-4821: checkout-api could not resolve legacy database hostname.
- INC-4790: intermittent 502s from payments-gateway (router timeout).
- INC-4902: slow storefront pages from product image CDN.
