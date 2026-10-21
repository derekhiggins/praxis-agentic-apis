# Configuration

Set these environment variables before running `scripts/deploy.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `NAMESPACE` | `praxis-standalone` | Praxis namespace |
| `RELEASE` | `praxis-gateway` | Helm release, Deployment, and Service name |
| `CONFIG_DIR` | Repository `configs/openai-ogx` | Configuration directory |
| `CONFIG_FILE` | `${CONFIG_DIR}/config.yaml` | Praxis pipeline configuration |
| `VALUES_FILE` | `${CONFIG_DIR}/values.yaml` | Helm values override file |
| `API_KEY_SECRET` | `openai` | Namespace-local backend credential Secret |
| `API_KEY_SECRET_KEY` | `OPENAI_API_KEY` | Key within that Secret |
| `INFERENCE_HOST` | `api.openai.com` | HTTPS backend hostname and TLS SNI |
| `INFERENCE_PORT` | `443` | HTTPS backend port |
| `OGX_NAMESPACE` | `redhat-ods-applications` | Existing OGX namespace |
| `OGX_SERVICE` | `ogx-distribution-service` | Existing OGX Service |
| `OGX_PORT` | `8321` | OGX HTTP and NetworkPolicy port |
| `OGX_ENDPOINT` | `${OGX_SERVICE}.${OGX_NAMESPACE}.svc.cluster.local:${OGX_PORT}` | OGX host:port override |
| `OGX_APP_LABEL` | `ogx` | OGX pod selector's `app` value |
| `OGX_INSTANCE_LABEL` | `ogx-distribution` | OGX pod selector's `app.kubernetes.io/instance` value |

`INFERENCE_HOST` must be a hostname, without scheme or path. The default pipeline
uses HTTPS and `/v1/chat/completions`; other transports or API paths require an
alternate config. `OGX_ENDPOINT` does not change the NetworkPolicy target, so
keep its namespace, pod labels, and port consistent with your OGX deployment.

## Multiple configurations

Each configuration directory contains a pipeline `config.yaml` and matching
Helm `values.yaml`. The default is `configs/openai-ogx`. Shared Helm defaults,
including the image pin, probes, and resources, live in `configs/common-values.yaml`.

From the repository root, select a configuration directory:

```bash
CONFIG_DIR=configs/openai-ogx bash ./scripts/deploy.sh
```

Add future configurations as sibling directories. Individual file overrides are
also supported:

```bash
CONFIG_FILE=/path/to/pipeline.yaml \
VALUES_FILE=/path/to/overrides.yaml \
bash ./scripts/deploy.sh
```

Relative directory and file paths resolve from your current working directory.
Helm values are loaded in order: `configs/common-values.yaml`, the selected
directory's `values.yaml`, then `VALUES_FILE`. Later values take precedence.
`CONFIG_FILE` replaces the selected directory's pipeline. The installer sets the
resource name to `RELEASE` and overrides the first environment entry's Secret
reference; retain `OPENAI_API_KEY` as that entry when overriding `env`.

Pipeline files can use `${OGX_ENDPOINT}`, `${INFERENCE_HOST}`,
`${INFERENCE_PORT}`, and `${MCP_SERVER_URL}`. Only these placeholders are
substituted before deployment; other dollar signs are preserved.
Keep credentials in Secrets, not config files.
Alternate configs must retain the API listener on `0.0.0.0:8080`, admin listener on
`127.0.0.1:9901`, and SQLite path under `/var/lib/praxis` to use the existing access, probes,
tests, and storage setup unchanged. OGX remains a prerequisite for the installer.

## Chart and image

- Source: https://github.com/praxis-proxy/grid
- Chart: `oci://ghcr.io/praxis-proxy/charts/praxis-gateway`, version `0.2.1`
- Image: `ghcr.io/praxis-proxy/ai:0.7.0`, pinned in `configs/common-values.yaml` to
  `sha256:550661eea7e392a9f4415b836e0b2393299f26856bc02cbbc8d3301d49b759f3`

The image digest takes precedence over the tag. To select another image, set its
repository and digest in your values override file.

## Storage and upgrades

SQLite uses an `emptyDir` at `/var/lib/praxis`. State survives container restarts
within the same pod, but **is lost when the pod is replaced**, including upgrades
that trigger a rollout. `/tmp` and the root filesystem remain read-only.
`scripts/post-render.py` adds the mount without changing the published chart;
run `scripts/deploy.sh` for every upgrade to retain it.

Changing the backend Secret requires a pod restart to load the new value:

```bash
oc -n "$NAMESPACE" rollout restart "deployment/$RELEASE"
```

This also discards SQLite state.
