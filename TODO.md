# TODO

- [x] Demo walkthrough with requests, expected output, and tool-call flow
  (`demos/shop-outage`).
- [ ] Investigate MCP dispatch parse-charge limit; drop the `max_retained_bytes`
  workaround in the pipeline in `charts/praxis-agentic-apis/values.yaml`.
- [x] Move to an upstream praxis-ai image once the subrequest fix is merged.
- [ ] Validate a real client/harness end to end and document its configuration.
- [ ] Architecture overview showing Praxis, OGX, inference, and request flow.
- [x] PostgreSQL-backed Responses and Conversations storage.
- [x] Web search in the agentic loop.
- [x] MCP tool discovery and execution.
- [ ] Integrate with the RHOAI MCP catalogue.
- [ ] Conversation context compaction.
- [ ] CI for demo validation and tests.
- [x] Make the setup installable with plain Helm, without the `deploy.sh` wrapper.
- [ ] Switch the praxis-gateway dependency to the published OCI chart once it supports `praxisConfig.byo.tpl`.
