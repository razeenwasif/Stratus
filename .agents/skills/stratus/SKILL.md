---
name: stratus
description: >-
  Inspect and manage Google Cloud Platform resources on the user's behalf via Stratus
  (MCP server `stratus_*` tools and the `stratus` CLI), and open/focus the Stratus macOS app UI.
---

# Stratus Google Cloud Agent Skill

Use **Stratus** whenever the user asks you to inspect, troubleshoot, query, or operate their Google Cloud Platform projects, Compute Engine VMs, Cloud Run services, Cloud Storage buckets/objects, BigQuery datasets/SQL, Cloud SQL instances, Secret Manager secrets, Cloud Logging, IAM policies, or enabled APIs.

## Preferred Channels

1. **MCP Tools (`stratus` server)**: Prefer the `stratus_*` MCP tools when available (`stratus_status`, `stratus_list_projects`, `stratus_overview`, `stratus_list_vms`, `stratus_vm_action`, `stratus_list_gke`, `stratus_list_cloud_run`, `stratus_list_functions`, `stratus_list_network`, `stratus_list_artifacts`, `stratus_builds`, `stratus_scheduler`, `stratus_list_buckets`, `stratus_list_objects`, `stratus_read_object`, `stratus_pubsub`, `stratus_databases`, `stratus_monitoring`, `stratus_query_logs`, `stratus_list_iam`, `stratus_list_apis`, `stratus_toggle_api`, `stratus_bigquery`, `stratus_cloud_sql`, `stratus_secrets`, `stratus_open_ui`).
2. **CLI Fallback (`stratus`)**: When running from a shell (or inside Fairy / Claude / Codex without MCP loaded), use `~/.local/bin/stratus`, which outputs clean JSON:

```sh
stratus status
stratus projects
stratus overview -p <project-id>
stratus vm list -p <project-id>
stratus gke -p <project-id>
stratus run list -p <project-id>
stratus functions -p <project-id>
stratus network -p <project-id>
stratus artifacts -p <project-id>
stratus builds -p <project-id>
stratus scheduler -p <project-id>
stratus pubsub -p <project-id>
stratus db firestore|spanner|redis -p <project-id>
stratus metrics computeCPU|cloudRunRequests|sqlCPU|sqlMemory -p <project-id>
stratus storage buckets -p <project-id>
stratus logs --filter "severity>=ERROR" --limit 50 -p <project-id>
stratus iam -p <project-id>
stratus apis list -p <project-id>
stratus bq query "SELECT 1" -p <project-id>
stratus sql list -p <project-id>
stratus secrets list -p <project-id>
stratus open compute -p <project-id>
```

Add `--demo` to any command (or `"demo": true` in MCP tool arguments) to preview with offline Demo Mode data.

## Safety Rules

- Always inspect before mutating (`stratus_list_vms` before `stratus_vm_action`, `stratus_list_apis` before `stratus_toggle_api`).
- Only reveal Secret Manager payloads (`stratus_secrets` with `revealVersion` / `stratus secrets reveal`) when explicitly needed, and never echo raw secret values into logs or commits.
- Use `stratus_open_ui` (or `open "stratus://navigate?section=<section>&project=<id>"`) when showing the user a visual view in the Stratus desktop app is helpful.
