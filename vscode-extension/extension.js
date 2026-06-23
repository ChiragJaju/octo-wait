// Oswald — While You Wait : VSCode extension
// -------------------------------------------
// Responsibilities:
//   1. (optionally) run the same control server the Claude Code plugin talks to.
//   2. Show a webview panel that displays the player (pointing at that server).
//   3. Offer manual Play/Pause/Toggle commands for when you're NOT driving it
//      from Claude Code hooks.
//
// The "is the AI working?" detection lives in the Claude Code plugin's hooks,
// which POST /play and /pause to the very same server. This extension is the
// screen; the plugin is the brain. They share state through localhost:<port>.

const vscode = require('vscode');
const http = require('http');
const path = require('path');
const cp = require('child_process');

let serverProc = null;
let panel = null;

function cfg() {
  const c = vscode.workspace.getConfiguration('oswald');
  return {
    port: c.get('port', 8730),
    playlistId: c.get('playlistId', 'PLJOUQWZHQRPvbWKl4YgrEcs7kazppKoFR'),
    autostartServer: c.get('autostartServer', true),
    autoShowPanel: c.get('autoShowPanel', false),
  };
}

function baseUrl() {
  return `http://127.0.0.1:${cfg().port}`;
}

// --- tiny HTTP helpers (no deps) -------------------------------------------
function httpGet(url) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, { timeout: 800 }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
  });
}

function httpPost(pathName) {
  return new Promise((resolve, reject) => {
    const { port } = cfg();
    const req = http.request(
      { host: '127.0.0.1', port, path: pathName, method: 'POST', timeout: 800 },
      (res) => {
        let d = '';
        res.on('data', (c) => (d += c));
        res.on('end', () => resolve({ status: res.statusCode, body: d }));
      }
    );
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.end();
  });
}

async function serverUp() {
  try {
    const r = await httpGet(`${baseUrl()}/health`);
    return r.status === 200;
  } catch (_) {
    return false;
  }
}

// --- control server ---------------------------------------------------------
async function startServer(context) {
  if (await serverUp()) return true; // already running (maybe from the plugin)
  const serverJs = context.asAbsolutePath(path.join('media', 'server.js'));
  const { port, playlistId } = cfg();
  serverProc = cp.spawn(process.execPath, [serverJs], {
    env: Object.assign({}, process.env, {
      OSWALD_PORT: String(port),
      OSWALD_PLAYLIST: playlistId,
      OSWALD_OPEN_BROWSER: '0', // we display it in the webview, not a browser tab
    }),
    detached: false,
    stdio: 'ignore',
  });
  serverProc.on('exit', () => { serverProc = null; });
  // give it a moment to bind
  for (let i = 0; i < 15; i++) {
    if (await serverUp()) return true;
    await new Promise((r) => setTimeout(r, 150));
  }
  return serverUp();
}

function stopServer() {
  if (serverProc) {
    try { serverProc.kill(); } catch (_) {}
    serverProc = null;
  }
}

// --- webview panel ----------------------------------------------------------
function showPanel(context) {
  const { port } = cfg();
  if (panel) {
    panel.reveal(vscode.ViewColumn.Beside);
    return;
  }
  panel = vscode.window.createWebviewPanel(
    'oswaldPlayer',
    '🐙 Oswald',
    { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
    {
      enableScripts: true,
      retainContextWhenHidden: true, // keep playing when the tab is in the background
    }
  );
  panel.onDidDispose(() => { panel = null; });

  const src = `http://127.0.0.1:${port}/`;
  // The panel just frames the localhost player page. CSP must allow framing it.
  panel.webview.html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline';
               frame-src http://127.0.0.1:${port} http://localhost:${port};" />
<style>
  html,body { margin:0; padding:0; height:100%; background:#0b1020; }
  iframe { border:0; width:100%; height:100vh; display:block; }
</style>
</head>
<body>
  <iframe src="${src}" allow="autoplay; encrypted-media; fullscreen"></iframe>
</body>
</html>`;
}

// --- activation -------------------------------------------------------------
async function activate(context) {
  const c = cfg();

  if (c.autostartServer) {
    startServer(context).then((ok) => {
      if (ok && c.autoShowPanel) showPanel(context);
    });
  }

  const reg = (id, fn) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));

  reg('oswald.show', async () => {
    const ok = await startServer(context);
    if (!ok) {
      vscode.window.showErrorMessage('Oswald: could not start the control server (is Node available?).');
      return;
    }
    showPanel(context);
  });

  reg('oswald.startServer', async () => {
    const ok = await startServer(context);
    vscode.window.showInformationMessage(
      ok ? `Oswald control server running on ${baseUrl()}` : 'Oswald: failed to start server.'
    );
  });

  reg('oswald.stopServer', () => {
    stopServer();
    vscode.window.showInformationMessage('Oswald control server stopped.');
  });

  reg('oswald.play', async () => {
    try { await httpPost('/play'); } catch (_) {
      vscode.window.showWarningMessage('Oswald: server not reachable.');
    }
  });

  reg('oswald.pause', async () => {
    try { await httpPost('/pause'); } catch (_) {
      vscode.window.showWarningMessage('Oswald: server not reachable.');
    }
  });

  reg('oswald.toggle', async () => {
    try { await httpPost('/toggle'); } catch (_) {
      vscode.window.showWarningMessage('Oswald: server not reachable.');
    }
  });
}

function deactivate() {
  stopServer();
}

module.exports = { activate, deactivate };
