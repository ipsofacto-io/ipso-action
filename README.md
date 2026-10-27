# ipso-action

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ipsofacto-io/ipso-action/badge)](https://scorecard.dev/viewer/?uri=github.com/ipsofacto-io/ipso-action)

GitHub Action that runs ipso decision checks in CI and uploads SARIF results.

> Status: skeleton. The composite action lands in a later change, once a released CLI exists to download.

GitHub Marketplace requires an action at the root of its own repository. `action.yml` will be a composite action that downloads a released `ipso` binary and runs the check. Source for the CLI stays in the `ipso` repository.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE).

Copyright 2026 Luca Bertelli.

## Contributing

Follow the contributor terms in [ipsofacto-io/.github](https://github.com/ipsofacto-io/.github/blob/main/CONTRIBUTING.md). Commits need a `Signed-off-by` trailer (`git commit -s`).
