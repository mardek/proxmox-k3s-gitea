import html
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

DATA = Path(os.environ.get('DATA_DIR', '/data'))
DATA.mkdir(parents=True, exist_ok=True)
SAFE_NAME = re.compile(r'^[a-zA-Z0-9_.-]+$')


def load_metrics():
    records = []
    for path in sorted((DATA / 'metrics').glob('*.json')):
        try:
            records.append(json.loads(path.read_text()))
        except (OSError, ValueError):
            continue
    return records


def index():
    records = load_metrics()
    rows = []
    for record in reversed(records):
        worker = html.escape(record.get('worker', 'unknown'))
        build = html.escape(record.get('build_id', 'unknown'))
        version = html.escape(record.get('ruby_version', 'unknown'))
        status = html.escape(record.get('status', 'unknown'))
        stages = record.get('stages', {})
        compile_seconds = stages.get('compile', {}).get('seconds', 0)
        test_seconds = stages.get('test', {}).get('seconds', 0)
        rows.append(
            f'<tr><td>{worker}</td><td>{version}</td><td>{status}</td>'
            f'<td>{compile_seconds:.1f} s</td><td>{test_seconds:.1f} s</td>'
            f'<td><a href="/reports/{worker}.html">{build}</a></td></tr>'
        )
    body = ''.join(rows) or '<tr><td colspan="6">Waiting for the first build.</td></tr>'
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<meta http-equiv="refresh" content="30"><title>Ruby Forge — Build metrics</title><style>
*{{box-sizing:border-box}}body{{font:16px system-ui,sans-serif;max-width:1200px;margin:40px auto;padding:0 20px;color:#172033;background:#f5f7fa}}
main{{background:white;padding:32px;border-top:3px solid #c51f3a;box-shadow:0 8px 30px #1720330d}}
.brand{{display:flex;align-items:center;gap:16px;padding-bottom:24px;border-bottom:1px solid #e5e9f0;margin-bottom:24px}}
.logo{{width:56px;height:56px;flex:none}}h1{{font-size:26px;line-height:1.1;margin:0 0 6px;letter-spacing:-.5px}}
.eyebrow{{display:block;color:#a3162d;font-size:11px;font-weight:700;letter-spacing:1.8px;text-transform:uppercase;margin-bottom:7px}}
.tagline{{margin:0;color:#65728a;font-size:14px}}p{{color:#4c596f}}
table{{border-collapse:collapse;width:100%}}td,th{{padding:12px;text-align:left}}th{{background:#e9edf3}}
tr:nth-child(even){{background:#fafbfd}}a{{color:#2457c5}}small{{display:block;margin-top:20px;color:#65728a}}
</style></head><body><main><header class="brand">
<svg class="logo" viewBox="0 0 64 64" role="img" aria-label="Ruby Forge logo">
<path fill="#c51f3a" d="M12 18 23 6h18l11 12-20 40Z"/><path fill="#ed5a70" d="m12 18 20 8 20-8-20 40Z"/>
<path fill="#9e1228" d="m12 18 20 8-9 17Z"/><path fill="#db344d" d="m32 26 20-8-11 25Z"/>
<path fill="#ff9dac" d="M23 6l-3 12 12 8-2-20Zm18 0 3 12-12 8 2-20Z"/>
<path fill="none" stroke="#fff" stroke-opacity=".65" d="m12 18 8 0 10-12 12 12h10M20 18l12 8 12-8M32 26v32"/>
</svg><div><span class="eyebrow">Gentoo build lab</span><h1>Ruby Forge</h1><p class="tagline">Build metrics &amp; release reports</p></div></header>
<p>Three K3s workers building Ruby from source. This page refreshes every 30 seconds.</p>
<table><tr><th>Worker</th><th>Ruby</th><th>Status</th><th>Compile</th><th>Tests</th><th>Report</th></tr>{body}</table>
<small>Metrics and reports are stored on a Longhorn persistent volume.</small>
</main></body></html>'''.encode()


class Handler(BaseHTTPRequestHandler):
    def send_content(self, content, content_type='text/html; charset=utf-8', status=200):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        path = unquote(self.path)
        if path == '/':
            self.send_content(index())
            return
        match = re.fullmatch(r'/(reports|metrics)/([a-zA-Z0-9_.-]+)', path)
        if match:
            name = match.group(2)
            if SAFE_NAME.fullmatch(name):
                file = DATA / match.group(1) / name
                if file.is_file():
                    content_type = 'application/json' if name.endswith('.json') else 'text/html; charset=utf-8'
                    self.send_content(file.read_bytes(), content_type)
                    return
        self.send_content(b'Not found', 'text/plain; charset=utf-8', 404)

    def do_PUT(self):
        match = re.fullmatch(r'/(reports|metrics)/([a-zA-Z0-9_.-]+)', unquote(self.path))
        if not match or not SAFE_NAME.fullmatch(match.group(2)):
            self.send_content(b'Invalid path', 'text/plain; charset=utf-8', 400)
            return
        length = int(self.headers.get('Content-Length', '0'))
        if length < 1 or length > 10 * 1024 * 1024:
            self.send_content(b'Invalid content length', 'text/plain; charset=utf-8', 400)
            return
        directory = DATA / match.group(1)
        directory.mkdir(parents=True, exist_ok=True)
        (directory / match.group(2)).write_bytes(self.rfile.read(length))
        self.send_content(b'Stored', 'text/plain; charset=utf-8', 201)

    def log_message(self, format, *args):
        print(format % args, flush=True)


ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
