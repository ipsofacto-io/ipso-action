# ipso-action

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ipsofacto-io/ipso-action/badge)](https://scorecard.dev/viewer/?uri=github.com/ipsofacto-io/ipso-action)

GitHub Action that runs [ipso](https://github.com/ipsofacto-io/ipso) engineering decision checks in CI, uploads SARIF alerts to GitHub Code Scanning, stores verdict evidence as a workflow artifact, and optionally uploads verdict reports to an ipso control plane.

> Status: tested on every pull request and listed on GitHub Marketplace (from v0.1.0). Installs and verifies `ipso` v0.4.0 by default. Always pin this action to a full commit SHA.

## Quick start

Run `ipso-action` from the repository root so SARIF file paths resolve correctly. See [`ipsofacto-io/examples`](https://github.com/ipsofacto-io/examples) for a live working workflow.

```yaml
name: ipso

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write # upload SARIF to GitHub Code Scanning
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # Generate your plan first, e.g.:
      # terraform plan -out p && terraform show -json p > plan.json
      - uses: ipsofacto-io/ipso-action@<commit-sha> # pin a full commit SHA
        with:
          command: plan
          args: plan.json
          env: prod
```

### How it works

1. Runs `ipso check` to validate your EDR decision records.
2. Runs `ipso compile` to compile in-force checks (skipped when `args` contains `--bundle`, since a signed policy bundle replaces the local build).
3. Runs `ipso check <command> <args> --report <file> --sarif <file>`.
4. Uploads the SARIF file and evidence artifact (even when the check fails), then exits with the check's status.

**Security note for pull requests:** On a pull request, decisions are loaded from the PR's checkout, which means a PR author can modify both code and decision files together. Protect `docs/decisions` with `CODEOWNERS`, or enforce a signed policy bundle with `plan --bundle`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `command` | Yes | | Check engine to run: `plan`, `ci`, `checkov`, `snyk`, `wiz`, `sonarqube`, `dependabot`, `pulumi`, `cloudformation`, `arm`, `depcruise`, `semgrep`, `archunit`, `importlinter`, `kyverno`, `gatekeeper`, or `eslint` |
| `args` | No | | Whitespace-separated arguments passed to the check command (no shell expansion, so paths cannot contain spaces; `--report`, `--sarif`, `--env`, and `--input` are rejected here) |
| `env` | No | | Environment name passed as `--env` |
| `input` | No | | Named input passed as `--input` (not supported by `ci`) |
| `version` | No | `0.4.0` | `ipso` release version to install (without a leading `v`) |
| `cli-path` | No | | Path to a pre-installed `ipso` binary on the runner (skips download and attestation verification) |
| `upload-sarif` | No | `true` | Set to `false` in private repositories without GitHub Code Scanning |
| `server-url` | No | | Base HTTPS URL of an ipso control plane (for example `https://ipso.example.com`); must be paired with `server-audience` ([details](#upload-to-an-ipso-control-plane)) |
| `server-audience` | No | | OIDC token audience expected by the control plane (`IPSO_CI_AUDIENCE`); never derived automatically from `server-url` |

`env` and `input` form the SARIF category so multiple checks on different inputs do not overwrite each other's alerts. Use one step per named run.

## Outputs

| Output | Description |
| --- | --- |
| `exit-code` | Exit code returned by the check command |
| `sarif` | Path to the generated SARIF file (empty if none was written) |
| `report` | Path to the verdict report JSON (empty if none was written) |
| `evidence-name` | Name of the uploaded workflow artifact (empty if nothing was uploaded) |
| `upload-id` | Verdict upload ID returned by the control plane (empty if not uploaded) |

## Upload to an ipso control plane

To publish check verdicts to an ipso control plane (using GitHub OIDC with no stored secret), add `id-token: write` to the job permissions and set both `server-url` and `server-audience`:

```yaml
    permissions:
      contents: read
      security-events: write
      id-token: write # request a GitHub OIDC token for the control plane
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: ipsofacto-io/ipso-action@<commit-sha> # pin a full commit SHA
        with:
          command: plan
          args: plan.json
          server-url: https://ipso.example.com
          server-audience: https://ipso.example.com/ci
```

### Upload behavior

- **Runs on pass and fail:** The upload executes after the check and artifact upload, even if the check failed.
- **Identity comes from GitHub OIDC:** Tenant, repository, commit, and run metadata come strictly from GitHub's signed OIDC token. The repository's GitHub App installation must already be bound to a tenant (otherwise the server returns `403`).
- **Non-blocking by default:** Upload failures (missing `id-token: write`, unreachable server, or non-200/201 response) log a warning and retry a few times without overriding the check's pass/fail exit code.
- **Strict config validation:** A non-HTTPS `server-url`, or setting only one of `server-url` / `server-audience`, fails the action immediately.
- **Fork pull requests:** Pull requests from forks receive no OIDC token, so the action automatically skips the control-plane upload.

## What leaves the runner

- **GitHub Code Scanning (SARIF):** Uploaded to the same repository. The SARIF output excludes plan values, resource addresses, and engine messages.
- **Workflow evidence artifact:** Contains the SARIF file and the verdict report (hashes and verdict counts only). Stays within the workflow run.
- **Control plane (only when `server-url` is set):** Sends the verdict report (hashes and verdict counts), the command name, and the SHA-256 of the SARIF file, authenticated with the GitHub OIDC token. Neither the SARIF file nor any plan values, resource addresses, or violation messages are sent.
- **Default offline mode (no `server-url`):** Makes no calls to any ipso service and needs no secrets; it only fetches the `ipso` release archive and its attestation from GitHub.

Note: the runner console log still prints resource addresses and engine messages, so keep that in mind in public repositories.

## Permissions and fork pull requests

- Required job permissions: `contents: read` and `security-events: write` (plus `id-token: write` if uploading to a control plane).
- Pull requests from forks run with a read-only token and no OIDC token, so the action skips both SARIF and control-plane uploads while keeping the evidence artifact.

## Runner requirements

- **OS and architecture:** Linux or macOS on `x64` or `arm64`.
- **Base tools (pre-installed on GitHub-hosted runners):** `bash`, `curl`, `gh` CLI, and `jq` (when uploading to a control plane).
- **Check engines:** This action does not install third-party scanners or engines.
  - `plan`, `ci`, `checkov`, `pulumi`, `cloudformation`, and `arm` need no extra binaries.
  - `snyk`, `wiz`, `sonarqube`, and `dependabot` read an evidence file generated earlier in the job. Because the default `ipso` `0.4.0` release predates these commands, set `version` or `cli-path` to a newer build.
  - All other commands require their pinned engine binary on `PATH` (see the [ipso README](https://github.com/ipsofacto-io/ipso#commands)).

## How the CLI binary is verified

Before executing `ipso`, the action downloads the release archive and runs `gh attestation verify` against it. The build provenance attestation must match:

- Repository: `ipsofacto-io/ipso`
- Workflow: the release workflow in `ipsofacto-io/.github`
- Tag: the requested release version

If verification fails, the step exits before running the binary. Setting `cli-path` bypasses this check, so only point it at a binary your workflow built or trusts.

## Publishing a release (maintainers)

GitHub has no API for Marketplace listings, so a maintainer accepts the Marketplace agreement once in the browser:

1. Publish the `ipso` release that this action defaults to.
2. Draft a GitHub Release in this repository from a `vX.Y.Z` tag, check **Publish this Action to the GitHub Marketplace**, and select the categories.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE).

Copyright 2026 Luca Bertelli.

## Contributing

Follow the contributor guidelines in [ipsofacto-io/.github](https://github.com/ipsofacto-io/.github/blob/main/CONTRIBUTING.md). All commits require a `Signed-off-by` trailer (`git commit -s`).
