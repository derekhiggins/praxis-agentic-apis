# Runbook: storefront

Owner: Web Experience team (#web-experience)
Tier: 1 (public website)

## Overview

storefront serves the public shop website: home, product, search, and cart
pages. It runs as the `storefront` Deployment (2 replicas) in the `shop`
namespace. Checkout requests (`POST /checkout`) are proxied to
`http://checkout-api:8080/api/v1/checkout`.

Access logs use the format
`<ip> - - [<time>] "<method> <path> HTTP/1.1" <status> "<agent>" rt=<seconds>`.
Proxied requests add `upstream=`, `upstream_status=`, and `error=` fields. Every
60 seconds each pod logs a `stats last 60s` summary with 5xx and checkout
failure counts.

## Failure: checkout returns 502, other pages fine

Symptom: `POST /checkout` returns 502 with `upstream=checkout-api:8080`;
page requests return 200.

- `error="[Errno 111] Connection refused"`: the checkout-api Service has no
  ready endpoints. Investigate checkout-api readiness; see the checkout-api
  runbook. Restarting storefront does not help.
- `upstream_status=503`: checkout-api is reachable but failing requests; check
  checkout-api logs.
- `timed out`: checkout-api is slow; check orders-db load.

## Failure: all pages slow

Check product image CDN status first (see INC-4902), then pod CPU with
`oc adm top pods`. Scale to 4 replicas during sales events.

## Escalation

Customer-facing outage of any page is SEV1. Checkout failures alone are SEV1
and owned by Payments Platform.
