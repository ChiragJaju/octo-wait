#!/usr/bin/env node
/*
 * Oswald-While-You-Wait — control server
 * --------------------------------------
 * A tiny, dependency-free HTTP server that is the single source of truth for:
 *   - playing:  whether the AI is currently "working" (true) or idle (false)
 *   - resume:   { index, time } — which playlist video and how far in, so we
 *               can continue exactly where we left off.
 *
 * It serves the YouTube IFrame player page and exposes a small control API that
 * Claude Code hooks (or the VSCode extension) POST to.
 *
 * No npm install required — uses only Node's standard library.
 */

'use strict';

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ---- Configuration (all overridable via env) -------------------------------
const PORT = parseInt(process.env.OSWALD_PORT || '8730', 10);
// The Oswald YouTube playlist (just the list ID, not the full URL).
const PLAYLIST_ID = process.env.OSWALD_PLAYLIST || 'PLJOUQWZHQRPvbWKl4YgrEcs7kazppKoFR';
const DATA_DIR =
  process.env.OSWALD_DATA_DIR || path.join(os.homedir(), '.oswald-while-you-wait');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const PUBLIC_DIR = path.join(__dirname, 'public');

// ---- Persistent state ------------------------------------------------------
let state = {
  playing: false,
  resume: { index: 0, time: 0 },
  updatedAt: Date.now(),
};

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      state.resume = {
        index: Number(parsed.resume && parsed.resume.index) || 0,
        time: Number(parsed.resume && parsed.resume.time) || 0,
      };
      // We never persist `playing` as true across restarts — always boot paused.
      state.playing = false;
    }
  } catch (_) {
    /* first run / no file yet — fine */
  }
}

function saveStateNow() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (e) {
    // Non-fatal: resume just won't survive a restart.
  }
}

let saveTimer = null;
function saveStateThrottled() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    saveStateNow();
  }, 1000);
}

// Flush the latest position synchronously when the process is asked to stop,
// so even a full machine restart resumes from the right spot.
['SIGINT', 'SIGTERM'].forEach((sig) => {
  process.on(sig, () => {
    saveStateNow();
    process.exit(0);
  });
});

// ---- Helpers ---------------------------------------------------------------
function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1e6) req.destroy(); // guard against floods
    });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (_) {
        resolve({});
      }
    });
  });
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function serveStatic(res, filePath) {
  fs.readFile(filePath, (err, buf) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    res.end(buf);
  });
}

// ---- Server ----------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  if (req.method === 'OPTIONS') {
    sendJSON(res, 204, {});
    return;
  }

  // --- API ---
  if (pathname === '/health') {
    return sendJSON(res, 200, { ok: true });
  }

  if (pathname === '/config') {
    return sendJSON(res, 200, { playlistId: PLAYLIST_ID, port: PORT });
  }

  if (pathname === '/state') {
    return sendJSON(res, 200, state);
  }

  if (pathname === '/play' && req.method === 'POST') {
    state.playing = true;
    state.updatedAt = Date.now();
    return sendJSON(res, 200, state);
  }

  if (pathname === '/pause' && req.method === 'POST') {
    state.playing = false;
    state.updatedAt = Date.now();
    return sendJSON(res, 200, state);
  }

  if (pathname === '/toggle' && req.method === 'POST') {
    state.playing = !state.playing;
    state.updatedAt = Date.now();
    return sendJSON(res, 200, state);
  }

  // The player page reports its current position so we can resume later.
  if (pathname === '/position' && req.method === 'POST') {
    const body = await readBody(req);
    const index = Number(body.index);
    const time = Number(body.time);
    if (Number.isFinite(index) && index >= 0) state.resume.index = index;
    if (Number.isFinite(time) && time >= 0) state.resume.time = time;
    saveStateThrottled();
    return sendJSON(res, 200, { ok: true, resume: state.resume });
  }

  // --- Static / player page ---
  if (pathname === '/' || pathname === '/index.html') {
    return serveStatic(res, path.join(PUBLIC_DIR, 'player.html'));
  }

  // Any other path: serve from public/ (no traversal).
  const safe = path.normalize(pathname).replace(/^(\.\.[/\\])+/, '');
  return serveStatic(res, path.join(PUBLIC_DIR, safe));
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    // Already running — that's the whole point of "ensure". Exit quietly.
    console.error(`[oswald] server already running on port ${PORT}; exiting.`);
    process.exit(0);
  } else {
    console.error('[oswald] server error:', err);
    process.exit(1);
  }
});

loadState();
server.listen(PORT, '127.0.0.1', () => {
  console.log(`[oswald] control server on http://localhost:${PORT}`);
  console.log(`[oswald] playlist: ${PLAYLIST_ID}`);
  console.log(`[oswald] state file: ${STATE_FILE}`);
});
