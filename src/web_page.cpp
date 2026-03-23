#include "web_page.h"

// ─────────────────────────────────────────────────────────────────────────────
//  CHAT PAGE  (/)
//  Server-side nicknames · scrollable · per-node border colors
// ─────────────────────────────────────────────────────────────────────────────
const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mesh Chat</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; overflow: hidden; }
body {
  background: #000; color: #fff;
  font-family: system-ui, sans-serif;
  display: flex; flex-direction: column; padding: 20px;
}
.container {
  max-width: 600px; width: 100%; margin: 0 auto;
  display: flex; flex-direction: column; height: 100%; min-height: 0;
}
h1 { text-align: center; margin-bottom: 15px; flex-shrink: 0; }
.info {
  display: flex; justify-content: space-between;
  font-size: 13px; opacity: .7; margin-bottom: 12px; flex-shrink: 0;
}
.chat {
  flex: 1; min-height: 0;
  padding: 14px; border-radius: 16px; outline: 1px solid #333;
  display: flex; flex-direction: column; gap: 10px;
  overflow-y: auto; scroll-behavior: smooth;
}
.chat::-webkit-scrollbar        { width: 4px; }
.chat::-webkit-scrollbar-track  { background: transparent; }
.chat::-webkit-scrollbar-thumb  { background: #444; border-radius: 2px; }
.chat::-webkit-scrollbar-thumb:hover { background: #666; }
.msg {
  max-width: 80%; padding: 10px 14px;
  border-radius: 18px; font-size: 14px; word-break: break-word;
}
.me    { align-self: flex-end; background: #fff; color: #000; }
.other { align-self: flex-start; border: 1.5px solid #333; }
.input-row { display: flex; gap: 10px; margin-top: 14px; flex-shrink: 0; }
input {
  flex: 1; padding: 14px; border-radius: 999px;
  border: 1px solid #444; background: #000; color: #fff; font-size: 14px; outline: none;
}
input:focus { border-color: #888; }
button {
  padding: 14px 20px; border-radius: 999px;
  border: 1px solid #fff; background: #fff; color: #000;
  font-weight: 600; cursor: pointer; font-size: 14px;
}
button:active { opacity: .7; }
</style>
</head>
<body>
<div class="container">
  <h1>Mesh Chat</h1>
  <div class="info">
    <div>Node: <span id="nodeId">-</span></div>
    <div>Peers: <span id="nodeCount">-</span></div>
  </div>
  <div class="chat" id="chat"></div>
  <div class="input-row">
    <input id="msg" placeholder="Type message"
           onkeydown="if(event.key==='Enter') send()">
    <button onclick="send()">Send</button>
  </div>
</div>
<script>
(function () {
  var NODE_COLORS = [
    '#4fc3f7','#ce93d8','#ffb74d','#ef9a9a',
    '#80cbc4','#fff176','#f48fb1','#a5d6a7',
    '#ff8a65','#90caf9'
  ];
  var colorMap  = {};   // nodeId -> color
  var nickMap   = {};   // nodeId -> nickname
  var nextColor = 0;
  var rendered  = 0;
  var box       = document.getElementById('chat');

  function colorFor(id) {
    if (!colorMap[id]) { colorMap[id] = NODE_COLORS[nextColor++ % NODE_COLORS.length]; }
    return colorMap[id];
  }

  function displayName(id) { return nickMap[id] || id.substring(0, 6); }

  function isNearBottom() {
    return box.scrollHeight - box.scrollTop - box.clientHeight < 80;
  }

  function send() {
    var inp = document.getElementById('msg');
    var t = inp.value.trim(); if (!t) return;
    fetch('/send?msg=' + encodeURIComponent(t)).catch(function(){});
    inp.value = ''; inp.focus();
  }
  window.send = send;

  function update() {
    fetch('/data')
      .then(function(r) { return r.json(); })
      .then(function(d) {
        // Rebuild nick map from server data
        nickMap = {};
        (d.nicknames || []).forEach(function(n) { nickMap[n.id] = n.nick; });

        var selfNick = nickMap[d.nodeId] || d.nodeId.substring(0, 6);
        document.getElementById('nodeId').textContent    = selfNick;
        document.getElementById('nodeCount').textContent = d.nodeCount;

        var msgs = d.messages || [];
        if (msgs.length <= rendered) return;

        var wasNearBottom = isNearBottom();

        for (var i = rendered; i < msgs.length; i++) {
          var m   = msgs[i];
          var div = document.createElement('div');
          div.className = 'msg ' + (m.me ? 'me' : 'other');
          if (!m.me) {
            div.style.borderColor = colorFor(m.sender);
            div.textContent = displayName(m.sender) + ': ' + m.text;
          } else {
            div.textContent = m.text;
          }
          box.appendChild(div);
        }

        rendered = msgs.length;
        if (wasNearBottom) box.scrollTop = box.scrollHeight;
      })
      .catch(function(){});
  }

  setInterval(update, 1000);
  update();
})();
</script>
</body>
</html>
)rawliteral";


// ─────────────────────────────────────────────────────────────────────────────
//  NODES PAGE  (/nodes)
//  Black-white theme · canvas graph · nickname editing
//  Input focus fix: sidebar never rebuilds while an input is focused
//  Mobile: graph full-width, node list stacks below
// ─────────────────────────────────────────────────────────────────────────────
const char nodes_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mesh Nodes</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }

/* ── Desktop: fixed full-height, no scroll ── */
html, body {
  height: 100%;
  overflow: hidden;
  background: #000;
  color: #fff;
  font-family: system-ui, sans-serif;
  font-size: 14px;
}
body {
  display: flex;
  flex-direction: column;
  padding: 20px;
  gap: 0;
}

/* ── Header ── */
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 14px;
  flex-shrink: 0;
}
h1 { font-size: 22px; }
.info { display: flex; gap: 16px; font-size: 13px; opacity: .65; }

/* ── Main row: graph + sidebar ── */
.main {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: row;
  gap: 14px;
}

/* ── Canvas graph ── */
.graph-wrap {
  flex: 1;
  min-width: 0;
  border-radius: 16px;
  outline: 1px solid #222;
  overflow: hidden;
  position: relative;
  background: #000;
}
canvas { display: block; width: 100%; height: 100%; }

/* Tooltip */
#tooltip {
  position: absolute;
  background: #fff; color: #000;
  font-size: 12px; font-weight: 600;
  padding: 5px 11px; border-radius: 8px;
  pointer-events: none;
  opacity: 0; transition: opacity 0.12s;
  white-space: nowrap; z-index: 10;
}
#tooltip.show { opacity: 1; }

/* ── Sidebar ── */
.sidebar {
  width: 220px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  overflow-y: auto;
}
.sidebar::-webkit-scrollbar        { width: 3px; }
.sidebar::-webkit-scrollbar-thumb  { background: #333; border-radius: 2px; }

.sidebar-title {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  opacity: .4;
  flex-shrink: 0;
  padding-bottom: 8px;
  border-bottom: 1px solid #1e1e1e;
}

/* Node card */
.node-card {
  border: 1px solid #1e1e1e;
  border-radius: 12px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex-shrink: 0;
  transition: border-color 0.15s;
}
.node-card:hover   { border-color: #444; }
.node-card.is-self { border-color: #fff; }

.card-top {
  display: flex; align-items: center; gap: 8px;
}
.node-dot {
  width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0;
}
.dot-self   { background: #fff; }
.dot-peer   { background: transparent; border: 2px solid #555; }

.node-id-text {
  font-size: 12px; opacity: .45;
  font-variant-numeric: tabular-nums; letter-spacing: .04em;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.node-nick-display {
  font-size: 13px; font-weight: 600; flex: 1;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}

.self-tag {
  margin-left: auto; font-size: 10px;
  background: #fff; color: #000;
  padding: 2px 7px; border-radius: 999px;
  font-weight: 700; letter-spacing: .05em; flex-shrink: 0;
}

/* Nick edit row */
.nick-row { display: flex; gap: 6px; }
.nick-input {
  flex: 1; min-width: 0;
  background: #0d0d0d; border: 1px solid #2a2a2a; border-radius: 8px;
  color: #fff; font-size: 13px; padding: 7px 10px; outline: none;
  transition: border-color 0.15s;
}
.nick-input:focus { border-color: #666; }
.nick-input::placeholder { color: #333; }

.nick-save {
  background: #fff; color: #000; border: none;
  border-radius: 8px; padding: 7px 11px;
  font-size: 12px; font-weight: 700; cursor: pointer; flex-shrink: 0;
  transition: opacity 0.15s;
}
.nick-save:hover  { opacity: .8; }
.nick-save:active { opacity: .5; }

/* ── MOBILE: graph fills screen, sidebar stacks below ── */
@media (max-width: 640px) {
  html, body { height: auto; overflow-y: auto; overflow-x: hidden; }

  body { padding: 0; }

  .header {
    padding: 14px 16px 10px;
    margin-bottom: 0;
    border-bottom: 1px solid #1a1a1a;
  }

  .main {
    flex-direction: column;
    flex: none;
    height: auto;
    gap: 0;
    min-height: 0;
  }

  /* Graph: square, full viewport width */
  .graph-wrap {
    width: 100vw;
    height: 100vw;
    border-radius: 0;
    outline: none;
    border-bottom: 1px solid #1a1a1a;
    flex-shrink: 0;
  }

  /* Sidebar: full width, vertical list */
  .sidebar {
    width: 100%;
    overflow-y: visible;
    flex-direction: column;
    padding: 14px 16px;
    gap: 10px;
  }

  .sidebar-title { margin-bottom: 2px; }

  .node-card { border-radius: 12px; }
}
</style>
</head>
<body>

<div class="header">
  <h1>Mesh Nodes</h1>
  <div class="info">
    <span>Node: <b id="hSelf">-</b></span>
    <span>Peers: <b id="hCount">0</b></span>
  </div>
</div>

<div class="main">
  <div class="graph-wrap">
    <canvas id="cvs"></canvas>
    <div id="tooltip"></div>
  </div>

  <div class="sidebar">
    <div class="sidebar-title">// nodes</div>
    <div id="node-list"></div>
  </div>
</div>

<script>
(function () {
  // ── State ──────────────────────────────────────────────────────────────
  var selfId   = '';
  var peers    = [];
  var nickMap  = {};   // nodeId -> nickname (from server)
  var nodes    = [];   // canvas node objects
  var tick     = 0;
  var hoverId  = null;
  var lastData = {};

  // ── Canvas ─────────────────────────────────────────────────────────────
  var cvs     = document.getElementById('cvs');
  var ctx     = cvs.getContext('2d');
  var tooltip = document.getElementById('tooltip');
  var wrap    = cvs.parentElement;

  // Monochrome palette
  var C_BG      = '#000000';
  var C_GRID    = 'rgba(255,255,255,0.025)';
  var C_EDGE    = 'rgba(255,255,255,0.14)';
  var C_LABEL   = 'rgba(255,255,255,0.90)';
  var C_SUBLBL  = 'rgba(255,255,255,0.35)';
  var C_PULSE   = 'rgba(255,255,255,0.08)';
  var C_PULSEH  = 'rgba(255,255,255,0.18)';
  var FONT      = 'system-ui, sans-serif';

  function resize() {
    cvs.width  = wrap.clientWidth  * devicePixelRatio;
    cvs.height = wrap.clientHeight * devicePixelRatio;
    ctx.setTransform(1,0,0,1,0,0);
    ctx.scale(devicePixelRatio, devicePixelRatio);
    layout();
  }
  window.addEventListener('resize', resize);

  // ── Layout ─────────────────────────────────────────────────────────────
  function layout() {
    var W = wrap.clientWidth;
    var H = wrap.clientHeight;
    var cx = W / 2, cy = H / 2;
    var count = peers.length;

    var self = nodes.find(function(n) { return n.isSelf; });
    if (!self) {
      self = { id: selfId, x: cx, y: cy, targetX: cx, targetY: cy,
               r: 22, pulse: 0, isSelf: true };
      nodes = [self];
    }
    self.targetX = cx; self.targetY = cy;

    var orbitR = Math.min(W * 0.30, H * 0.34, 160);

    peers.forEach(function(pid, i) {
      var angle = (2 * Math.PI / count) * i - Math.PI / 2;
      var tx = cx + orbitR * Math.cos(angle);
      var ty = cy + orbitR * Math.sin(angle);
      var n  = nodes.find(function(x) { return x.id === pid; });
      if (!n) {
        n = { id: pid, x: tx, y: ty, targetX: tx, targetY: ty,
              r: 16, pulse: Math.random() * Math.PI * 2, isSelf: false };
        nodes.push(n);
      }
      n.targetX = tx; n.targetY = ty;
    });

    nodes = nodes.filter(function(n) {
      return n.isSelf || peers.indexOf(n.id) !== -1;
    });
  }

  var lerp = function(a, b, t) { return a + (b - a) * t; };

  // ── Draw ───────────────────────────────────────────────────────────────
  function draw() {
    var W = wrap.clientWidth, H = wrap.clientHeight;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = C_BG; ctx.fillRect(0, 0, W, H);

    // Grid
    ctx.strokeStyle = C_GRID; ctx.lineWidth = 1;
    var gs = 38;
    for (var x = 0; x < W; x += gs) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,H); ctx.stroke(); }
    for (var y = 0; y < H; y += gs) { ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(W,y); ctx.stroke(); }

    tick += 0.022;
    nodes.forEach(function(n) {
      n.x = lerp(n.x, n.targetX, 0.08);
      n.y = lerp(n.y, n.targetY, 0.08);
      n.pulse = (n.pulse + 0.035) % (2 * Math.PI);
    });

    var selfNode = nodes.find(function(n) { return n.isSelf; });
    if (!selfNode) return;

    // Edges — animated dashes
    nodes.forEach(function(n) {
      if (n.isSelf) return;
      ctx.save();
      ctx.setLineDash([5, 8]);
      ctx.lineDashOffset = -((tick * 32) % 26);
      ctx.strokeStyle = C_EDGE; ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(selfNode.x, selfNode.y);
      ctx.lineTo(n.x, n.y);
      ctx.stroke();
      ctx.restore();
    });

    // Nodes
    nodes.forEach(function(n) {
      var isHover = n.id === hoverId;
      var pAlpha  = (0.08 + Math.sin(n.pulse) * 0.05).toFixed(2);
      var pr      = n.r + 7 + Math.sin(n.pulse) * 3;

      // Pulse ring
      ctx.beginPath(); ctx.arc(n.x, n.y, pr, 0, 2 * Math.PI);
      ctx.strokeStyle = isHover ? C_PULSEH : C_PULSE;
      ctx.lineWidth   = isHover ? 2 : 1.5;
      ctx.stroke();

      // Extra hover halo
      if (isHover) {
        ctx.beginPath(); ctx.arc(n.x, n.y, n.r + 13, 0, 2 * Math.PI);
        ctx.strokeStyle = 'rgba(255,255,255,0.09)';
        ctx.lineWidth = 4; ctx.stroke();
      }

      // Fill
      ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, 2 * Math.PI);
      ctx.fillStyle   = n.isSelf ? '#ffffff' : '#0d0d0d';
      ctx.fill();
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth   = n.isSelf ? 0 : 1.5;
      ctx.stroke();

      // Labels
      var nick  = nickMap[n.id] || null;
      var short = n.id.substring(0, 8);

      if (nick) {
        // Nickname above
        ctx.font = 'bold 12px ' + FONT;
        ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
        ctx.fillStyle = C_LABEL;
        ctx.fillText(nick, n.x, n.y - n.r - 5);
        // node_id below
        ctx.font = '9px ' + FONT;
        ctx.textBaseline = 'top';
        ctx.fillStyle = C_SUBLBL;
        ctx.fillText(short, n.x, n.y + n.r + 4);
      } else {
        ctx.font = 'bold 11px ' + FONT;
        ctx.textAlign = 'center'; ctx.textBaseline = 'top';
        ctx.fillStyle = C_LABEL;
        ctx.fillText(short, n.x, n.y + n.r + 4);
      }

      // ME label inside self circle
      if (n.isSelf) {
        ctx.font = 'bold 10px ' + FONT;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillStyle = '#000';
        ctx.fillText('ME', n.x, n.y);
      }
    });

    // No peers hint
    if (peers.length === 0) {
      ctx.font = '13px ' + FONT;
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = 'rgba(255,255,255,0.18)';
      ctx.fillText('No peers detected', W / 2, H / 2 + 55);
    }
  }

  function animate() { draw(); requestAnimationFrame(animate); }

  // ── Hover / tooltip ────────────────────────────────────────────────────
  function hitTest(mx, my) {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      var dx = mx - n.x, dy = my - n.y;
      if (Math.sqrt(dx*dx + dy*dy) < n.r + 8) return n;
    }
    return null;
  }

  cvs.addEventListener('mousemove', function(e) {
    var rect = cvs.getBoundingClientRect();
    var hit  = hitTest(e.clientX - rect.left, e.clientY - rect.top);
    if (hit) {
      hoverId = hit.id;
      var nick  = nickMap[hit.id];
      var label = nick
        ? nick + '  ·  ' + hit.id.substring(0, 8)
        : hit.id.substring(0, 8);
      if (hit.isSelf) label = 'You  ·  ' + label;
      tooltip.textContent = label;
      tooltip.style.left  = (e.clientX - rect.left + 14) + 'px';
      tooltip.style.top   = (e.clientY - rect.top  - 18) + 'px';
      tooltip.classList.add('show');
    } else {
      hoverId = null;
      tooltip.classList.remove('show');
    }
  });
  cvs.addEventListener('mouseleave', function() {
    hoverId = null; tooltip.classList.remove('show');
  });

  // ── Sidebar ────────────────────────────────────────────────────────────
  // Key fix: never rebuild sidebar while a nick input is focused.
  // This prevents the input being torn out from under the user while typing.
  function isSidebarFocused() {
    var el = document.activeElement;
    return el && el.classList && el.classList.contains('nick-input');
  }

  function buildSidebar(d) {
    if (isSidebarFocused()) return;   // ← focus guard

    var list = document.getElementById('node-list');
    list.innerHTML = '';

    var allNodes = [{ id: d.nodeId, isSelf: true }].concat(
      (d.peers || []).map(function(id) { return { id: id, isSelf: false }; })
    );

    allNodes.forEach(function(node) {
      var card = document.createElement('div');
      card.className = 'node-card' + (node.isSelf ? ' is-self' : '');

      // Top row
      var top = document.createElement('div');
      top.className = 'card-top';

      var dot = document.createElement('div');
      dot.className = 'node-dot ' + (node.isSelf ? 'dot-self' : 'dot-peer');
      top.appendChild(dot);

      var nick = nickMap[node.id];

      // Nickname display (or short ID if not set)
      var nd = document.createElement('div');
      nd.className = 'node-nick-display';
      nd.textContent = nick || (node.isSelf ? 'You' : node.id.substring(0, 8));
      top.appendChild(nd);

      if (node.isSelf) {
        var badge = document.createElement('span');
        badge.className = 'self-tag';
        badge.textContent = 'YOU';
        top.appendChild(badge);
      }
      card.appendChild(top);

      // Short ID row
      var sid = document.createElement('div');
      sid.className = 'node-id-text';
      sid.textContent = node.id.substring(0, 12);
      card.appendChild(sid);

      // Nick edit row
      var row = document.createElement('div');
      row.className = 'nick-row';

      var inp = document.createElement('input');
      inp.className   = 'nick-input';
      inp.type        = 'text';
      inp.maxLength   = 20;
      inp.value       = nick || '';
      inp.placeholder = 'Rename…';
      inp.setAttribute('autocomplete', 'off');
      inp.setAttribute('autocorrect',  'off');
      inp.setAttribute('autocapitalize', 'off');
      inp.setAttribute('spellcheck', 'false');

      var btn = document.createElement('button');
      btn.className   = 'nick-save';
      btn.textContent = 'Save';

      var nodeId = node.id;

      function doSave() {
        var v = inp.value.trim();
        if (!v) return;
        fetch('/setnick?id=' + encodeURIComponent(nodeId)
                + '&nick=' + encodeURIComponent(v))
          .then(function() { inp.blur(); })
          .catch(function() {});
      }

      btn.addEventListener('click', doSave);
      inp.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') { e.preventDefault(); doSave(); }
      });

      // Prevent clicks inside the input from bubbling oddly on mobile
      inp.addEventListener('pointerdown', function(e) { e.stopPropagation(); });

      row.appendChild(inp);
      row.appendChild(btn);
      card.appendChild(row);
      list.appendChild(card);
    });
  }

  // ── Data poll ──────────────────────────────────────────────────────────
  function update() {
    fetch('/data')
      .then(function(r) { return r.json(); })
      .then(function(d) {
        lastData = d;
        selfId   = d.nodeId;
        peers    = d.peers || [];

        // Rebuild nick map from authoritative server data
        nickMap = {};
        (d.nicknames || []).forEach(function(n) { nickMap[n.id] = n.nick; });

        var selfNick = nickMap[d.nodeId] || d.nodeId.substring(0, 8);
        document.getElementById('hSelf').textContent  = selfNick;
        document.getElementById('hCount').textContent = d.nodeCount;

        layout();
        buildSidebar(d);   // skipped automatically if input is focused
      })
      .catch(function() {});
  }

  // ── Boot ───────────────────────────────────────────────────────────────
  resize();
  animate();
  update();
  setInterval(update, 1500);
})();
</script>
</body>
</html>
)rawliteral";
