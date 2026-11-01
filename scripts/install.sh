#!/usr/bin/env bash
# Installs one ipso release into a new directory under RUNNER_TEMP and prints its path to
# GITHUB_OUTPUT. The archive runs only after its build attestation verifies, so a replaced
# release asset, or an older signed asset under a newer tag, is refused.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

[[ "${IPSO_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3"

case "${RUNNER_OS}/${RUNNER_ARCH}" in
  Linux/X64) platform=linux_amd64 ;;
  Linux/ARM64) platform=linux_arm64 ;;
  macOS/X64) platform=darwin_amd64 ;;
  macOS/ARM64) platform=darwin_arm64 ;;
  *) fail "ipso-action runs on Linux and macOS, on X64 and ARM64" ;;
esac

command -v gh >/dev/null || fail "ipso-action needs the gh CLI to verify the release"

archive="ipso_${IPSO_VERSION}_${platform}.tar.gz"
directory="$(mktemp -d "${RUNNER_TEMP}/ipso-install.XXXXXX")"

curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
  --output "${directory}/${archive}" \
  "https://github.com/ipsofacto-io/ipso/releases/download/v${IPSO_VERSION}/${archive}"

gh attestation verify "${directory}/${archive}" \
  --repo ipsofacto-io/ipso \
  --signer-workflow ipsofacto-io/.github/.github/workflows/release-cli.yml \
  --source-ref "refs/tags/v${IPSO_VERSION}"

tar --extract --gzip --file "${directory}/${archive}" --directory "${directory}" ipso
chmod 0755 "${directory}/ipso"
rm "${directory}/${archive}"

echo "path=${directory}/ipso" >>"${GITHUB_OUTPUT}"
