# ipso-action

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ipsofacto-io/ipso-action/badge)](https://scorecard.dev/viewer/?uri=github.com/ipsofacto-io/ipso-action)

GitHub Action that runs ipso decision checks in CI, uploads SARIF to code scanning, and keeps the evidence as a workflow artifact.

> Status: the action works and is tested on every pull request. It installs and verifies ipso v0.3.0 by default. It is not on GitHub Marketplace yet, so pin a commit SHA of this repository.

## Usage

Run ipso from the root of the checkout, because SARIF locations are relative to it.

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
      security-events: write # upload the SARIF file to code scanning
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # terraform plan -out p && terraform show -json p > plan.json
      - uses: ipsofacto-io/ipso-action@<commit-sha> # pin a full commit SHA
        with:
          command: plan
          args: plan.json
          env: prod
```

The action runs `ipso check`, then `ipso compile`, then `ipso check <command> <args> --report <file> --sarif <file>`. The first command that fails stops the run. The uploads still run for whatever was written, and then the step fails. With `--bundle` in `args`, the compile step is skipped, because a signed bundle replaces the local build.

On a pull request the decisions come from the pull request's own checkout, so its author can edit a decision along with the change it governs. Protect `docs/decisions` with `CODEOWNERS`, or evaluate a signed bundle with `plan --bundle`, when that matters.

`ipsofacto-io/examples` holds a working sample of this workflow.

## Inputs

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `command` | Yes | | The engine check: `plan`, `ci`, `checkov`, `depcruise`, `semgrep`, `archunit`, `importlinter`, `kyverno`, `gatekeeper`, or `eslint` |
| `args` | No | | Arguments of that check. They are split on whitespace and no shell expands them, so a path cannot hold a space. `--report`, `--sarif`, `--env`, and `--input` are refused here |
| `env` | No | | Passed as `--env` |
| `input` | No | | Passed as `--input`. `ci` does not take it |
| `version` | No | `0.3.0` | The ipso release to install, without the leading `v` |
| `cli-path` | No | | Path of an ipso binary already on the runner. The action then installs and verifies nothing |
| `upload-sarif` | No | `true` | Set it to `false` in a private repository without code scanning |

`env` and `input` name the SARIF category, so runs over different inputs do not close each other's alerts. Use one step per named run.

## Outputs

| Output | Meaning |
| --- | --- |
| `exit-code` | Exit code of the check |
| `sarif` | Path of the SARIF file, empty when none was written |
| `report` | Path of the verdict report, empty when none was written |
| `evidence-name` | Name of the evidence artifact, empty when there was nothing to upload |

## What leaves the runner

- The SARIF file goes to the code scanning of the same repository. The SARIF contract keeps plan values, resource addresses, and engine messages out of it.
- The evidence artifact holds that SARIF file and the verdict report, which carries hashes and verdict counts. It stays in the same workflow run.
- The action calls no ipso service and needs no secret. It reads the release archive and its attestation from GitHub.

The runner log still prints resource addresses and engine messages, so read a public repository's log with that in mind.

## Permissions and pull requests from forks

The job needs `contents: read` and `security-events: write`. A pull request from a fork gets a read-only token, so the action skips the code scanning upload there and keeps the artifact.

## Runner requirements

Linux or macOS, on X64 or ARM64, with `bash`, `curl`, and the `gh` CLI. GitHub-hosted runners have all of them. The action does not install engines: `plan`, `ci`, and `checkov` need nothing more, and the other commands need their pinned engine on `PATH`, as the [ipso README](https://github.com/ipsofacto-io/ipso#commands) describes.

## How the CLI is verified

The action downloads the release archive and runs `gh attestation verify` on it. The attestation has to name `ipsofacto-io/ipso`, the release workflow in `ipsofacto-io/.github`, and the tag of the requested version. Otherwise the step fails before the binary runs. `cli-path` skips this, so point it only at a binary your workflow built or trusts.

## Publishing a release

GitHub has no API for a Marketplace listing, and a maintainer accepts its agreement once in the browser.

1. Publish the ipso release this action defaults to.
2. Draft a release of this repository from a `vX.Y.Z` tag, select "Publish this Action to the GitHub Marketplace", and pick the categories.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE).

Copyright 2026 Luca Bertelli.

## Contributing

Follow the contributor terms in [ipsofacto-io/.github](https://github.com/ipsofacto-io/.github/blob/main/CONTRIBUTING.md). Commits need a `Signed-off-by` trailer (`git commit -s`).
