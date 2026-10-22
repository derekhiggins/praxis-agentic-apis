# Runbook: orders-db

Owner: Data Platform team (#data-platform)
Tier: 1

## Overview

orders-db is the PostgreSQL 16 server for the `orders` database. It runs as the
`orders-db` StatefulSet (1 replica) in the `shop` namespace behind the
`orders-db` Service on port 5432. Clients: checkout-api (role `checkout`).

## Credential rotation

The `checkout` role password is rotated weekly by the Vault database secrets
engine. The rotation job updates the `orders-db-credentials` Secret and restarts
orders-db, which logs:
`password for role "checkout" set from orders-db-credentials (rotated-at <time>)`.

Clients must pick up the new Secret. Clients that read credentials from
environment variables need their pods restarted after every rotation; see
INC-4867. The rotation job does not restart clients.

## Failure: "password authentication failed for user"

orders-db is healthy; the client is sending a stale or wrong password. The log
pairs a `FATAL:  password authentication failed` line with a `DETAIL:` line
naming the matched pg_hba.conf rule. Fix the client, not the database. Do not
reset the role password manually; it breaks the next Vault rotation.

## Failure: "could not extend file" / disk full

WAL or table growth filled the volume. See INC-4933. Page Data Platform.

## Failure: too many connections

`FATAL:  sorry, too many clients already`. Check client pool sizes; max is 200.
