#!/usr/bin/env bash
# Validates the decision files, compiles them, runs one engine check, and records where the
# files went. It exits 0 when the check fails, so the upload steps run. It exits non-zero only
# when the inputs are unusable, and the action's last step then fails on the missing exit code.
# Inputs arrive in the environment and are never evaluated, and no input reaches a workflow
# command or GITHUB_OUTPUT except through the name filter below.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 2
}

[[ -x "${IPSO_BIN}" ]] || fail "the ipso binary is missing or not executable"

case "${IPSO_COMMAND}" in
  plan | ci | checkov | depcruise | semgrep | archunit | importlinter | kyverno | gatekeeper | eslint) ;;
  *) fail "command must be plan, ci, checkov, depcruise, semgrep, archunit, importlinter, kyverno, gatekeeper, or eslint" ;;
esac

args=()
if [[ -n "${IPSO_ARGS}" ]]; then
  # With no delimiter read reaches end of input and returns 1, which is expected here.
  read -r -d '' -a args <<<"${IPSO_ARGS}" || true
fi
compile=true
for arg in ${args[@]+"${args[@]}"}; do
  case "${arg}" in
    --report | --report=* | --sarif | --sarif=*)
      fail "args cannot set --report or --sarif, the action writes those files"
      ;;
    --env | --env=* | --input | --input=*)
      fail "args cannot set --env or --input, use the env and input inputs"
      ;;
    # A signed bundle replaces .ipso/build, so the working tree's decisions are not compiled.
    --bundle | --bundle=*) compile=false ;;
  esac
done

evidence="$(mktemp -d "${RUNNER_TEMP}/ipso-evidence.XXXXXX")"
report="${evidence}/report.json"
sarif="${evidence}/ipso.sarif"

flags=(--report "${report}" --sarif "${sarif}")
name="${IPSO_COMMAND}"
if [[ -n "${IPSO_ENV}" ]]; then
  flags+=(--env "${IPSO_ENV}")
  name+="-${IPSO_ENV}"
fi
if [[ -n "${IPSO_INPUT}" ]]; then
  flags+=(--input "${IPSO_INPUT}")
  name+="-${IPSO_INPUT}"
fi

# ipso and the engines print repository text, such as file names. The runner must not read a
# line of that text as a workflow command, so command processing is off while they run.
resume="$(LC_ALL=C od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
echo "::stop-commands::${resume}"

code=0
"${IPSO_BIN}" check || code=$?
if [[ "${code}" -eq 0 && "${compile}" == "true" ]]; then
  "${IPSO_BIN}" compile || code=$?
fi
if [[ "${code}" -eq 0 ]]; then
  "${IPSO_BIN}" check "${IPSO_COMMAND}" ${args[@]+"${args[@]}"} "${flags[@]}" || code=$?
fi

echo "::${resume}::"

{
  echo "exit-code=${code}"
  [[ -f "${report}" ]] && echo "report=${report}"
  [[ -f "${sarif}" ]] && echo "sarif=${sarif}"
  if [[ -f "${report}" || -f "${sarif}" ]]; then
    # An artifact name is unique in a run, so it names the job, the matrix leg, and the attempt.
    # A filtered env or input name cannot add a character an artifact name or GITHUB_OUTPUT refuses.
    artifact="ipso-evidence-${GITHUB_JOB}-${name}-${IPSO_JOB_INDEX:-0}-${GITHUB_RUN_ATTEMPT}"
    echo "evidence-name=${artifact//[^A-Za-z0-9._-]/_}"
    echo "evidence-dir=${evidence}"
  fi
} >>"${GITHUB_OUTPUT}"
