# Runbook: payments-worker

Owner: Payments Platform team (#payments-platform)
Tier: 2

## Overview

payments-worker consumes settlement jobs from the `settlements` Kafka topic and
writes results to the ledger service. It holds a job lease while processing.

## Failure: consumer lag growing

Cause: slow ledger responses or too few replicas. Check ledger latency first,
then scale: `oc scale deployment/payments-worker --replicas=4`. Do not exceed
the topic partition count (8).

## Failure: duplicate settlement jobs

Cause: lease not released when the pod is killed during a node drain (INC-4755).
Confirm `terminationGracePeriodSeconds` is at least 30. Duplicates are
idempotent in the ledger, so no customer impact; file a ticket only if the
duplicate rate exceeds 1%.

## Failure: TLS handshake errors to Kafka

Cause: expired client certificate in the `payments-worker-kafka-tls` Secret.
Certificates are issued by cert-manager; check the Certificate resource status
and the issuer logs.
