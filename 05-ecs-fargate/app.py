"""Small container networking demo; no AWS SDK or credentials required."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json

PAGE = b"""<!doctype html><html lang="en"><meta charset="utf-8">
<title>ECS container lab</title><style>
body{background:#101c28;color:#e8f1f5;font:20px system-ui;max-width:850px;margin:12vh auto;padding:24px}
h1{font-size:52px}a{color:#76d9ba}section{border:1px solid #385066;padding:24px;border-radius:12px}
</style><h1>Running on ECS Fargate</h1>
<p>A Python application packaged with Docker and deployed using Terraform.</p>
<section><p>Image registry: Amazon ECR</p><p>Compute: ECS Fargate</p>
<p>Application logs: CloudWatch</p><a href="/health">Check application health</a></section></html>"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            status, kind, body = 200, "text/html; charset=utf-8", PAGE
        elif self.path == "/health":
            status, kind, body = 200, "application/json", json.dumps({"status": "ok", "service": "ecs-lab"}).encode()
        else:
            status, kind, body = 404, "application/json", b'{"error":"not found"}'
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    print("Container listening on port 8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
