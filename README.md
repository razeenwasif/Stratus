<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="Stratus App Icon" />
</p>

<h1 align="center">Stratus</h1>

<p align="center">
  <strong>A fast, minimal, pitch-black native macOS desktop console for Google Cloud Platform.</strong><br />
  Built directly on Google Cloud REST APIs with SwiftUI, Swift Charts, and zero external dependencies.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0-E88255?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20Swift%20Charts-7A89FF?style=flat-square" alt="SwiftUI + Swift Charts" />
  <img src="https://img.shields.io/badge/dependencies-zero-34D399?style=flat-square" alt="Zero Dependencies" />
</p>

---

## Design Philosophy

Google Cloud's web console is dense, nested, and slow to navigate. **Stratus** strips away chrome and visual noise in favor of a calm, keyboard-first workspace:

- **Pure Pitch Black (`#000000`)**: Seamless dark canvas extending into a transparent macOS titlebar.
- **Zero Pane Dividers & Zero Card Borders**: Navigation, content, and inspector drawers are separated purely by whitespace, typographic hierarchy, and subtle tonal elevation (`#060608` / `#111114`).
- **Tabular Telemetry**: Monospace tabular figures (`monospacedDigit`) for spend, vCPUs, IP addresses, request counts, and timestamps.
- **Instant Exploration**: Ships with an offline **Demo Mode** so you can explore the full interface before connecting a live project.

---

## Features

| Section | Capabilities |
| :--- | :--- |
| **Overview** | Hero total spend KPI (exact invoice spend via optional BigQuery Billing Export or API resource estimate), service breakdown, interactive 30-day `.monotone` spline area chart, `Totals` strip, and `Top resources`. |
| **Compute & GKE** | Compute Engine VMs (Running/Stopped filters, IPs, **Start / Stop / Reset**, SSH copy) + **GKE Kubernetes** clusters, node pools & `kubectl` credential copy. |
| **Serverless** | **Cloud Run** services, traffic split bars & revision history + **Cloud Functions v2** runtimes, triggers & endpoints. |
| **Network & CI** | **VPC & Firewall Rules** (ALLOW/DENY, protocols/ports, source ranges), **Artifact Registry** repos & Docker image pull commands, **Cloud Build** history & **Cloud Scheduler** jobs (**Run Now**). |
| **Cloud Storage** | Borderless bucket & folder browser with breadcrumbs, inline text/JSON/YAML preview, **Upload**, **Download**, and **Delete**. |
| **Data & Messaging** | **BigQuery** SQL workspace, **Cloud SQL** instances & restart, **Firestore** databases & root collections, **Cloud Spanner**, **Memorystore (Redis)**, and **Pub/Sub** topics/subscriptions with inline **Publish**. |
| **Monitoring** | Live **Cloud Monitoring** CPU, Memory, and Cloud Run request rate time-series spline charts (`1h`, `6h`, `24h`). |
| **Cloud Logging** | Monospace log stream with severity pills (`ERR`, `WRN`, `INF`, `DBG`) and expandable `jsonPayload` inspection. |
| **Security & IAM** | **IAM Principals**, **Enabled APIs** (enable/disable), and **Secret Manager** version inspection with masked-by-default payload reveal. |
| **Agent Drawer (`⌘J`)** | Built-in **Fairy** & **Antigravity (`agy`)** chat drawer with live project/resource context, plus `⌘K` Command Palette. |

---

## Authentication & Security

Stratus communicates directly with official `*.googleapis.com` REST endpoints and **never** bundles API keys, client secrets, or telemetry trackers:

1. **Local `gcloud` CLI / ADC (Recommended)**
   Auto-detects `gcloud` in `/opt/homebrew/bin/gcloud`, `/usr/local/bin/gcloud`, or `~/google-cloud-sdk/bin/gcloud`, reading short-lived tokens via `gcloud auth print-access-token` or Application Default Credentials.
2. **Native Google OAuth 2.0 (PKCE)**
   Uses `ASWebAuthenticationSession` with SHA-256 PKCE (`com.stratus.gcp:/oauth2redirect`). Access & refresh tokens are stored strictly in your **macOS Keychain** (`com.stratus.gcp`).
3. **Bearer Token / Demo Mode**
   Paste a temporary `ya29...` token into Keychain or toggle offline Demo Mode anytime from the bottom-left account pill.
4. **Exact Invoice Billing (Optional)**
   Configure a BigQuery Billing Export table (`project.dataset.gcp_billing_export_v1_...`) in Connection Settings to power the Overview dashboard with exact net billed daily spend instead of API estimates.

---

## Installation & Build

### Requirements
- macOS 14.0+ (Sonoma or newer)
- Xcode / Swift 6.0+ toolchain

### Package & Install to `~/Applications`

```bash
# Run unit tests
swift test

# Build release binary, generate .app bundle with icon, and install to ~/Applications
./scripts/build-app.sh --release --install

# Launch Stratus
open ~/Applications/Stratus.app
```

Or run directly during development:

```bash
swift run
```

*(To regenerate `Assets/AppIcon.png` and `Assets/AppIcon.icns`, run `swift scripts/generate-icon.swift`.)*

---

## Agent Integration (`agy` & `fairy`)

