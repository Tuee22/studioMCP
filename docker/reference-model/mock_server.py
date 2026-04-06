import json
from http.server import BaseHTTPRequestHandler, HTTPServer


ADVISORY_TEXT = (
    "ADVISORY: upload media through /api, then submit workflow runs through "
    "/api/v1/runs and monitor status via /api/v1/runs/:runId/status."
)


class Handler(BaseHTTPRequestHandler):
    def _write_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._write_json(200, {"status": "ready"})
            return
        self._write_json(404, {"error": "not-found"})

    def do_POST(self):
        if self.path != "/generate":
            self._write_json(404, {"error": "not-found"})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length:
            self.rfile.read(content_length)

        self._write_json(200, {"response": ADVISORY_TEXT})

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
