#!/usr/bin/env bash
# Starts server.py in the background on 127.0.0.1:8443 with a certificate made for this run, and
# appends to GITHUB_ENV where it keeps its records (VERDICT_SERVER_DIR) and the CA bundle that
# trusts it (VERDICT_CA_BUNDLE). The bundle holds the system roots too, because the upload
# step asks GitHub for its token through the same curl.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$(mktemp -d "${RUNNER_TEMP}/verdict-server.XXXXXX")"

cat >"${dir}/openssl.cnf" <<'CONF'
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = 127.0.0.1
[extensions]
subjectAltName = IP:127.0.0.1,DNS:localhost
extendedKeyUsage = serverAuth
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "${dir}/openssl.cnf" \
  -keyout "${dir}/key.pem" -out "${dir}/cert.pem" 2>/dev/null

for roots in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
  [[ -f "${roots}" ]] && break
done
cat "${roots}" "${dir}/cert.pem" >"${dir}/ca.pem"

nohup python3 "${here}/server.py" "${dir}" "${dir}/cert.pem" "${dir}/key.pem" 8443 \
  >"${dir}/server.log" 2>&1 &

for _ in $(seq 50); do
  [[ -f "${dir}/ready" ]] && break
  sleep 0.2
done
[[ -f "${dir}/ready" ]] || {
  cat "${dir}/server.log" >&2
  exit 1
}

{
  echo "VERDICT_SERVER_DIR=${dir}"
  echo "VERDICT_CA_BUNDLE=${dir}/ca.pem"
} >>"${GITHUB_ENV}"