Stratus ships with a built-in **MCP stdio server** (`--mcp`), a **JSON CLI** (`stratus`), and **`stratus://` deep-link navigation** so Antigravity (`agy`) and Fairy (Claude Code, Codex, and Gemini) can inspect and operate Google Cloud resources on your behalf.

### Install Agent Integrations

After installing `~/Applications/Stratus.app`, run:

```bash
./scripts/install-agent-integrations.sh
```

This configures:
- **CLI**: Symlinks `~/.local/bin/stratus` → `~/Applications/Stratus.app/Contents/MacOS/Stratus`
- **MCP Server (`--mcp`)**: Registers `stratus` in Antigravity (`agy mcp add`), Claude Code/Fairy (`~/.claude.json`), and Codex/Fairy (`~/.codex/config.toml`)
- **Agent Skill**: Installs `.agents/skills/stratus/SKILL.md` to `~/.gemini/config/skills/stratus/`, `~/.claude/skills/stratus/`, and `~/.codex/skills/stratus/`

### Available MCP Tools & CLI Commands

| MCP Tool | CLI Equivalent | Purpose |
| :--- | :--- | :--- |
| `stratus_status` | `stratus status` | Auth mode, active email, default project |
| `stratus_list_projects` | `stratus projects` | List accessible GCP projects |
| `stratus_overview` | `stratus overview` | Cost & resource summary |
| `stratus_list_vms` / `stratus_vm_action` | `stratus vm list\|start\|stop\|reset` | Inspect & control Compute VMs |
| `stratus_list_gke` | `stratus gke` | List GKE clusters & node counts |
| `stratus_list_cloud_run` | `stratus run list` | List Cloud Run services & URLs |
| `stratus_list_functions` | `stratus functions` | List Cloud Functions v2 runtimes & triggers |
| `stratus_list_network` | `stratus network` | List VPC networks & firewall rules |
| `stratus_list_artifacts` | `stratus artifacts [repo]` | List Artifact Registry repos & Docker images |
| `stratus_builds` / `stratus_scheduler` | `stratus builds` / `stratus scheduler` | View Cloud Build runs & trigger Scheduler jobs |
| `stratus_list_buckets` / `stratus_list_objects` / `stratus_read_object` | `stratus storage buckets\|ls\|cat` | Browse & read GCS objects |
| `stratus_pubsub` | `stratus pubsub [publish ...]` | List Pub/Sub topics/subscriptions & publish |
| `stratus_databases` | `stratus db [firestore\|spanner\|redis]` | Inspect Firestore, Spanner & Memorystore Redis |
| `stratus_monitoring` | `stratus metrics [kind] [--hours N]` | Query Cloud Monitoring CPU, Memory & request series |
| `stratus_query_logs` | `stratus logs --filter "..."` | Query Cloud Logging |
| `stratus_list_iam` / `stratus_list_apis` / `stratus_toggle_api` | `stratus iam` / `stratus apis ...` | Inspect IAM & toggle GCP APIs |
| `stratus_bigquery` / `stratus_cloud_sql` / `stratus_secrets` | `stratus bq\|sql\|secrets ...` | Query BigQuery, Cloud SQL & Secret Manager |
| `stratus_open_ui` | `stratus open [section]` | Focus the Stratus macOS app via `stratus://` |

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘K` | Open Command Palette |
| `⌘J` | Toggle In-App Agent Drawer (Fairy / Antigravity) |
| `⌘R` | Refresh active view |
| `⌘1` – `⌘9` | Jump to Overview, Compute & GKE, Serverless, Network & CI, Storage, Data & Pub/Sub, Monitoring, Logs, or Security & IAM |
| `⌘\` | Toggle sidebar |
| `Esc` | Close Command Palette, Agent Drawer, or Inspector drawer |

---

## Project Structure

```text
.
├── .agents/skills/stratus/
│   └── SKILL.md                  # Agent skill for Antigravity (agy) & Fairy
├── Assets/
│   ├── AppIcon.icns
│   └── AppIcon.png
├── Package.swift
├── scripts/
│   ├── build-app.sh              # Compiles, bundles Stratus.app, and optionally installs to ~/Applications
│   ├── generate-icon.swift       # Renders 1024x1024 icon & compiles AppIcon.icns
│   └── install-agent-integrations.sh  # Links `stratus` CLI and registers MCP + skills for agy & Fairy
├── Sources/Stratus/
│   ├── Agent/                    # AgentBridge, MCPServer (--mcp), and StratusCLI
│   ├── Models/                   # Sendable GCP resource, billing, monitoring & extended models
│   ├── Services/                 # AuthManager (PKCE + gcloud), KeychainStore, GCPAPIClient, CostEstimator, AgentChatService, DemoDataProvider
│   ├── State/                    # @MainActor @Observable AppState
│   ├── Theme/                    # Pitch-black T3 tokens & zero-border SwiftUI components
│   ├── Views/                    # Overview, Compute & GKE, Serverless, Network & CI, Storage, Data & Pub/Sub, Monitoring, Logging, Security & IAM, Inspector, AgentDrawer, CommandPalette
│   ├── StratusApp.swift
│   └── StratusEntrypoint.swift   # Hybrid GUI / CLI / MCP stdio entrypoint
└── Tests/StratusTests/           # Unit tests for PKCE, GCS encoding, REST JSON decoding, billing export, MCP & agent chat
```
