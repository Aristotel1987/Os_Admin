from http.server import BaseHTTPRequestHandler, HTTPServer
import os, socket, datetime
NAME = os.environ.get("APP_NAME", socket.gethostname())

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"backend={NAME} host={socket.gethostname()} time={datetime.datetime.utcnow().isoformat()}Z\n"
        self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, fmt, *args): return

HTTPServer(("0.0.0.0", int(os.environ.get("PORT","8080"))), H).serve_forever()
