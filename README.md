# LuaMadePackages

A **public, Azure-hosted package registry** for sharing LuaMade scripts and programs.

---

## Table of Contents

- [Architecture](#architecture)
- [Repository Layout](#repository-layout)
- [Quick Start – Using the CLI](#quick-start--using-the-cli)
- [Package Format](#package-format)
- [API Reference](#api-reference)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites)
  - [1. Create Azure credentials](#1-create-azure-credentials)
  - [2. Generate an API key](#2-generate-an-api-key)
  - [3. Deploy via GitHub Actions](#3-deploy-via-github-actions)
  - [4. Local development](#4-local-development)
- [Contributing](#contributing)

---

## Architecture

```
┌─────────────────┐       HTTPS       ┌──────────────────────────────────┐
│  lpm  (Lua CLI) │ ─────────────────▶│  Azure Functions (Node.js v4)    │
└─────────────────┘                   │                                  │
                                      │  GET  /api/packages              │
                                      │  GET  /api/packages/{name}       │
                                      │  POST /api/packages              │
                                      │  GET  /api/packages/{n}/{v}/dl   │
                                      │  DEL  /api/packages/{n}/{v}      │
                                      └───────────────┬──────────────────┘
                                                      │
                                                      ▼
                                      ┌──────────────────────────────────┐
                                      │  Azure Blob Storage              │
                                      │  container: packages             │
                                      │                                  │
                                      │  {name}/metadata.json            │
                                      │  {name}/{version}/package.tar.gz │
                                      └──────────────────────────────────┘
```

| Component | Technology |
|-----------|-----------|
| API | Azure Functions v4 (Node.js 18) |
| Storage | Azure Blob Storage (Standard LRS) |
| Hosting | Consumption Plan (pay-per-use) |
| Monitoring | Application Insights |
| IaC | Azure Bicep |
| CLI | Lua 5.3+ |

---

## Repository Layout

```
LuaMadePackages/
├── api/                         Azure Functions API
│   ├── host.json                Functions host configuration
│   ├── package.json
│   ├── local.settings.json.example
│   ├── src/
│   │   ├── functions/
│   │   │   ├── listPackages.js       GET  /api/packages
│   │   │   ├── getPackage.js         GET  /api/packages/{name}
│   │   │   ├── publishPackage.js     POST /api/packages
│   │   │   ├── downloadPackage.js    GET  /api/packages/{name}/{version}/download
│   │   │   └── deletePackageVersion.js  DELETE /api/packages/{name}/{version}
│   │   └── utils/
│   │       ├── auth.js          Bearer token verification
│   │       ├── storage.js       Azure Blob Storage helpers
│   │       └── validation.js    Input validation + response helpers
│   └── tests/                   Jest unit tests
│       ├── auth.test.js
│       ├── storage.test.js
│       └── validation.test.js
├── infra/                       Azure Bicep infrastructure templates
│   ├── main.bicep               Storage Account + Function App + App Insights
│   └── parameters.json          Example parameter values
├── cli/                         Lua CLI client (lpm)
│   ├── lpm.lua                  Entry point
│   └── lib/
│       ├── config.lua           Registry URL + install dir
│       ├── http.lua             HTTP GET/POST/DELETE helpers
│       ├── json.lua             dkjson wrapper
│       └── fs.lua               Path / directory helpers
└── .github/workflows/
    └── deploy.yml               CI/CD pipeline (test → infra → app)
```

---

## Quick Start – Using the CLI

### Prerequisites

Install Lua dependencies via [LuaRocks](https://luarocks.org/):

```bash
luarocks install luasocket
luarocks install luasec
luarocks install dkjson
```

### Search for packages

```bash
lua lpm.lua search json
```

### View package details

```bash
lua lpm.lua info my-library
```

### Install a package

```bash
# Install the latest version
lua lpm.lua install my-library

# Install a specific version
lua lpm.lua install my-library 1.2.0
```

Packages are extracted to `./packages/<name>/<version>/` by default.  
Override with the `LPM_INSTALL_DIR` environment variable.

### Publish a package

1. Create a `manifest.json` (see [Package Format](#package-format)).
2. Bundle your Lua files into a tarball: `tar -czf my-library-1.0.0.tar.gz src/`
3. Publish:

```bash
LPM_API_KEY=<your-key> lua lpm.lua publish manifest.json my-library-1.0.0.tar.gz
```

### Delete a package version

```bash
LPM_API_KEY=<your-key> lua lpm.lua delete my-library 1.0.0
```

### Point the CLI at a custom registry

```bash
export LPM_REGISTRY_URL=https://my-function-app.azurewebsites.net/api
```

---

## Package Format

### `manifest.json`

```json
{
  "name": "my-library",
  "version": "1.0.0",
  "description": "A short description of the package.",
  "author": "Your Name",
  "license": "MIT",
  "luamadeVersion": ">=1.0.0",
  "tags": ["json", "utility"],
  "dependencies": {
    "other-library": "2.0.0"
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Lowercase alphanumeric + hyphens/underscores, 1–64 chars |
| `version` | ✅ | Semantic version (`MAJOR.MINOR.PATCH`) |
| `description` | ✅ | Short human-readable description |
| `author` | ✅ | Author name |
| `license` | | SPDX license identifier (default: `MIT`) |
| `luamadeVersion` | | Minimum compatible LuaMade version |
| `tags` | | Array of searchable keyword strings |
| `dependencies` | | Map of `{ "pkg-name": "version" }` |

### Tarball structure

```
my-library-1.0.0.tar.gz
└── init.lua          ← main entry point
└── ...               ← additional Lua files
```

---

## API Reference

Base URL: `https://<function-app-hostname>/api`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/packages` | — | List all packages. Supports `?search=<query>` |
| `GET` | `/packages/{name}` | — | Get full metadata for a package |
| `POST` | `/packages` | Bearer | Publish a new package version |
| `GET` | `/packages/{name}/{version}/download` | — | Redirect to tarball download URL |
| `DELETE` | `/packages/{name}/{version}` | Bearer | Delete a specific package version |

### Authentication

Authenticated endpoints require:

```
Authorization: Bearer <api-key>
```

The server compares the SHA-256 hash of the provided key against the `API_KEY_HASH`
application setting, so the plaintext key is never stored in Azure.

### Publish request body

`Content-Type: multipart/form-data`

| Field | Type | Description |
|-------|------|-------------|
| `manifest` | text (JSON) | Package manifest |
| `package` | binary (file) | Package tarball (`.tar.gz`) |

---

## Deployment

### Prerequisites

- Azure CLI (`az`) – [install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure Functions Core Tools v4 – [install](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- Node.js 18+

### 1. Create Azure credentials

Create a service principal with Contributor rights on your subscription:

```bash
az ad sp create-for-rbac \
  --name "luamadepkgs-deploy" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id> \
  --sdk-auth
```

Copy the JSON output and add it as the GitHub secret **`AZURE_CREDENTIALS`**.

### 2. Generate an API key

```bash
# Generate a random key
API_KEY=$(openssl rand -base64 32)
echo "Your API key: $API_KEY"

# Hash it (store the HASH, not the key itself)
API_KEY_HASH=$(echo -n "$API_KEY" | sha256sum | cut -d' ' -f1)
echo "Store this hash as the AZURE_CREDENTIALS secret: $API_KEY_HASH"
```

Add `API_KEY_HASH` as a GitHub secret.  
Save `API_KEY` somewhere safe – you need it for `LPM_API_KEY`.

### 3. Deploy via GitHub Actions

Push to `main` (or trigger the workflow manually):

```bash
git push origin main
```

The pipeline will:
1. Run all unit tests
2. Deploy the Bicep infrastructure (creates/updates the Azure resources)
3. Deploy the Function App code

### 4. Local development

```bash
cd api
cp local.settings.json.example local.settings.json
# Edit local.settings.json – set AZURE_STORAGE_CONNECTION_STRING
# (Use Azurite for local blob storage: https://learn.microsoft.com/azure/storage/common/storage-use-azurite)

npm install
func start
```

The API will be available at `http://localhost:7071/api`.

---

## Contributing

1. Fork the repository.
2. Create a feature branch.
3. Make changes and add tests in `api/tests/`.
4. Run `npm test` from the `api/` directory.
5. Open a pull request.

All pull requests are validated by the CI pipeline before merging.
