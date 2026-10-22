# On-call escalation policy

## Severity

- SEV1: customer-facing outage (website, checkout, login, payments). Page immediately.
- SEV2: degraded customer experience or Tier 1 service at risk. Page within 15 minutes.
- SEV3: internal impact only. Ticket during business hours.

## Who to page

- Web Experience: storefront.
- Payments Platform: checkout-api, payments-gateway, payments-worker.
- Data Platform: orders-db and other PostgreSQL, Kafka, Vault database secrets.
- Cluster Operations: node, network, or OpenShift platform issues.

## Incident ticket contents

Every incident ticket must include: summary, impact, timeline, root cause (or
current hypothesis), evidence (logs, events, metrics), linked incidents, and
next steps with owners.

## Changes during incidents

Restarting pods of a Tier 1 service is pre-approved when a runbook prescribes
it; record each pod restarted in the ticket. Configuration changes need
approval from the incident commander.
