# Runbook: checkout-api

Owner: Payments Platform team (#payments-platform)
Tier: 1 (customer-facing checkout)

## Overview

checkout-api handles cart checkout for the storefront. It runs as the
`checkout-api` Deployment (2 replicas) in the `shop` namespace and stores orders
in the `orders` database on `orders-db` (PostgreSQL, port 5432).

Configuration comes from environment variables: `DATABASE_HOST`,
`DATABASE_PORT`, `DATABASE_NAME`. `DATABASE_USER` and `DATABASE_PASSWORD` are
injected from the `orders-db-credentials` Secret as environment variables, so
they are read once when the container starts.

The readiness probe (`/healthz/ready`) opens a database connection. When the
database rejects checkout-api, pods stay Running but go NotReady, the
`checkout-api` Service has no endpoints, and storefront checkout returns 502.

## Failure: "password authentication failed for user checkout"

Symptom: pods Running but 0/1 Ready; readiness probe events report HTTP 503;
logs show `psycopg2.OperationalError: ... FATAL:  password authentication failed
for user "checkout"`. orders-db logs show the matching FATAL lines.

Cause: the `orders-db-credentials` Secret was rotated and orders-db restarted
with the new password, but checkout-api pods still hold the old password in
their environment. Seen before in INC-4867.

Confirm:

1. orders-db log contains `password for role "checkout" set from
   orders-db-credentials (rotated-at <time>)`.
2. checkout-api pods started before that rotation time.

Fix: restart checkout-api pods so they read the current Secret. Delete the pods
one at a time (`oc delete pod <name>`) or run
`oc rollout restart deployment/checkout-api`. New pods should become Ready
within 20 seconds. Do not change the database password back.

## Failure: "could not translate host name" on startup

Cause: `DATABASE_HOST` points at a Service that does not exist. See INC-4821.
Fix the Deployment env; do not create alias Services.

## Failure: OOMKilled during peak traffic

Cause: memory limit too low for connection pool size. Raise the limit to 512Mi
or lower `DB_POOL_SIZE`. Requires a change request for Tier 1.

## Escalation

Page Payments Platform on-call after 15 minutes of checkout unavailability.
See the on-call escalation policy.
