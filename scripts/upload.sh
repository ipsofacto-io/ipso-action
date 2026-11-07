#!/usr/bin/env bash
# Uploads the verdict report of one check to an ipso control plane (ADR-0102, ADR-0105). It
# runs after the check step and after the evidence uploads, and only when the workflow names
# a server. The body is the report, the name of the command, and the SHA-256 of the SARIF file.
# The SARIF file itself never leaves the runner. The step asks GitHub for an OIDC token for the
# audience of the server, which is the only credential, and nothing in the body names a tenant,
# a repository, or a run. An input that cannot be right fails the step. A failed upload only
# warns, so the result of the action stays the result of the check. Inputs arrive in the
# environment and are never evaluated, and nothing the server sends reaches a workflow command
# except a status number and a short word from a closed pattern.
set -euo pipefail
umask 077

fail() {
  echo "::error::$1" >&2
  exit 2
}

# Prints a warning and ends the step successfully, so the result of the action stays the check's.
give_up() {
  echo "::warning::$1" >&2
  exit 0
}

[[ -n "${IPSO_SERVER_URL}" && -n "${IPSO_SERVER_AUDIENCE}" ]] ||
  fail "server-url and server-audience go together, set both or neither"
[[ "${IPSO_SERVER_URL}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] ||
  fail "server-url must look like https://host, https://host:port, or https://host/path"
[[ "${IPSO_SERVER_AUDIENCE}" =~ ^[\ -~]{1,255}$ ]] ||
  fail "server-audience must be 1 to 255 printable ASCII characters"
[[ "${IPSO_COMMAND}" =~ ^[a-z]{1,32}$ ]] || fail "the command is not a check name"
[[ -f "${IPSO_REPORT}" ]] || fail "there is no report to upload"
server="${IPSO_SERVER_URL%/}"

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  give_up "the report was not uploaded, because the job has no OIDC token: give it id-token: write"
fi

work="$(mktemp -d "${RUNNER_TEMP}/ipso-upload.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

digest=""
if [[ -n "${IPSO_SARIF}" && -f "${IPSO_SARIF}" ]]; then
  if command -v sha256sum >/dev/null; then
    digest="$(sha256sum "${IPSO_SARIF}")"
  else
    digest="$(shasum -a 256 "${IPSO_SARIF}")"
  fi
  digest="${digest%% *}"
fi

# jq reads the report as data. A report that is not JSON is an upload that did not happen.
jq -n --arg check "${IPSO_COMMAND}" --arg sarif "${digest}" --slurpfile report "${IPSO_REPORT}" \
  '{check: $check, report: $report[0]} + (if $sarif == "" then {} else {sarif_sha256: $sarif} end)' \
  >"${work}/body.json" 2>/dev/null || give_up "the report was not uploaded, because the report file is not JSON"

# Neither token is ever put on a command line: curl reads each header file, which only this user can read.
audience="$(jq -rn --arg audience "${IPSO_SERVER_AUDIENCE}" '$audience | @uri')"
printf 'Authorization: bearer %s\n' "${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" >"${work}/request-headers"
status="$(curl --silent --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 --retry 3 \
  --header "@${work}/request-headers" --output "${work}/token.json" --write-out '%{http_code}' \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience}")" || status=000
[[ "${status}" == "200" ]] || give_up "the report was not uploaded, because GitHub gave no OIDC token (status ${status})"

token="$(jq -er '.value' "${work}/token.json" 2>/dev/null)" || token=""
[[ "${token}" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] ||
  give_up "the report was not uploaded, because GitHub gave no OIDC token"
echo "::add-mask::${token}"
printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "${token}" >"${work}/upload-headers"

# No redirect is followed, so the token goes to the server named in the workflow and nowhere else.
# A retry is safe, because the server stores one upload for the same run, attempt, and content.
status="$(curl --silent --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 \
  --retry 3 --retry-connrefused --request POST --header "@${work}/upload-headers" \
  --data-binary "@${work}/body.json" --output "${work}/answer.json" --write-out '%{http_code}' \
  "${server}/v1/verdicts")" || status=000

case "${status}" in
  000) give_up "the report was not uploaded, because the server could not be reached" ;;
  200 | 201)
    id="$(jq -er '.id' "${work}/answer.json" 2>/dev/null)" || id=""
    [[ "${id}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
      give_up "the server answered ${status} without an upload id"
    echo "uploaded the verdict report (status ${status})"
    echo "upload-id=${id}" >>"${GITHUB_OUTPUT}"
    ;;
  *)
    reason="$(jq -er '.error' "${work}/answer.json" 2>/dev/null)" || reason=""
    [[ "${reason}" =~ ^[a-z\ ]{1,40}$ ]] || reason="no reason"
    give_up "the report was not uploaded: the server answered ${status} (${reason})"
    ;;
esac
