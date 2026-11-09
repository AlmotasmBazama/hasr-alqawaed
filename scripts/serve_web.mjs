// Serve only the compiled Flutter release, never the project/source directory.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = fs.realpathSync(path.join(project, 'build', 'web'));
if (!fs.existsSync(path.join(root, 'index.html'))) {
  throw new Error('Run flutter build web --release before starting this server.');
}
const port = Number(process.env.HASR_PREVIEW_PORT || 0);
const mime = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.pdf': 'application/pdf',
};
const inside = (file) => file === root || file.startsWith(root + path.sep);
const server = http.createServer(async (req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { Allow: 'GET, HEAD' }).end(); return;
  }
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
    let candidate = path.resolve(root, '.' + pathname);
    if (!inside(candidate)) { res.writeHead(403).end(); return; }
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      candidate = path.join(candidate, 'index.html');
    }
    if (!fs.existsSync(candidate)) {
      if (path.extname(candidate)) { res.writeHead(404).end(); return; }
      candidate = path.join(root, 'index.html');
    }
    candidate = fs.realpathSync(candidate);
    if (!inside(candidate) || !fs.statSync(candidate).isFile()) {
      res.writeHead(403).end(); return;
    }
    res.writeHead(200, {
      'Content-Type': mime[path.extname(candidate)] || 'application/octet-stream',
      'Content-Length': fs.statSync(candidate).size,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(candidate).pipe(res);
  } catch {
    if (!res.headersSent) { res.writeHead(400); }
    res.end();
  }
});
server.listen(port, '127.0.0.1', () => {
  console.log(JSON.stringify({ pid: process.pid, root, url: `http://127.0.0.1:${server.address().port}` }));
});
