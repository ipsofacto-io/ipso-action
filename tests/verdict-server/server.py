#!/usr/bin/env python3
"""A stand-in for POST /v1/verdicts of ipso-server (ADR-0102), for the action's own tests.

usage: server.py DIRECTORY CERTIFICATE KEY PORT

It serves HTTPS on 127.0.0.1, writes DIRECTORY/ready once it listens, and appends one JSON line
to DIRECTORY/requests.jsonl for each POST: the path, the status and body of the answer, the
content type, the parsed body, and the claims of the bearer token (never the token itself). It
answers:

  POST /v1/verdicts        201 with a new upload id, 401 without a bearer token
  POST /down/v1/verdicts   503 with Retry-After: 1, the way an unavailable server answers

It checks the token for presence only. What the real server checks is ADR-0102's, in ipso-server.
"""

import base64
import http.server
import json
import ssl
import sys
import threading
import uuid
from pathlib import Path

CLAIMS = ("iss", "aud", "repository", "run_id", "run_attempt", "workflow_ref")


def claims_of(header):
    scheme, _, token = (header or "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    try:
        part = token.split(".")[1]
        payload = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    except (IndexError, ValueError):
        return {}
    return {name: payload.get(name) for name in CLAIMS}


def make_handler(directory):
    log = directory / "requests.jsonl"
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def answer(self, status, body, headers=()):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            for name, value in headers:
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            claims = claims_of(self.headers.get("Authorization"))
            try:
                body = json.loads(raw)
            except ValueError:
                body = None

            headers = ()
            if self.path == "/v1/verdicts" and claims is None:
                status, answer = 401, {"error": "unauthorized"}
            elif self.path == "/v1/verdicts" and not isinstance(body, dict):
                status, answer = 400, {"error": "invalid query"}
            elif self.path == "/v1/verdicts":
                verdicts = body.get("report", {}).get("verdicts", [])
                status, answer = 201, {"id": str(uuid.uuid4()), "verdicts": len(verdicts)}
            elif self.path == "/down/v1/verdicts":
                status, answer, headers = 503, {"error": "unavailable"}, (("Retry-After", "1"),)
            else:
                status, answer = 404, {"error": "not found"}

            record = {
                "path": self.path,
                "status": status,
                "content_type": self.headers.get("Content-Type"),
                "claims": claims,
                "body": body,
                "answer": answer,
            }
            with lock, log.open("a") as out:
                out.write(json.dumps(record, sort_keys=True) + "\n")
            self.answer(status, answer, headers)

    return Handler


def main():
    directory, certificate, key, port = Path(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4])
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certificate, key)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), make_handler(directory))
    server.socket = context.wrap_socket(server.socket, server_side=True)
    (directory / "ready").write_text("ready\n")
    server.serve_forever()


if __name__ == "__main__":
    main()
