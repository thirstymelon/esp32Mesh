#include "web_page.h"

const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mesh Chat</title>
<style>
body{
    margin:0;
    padding:20px;
    background:#000;
    color:#fff;
    font-family:system-ui;
}
.container{max-width:600px;margin:auto;}
h1{text-align:center;margin-bottom:15px;}
.info{
    display:flex;
    justify-content:space-between;
    font-size:13px;
    opacity:.7;
    margin-bottom:12px;
}
.chat{
    min-height:320px;
    padding:14px;
    border-radius:16px;
    outline:1px solid #333;
    display:flex;
    flex-direction:column;
    gap:10px;
    overflow-y:auto;
}
.msg{
    max-width:80%;
    padding:10px 14px;
    border-radius:18px;
    font-size:14px;
}
.me{
    align-self:flex-end;
    background:#fff;
    color:#000;
}
.other{
    align-self:flex-start;
    border:1px solid #333;
}
.input-row{
    display:flex;
    gap:10px;
    margin-top:14px;
}
input{
    flex:1;
    padding:14px;
    border-radius:999px;
    border:1px solid #444;
    background:#000;
    color:#fff;
}
button{
    padding:14px 20px;
    border-radius:999px;
    border:1px solid #fff;
    background:#fff;
    color:#000;
    font-weight:600;
}
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
onkeydown="if(event.key==='Enter')send()">
<button onclick="send()">Send</button>
</div>
</div>

<script>
let rendered = 0;

function send(){
    const i=document.getElementById('msg');
    const t=i.value.trim();
    if(!t)return;
    fetch('/send?msg='+encodeURIComponent(t));
    i.value='';
}

function update(){
fetch('/data').then(r=>r.json()).then(d=>{

document.getElementById('nodeId').textContent=d.nodeId;
document.getElementById('nodeCount').textContent=d.nodeCount;

const box=document.getElementById('chat');

for(let i=rendered;i<d.messages.length;i++){
    const m=d.messages[i];
    const div=document.createElement('div');
    div.className='msg '+(m.me?'me':'other');
    div.textContent=(m.me?'Me: ':m.sender+': ')+m.text;
    box.appendChild(div);
}

rendered=d.messages.length;
box.scrollTop=box.scrollHeight;

});
}

setInterval(update,1000);
update();
</script>
</body>
</html>
)rawliteral";
