-- BrunoRoque SNES EMU

local sc = ""

init_dlsym()
sceMsgDialogTerminate() 

local PC_IP    = "127.0.0.1"
local LOG_PORT = 9027
local WEB_PORT = 9030

local function htons(p) return ((p << 8) | (p >> 8)) & 0xFFFF end
local function inet_addr(s)
    local a,b,c,d = s:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    return (d << 24) | (c << 16) | (b << 8) | a
end

local function make_sockaddr_in(port, ip)
    local sa = malloc(16)
    for i = 0, 15 do write8(sa + i, 0) end
    write8(sa + 0, 16); write8(sa + 1, 2)
    write16(sa + 2, htons(port))
    if ip then write32(sa + 4, inet_addr(ip)) end
    return sa
end

local log_sock = create_socket(AF_INET, SOCK_DGRAM, 0)
local log_sa = make_sockaddr_in(LOG_PORT, PC_IP)

local function ulog(m)
    if log_sock >= 0 then syscall.sendto(log_sock, m.."\n", #m+1, 0, log_sa, 16) end
end
ulog("=== BrunoRoque SNES EMU")

if not sceKernelLoadStartModule then
    sceKernelLoadStartModule = func_wrap(dlsym(LIBKERNEL_HANDLE, "sceKernelLoadStartModule"))
end
local libUser = sceKernelLoadStartModule("libSceUserService.sprx", 0, 0, 0, 0, 0)
local getUserId = dlsym(libUser, "sceUserServiceGetInitialUser")
local uid_buf = malloc(4)
write32(uid_buf, 0)
if getUserId then func_wrap(getUserId)(uid_buf) end
local userId = read32(uid_buf)
ulog("userId=" .. tostring(userId))

local web_sock = create_socket(AF_INET, 1, 0) 
if web_sock >= 0 then
    local ba = make_sockaddr_in(WEB_PORT)
    local en = malloc(4)
    write32(en, 1)
    syscall.setsockopt(web_sock, 0xFFFF, 4, en, 4)
    syscall.bind(web_sock, ba, 16)
    syscall.listen(web_sock, 128)
    ulog("Web controller on port " .. WEB_PORT)
else
    ulog("Web socket failed!")
end

local html_body = [=[
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta
      name="viewport"
      content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover"
    />
<title>BrunoRoque SNES</title>
    <style>
      @import url("https://fonts.googleapis.com/css2?family=Press+Start+2P&family=Orbitron:wght@400;700;900&display=swap");
      * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
        -webkit-tap-highlight-color: transparent;
        touch-action: manipulation;
      }
      html,
      body {
        width: 100%;
        height: 100%;
        overflow: hidden;
        position: fixed;
      }
      body {
        background: #716a7c;
        font-family: "Orbitron", monospace;
        display: flex;
        align-items: center;
        justify-content: center;
        background-image:
          radial-gradient(
            ellipse at 50% 0%,
            rgba(255, 214, 235, 0.28) 0%,
            transparent 60%
          ),
          radial-gradient(
            ellipse at 50% 100%,
            rgba(196, 168, 220, 0.2) 0%,
            transparent 50%
          );
        user-select: none;
        -webkit-user-select: none;
        padding: env(safe-area-inset-top) env(safe-area-inset-right)
          env(safe-area-inset-bottom) env(safe-area-inset-left);
      }
      .controller {
        position: relative;
        width: min(96vw, 680px);
        height: min(80vh, 440px);
        background: linear-gradient(
          165deg,
          #dcd5e2 0%,
          #c2b8cb 40%,
          #a79cab 100%
        );
        border-radius: 24px 24px 80px 80px;
        box-shadow:
          0 2px 0 #eee7f4,
          0 -1px 0 #8f859b,
          0 20px 60px rgba(0, 0, 0, 0.8),
          inset 0 1px 0 rgba(255, 255, 255, 0.24),
          inset 0 -2px 0 rgba(80, 56, 80, 0.18);
        display: flex;
        flex-direction: column;
        padding: 16px 20px;
      }
      .top-bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 0 8px 8px;
      }
      .brand {
        font-family: "Press Start 2P", monospace;
        font-size: clamp(8px, 2vw, 13px);
        color: #cf4f92;
        text-shadow: 0 0 12px rgba(207, 79, 146, 0.35);
        letter-spacing: 2px;
      }
      .screen-bar {
        background: #5d5668;
        border-radius: 6px;
        margin: 0 20px 12px;
        padding: 6px 12px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        border: 1px solid #7b7188;
        min-height: 28px;
        gap: 8px;
      }
      .screen-label {
        font-family: "Press Start 2P", monospace;
        font-size: clamp(6px, 1.2vw, 8px);
        color: #f3e8fb;
        letter-spacing: 1px;
      }
      .hid-btn {
        font-family: "Orbitron", monospace;
        font-size: clamp(7px, 1.2vw, 9px);
        color: #ffe6f4;
        background: rgba(207, 79, 146, 0.12);
        border: 1px solid rgba(207, 79, 146, 0.35);
        border-radius: 4px;
        padding: 3px 8px;
        cursor: pointer;
        letter-spacing: 0.5px;
        white-space: nowrap;
        transition: all 0.15s;
        display: none;
      }
      .hid-btn:hover,
      .hid-btn:active {
        background: rgba(207, 79, 146, 0.22);
        border-color: rgba(207, 79, 146, 0.55);
      }
      .hid-btn.show {
        display: inline-block;
      }
      .status-wrap {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .status-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: #84798d;
        border: 1px solid #655d6f;
        transition: all 0.3s;
        flex-shrink: 0;
      }
      .status-dot.on {
        background: #e46aa8;
        box-shadow:
          0 0 6px #e46aa8,
          0 0 14px rgba(228, 106, 168, 0.35);
        border-color: #c54a89;
      }
      #status {
        font-family: "Orbitron", monospace;
        font-size: clamp(7px, 1.3vw, 9px);
        color: #ffe6f4;
        text-transform: uppercase;
        letter-spacing: 1px;
      }
      .controls {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 8px;
      }
      .dpad-wrap {
        position: relative;
        width: 170px;
        height: 170px;
        flex-shrink: 0;
      }
      .dpad {
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        width: 148px;
        height: 148px;
      }
      .dpad-bg {
        position: absolute;
        background: #111;
        border: 2px solid #222;
      }
      .dpad-h {
        top: 50%;
        left: 0;
        right: 0;
        height: 50px;
        transform: translateY(-50%);
        border-radius: 4px;
      }
      .dpad-v {
        left: 50%;
        top: 0;
        bottom: 0;
        width: 50px;
        transform: translateX(-50%);
        border-radius: 4px;
      }
      .dpad-center {
        position: absolute;
        top: 50%;
        left: 50%;
        width: 14px;
        height: 14px;
        border-radius: 50%;
        background: #1a1a1a;
        border: 1px solid #333;
        transform: translate(-50%, -50%);
        z-index: 3;
      }
      .dpad-btn {
        position: absolute;
        z-index: 2;
        display: flex;
        align-items: center;
        justify-content: center;
        background: transparent;
        border: none;
        color: #6a6178;
        font-size: 18px;
        cursor: pointer;
        transition:
          color 0.08s,
          transform 0.06s;
      }
      .dpad-btn.active {
        color: #d85fa3;
      }
      .dpad-up {
        top: 0;
        left: 50%;
        transform: translateX(-50%);
        width: 50px;
        height: 50px;
      }
      .dpad-up.active {
        transform: translateX(-50%) scale(0.9);
      }
      .dpad-down {
        bottom: 0;
        left: 50%;
        transform: translateX(-50%);
        width: 50px;
        height: 50px;
      }
      .dpad-down.active {
        transform: translateX(-50%) scale(0.9);
      }
      .dpad-left {
        left: 0;
        top: 50%;
        transform: translateY(-50%);
        width: 50px;
        height: 50px;
      }
      .dpad-left.active {
        transform: translateY(-50%) scale(0.9);
      }
      .dpad-right {
        right: 0;
        top: 50%;
        transform: translateY(-50%);
        width: 50px;
        height: 50px;
      }
      .dpad-right.active {
        transform: translateY(-50%) scale(0.9);
      }
      .center-btns {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 6px;
        padding-top: 40px;
      }
      .meta-row {
        display: flex;
        gap: 14px;
      }
      .meta-btn {
        width: 62px;
        height: 24px;
        border-radius: 12px;
        border: none;
        background: linear-gradient(180deg, #9d92aa 0%, #7e738d 100%);
        box-shadow:
          0 2px 4px rgba(0, 0, 0, 0.5),
          inset 0 1px 0 rgba(255, 255, 255, 0.05);
        cursor: pointer;
        transition: all 0.08s;
      }
      .meta-btn.active {
        background: linear-gradient(180deg, #b3a6c0 0%, #91839e 100%);
        box-shadow:
          0 1px 2px rgba(0, 0, 0, 0.5),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
        transform: translateY(1px);
      }
      .meta-label {
        font-family: "Press Start 2P", monospace;
        font-size: clamp(5px, 1vw, 7px);
        color: #675d75;
        letter-spacing: 1px;
        text-align: center;
        margin-top: 4px;
      }
      .ab-wrap {
        position: relative;
        width: 170px;
        height: 170px;
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .ab-tilt {
        transform: rotate(0deg);
      }
      .ab-row {
        display: flex;
        gap: 18px;
        align-items: center;
      }
      .face-btn {
        width: 66px;
        height: 66px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        position: relative;
        transition: all 0.08s;
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: "Press Start 2P", monospace;
        font-size: clamp(11px, 2vw, 14px);
        color: rgba(255, 255, 255, 0.7);
        text-shadow: 0 -1px 1px rgba(0, 0, 0, 0.4);
      }
      .btn-a {
        background: linear-gradient(145deg, #d96eab 0%, #8f4c77 100%);
        box-shadow:
          0 4px 8px rgba(0, 0, 0, 0.6),
          0 0 0 3px #8d8299,
          inset 0 1px 0 rgba(255, 255, 255, 0.15);
      }
      .btn-a.active {
        background: linear-gradient(145deg, #f08dc3 0%, #b56294 100%);
        box-shadow:
          0 2px 4px rgba(0, 0, 0, 0.6),
          0 0 0 3px #8d8299,
          0 0 20px rgba(240, 141, 195, 0.32),
          inset 0 1px 0 rgba(255, 255, 255, 0.2);
        transform: scale(0.93);
      }
      .btn-b {
        background: linear-gradient(145deg, #d96eab 0%, #8f4c77 100%);
        box-shadow:
          0 4px 8px rgba(0, 0, 0, 0.6),
          0 0 0 3px #8d8299,
          inset 0 1px 0 rgba(255, 255, 255, 0.15);
      }
      .btn-b.active {
        background: linear-gradient(145deg, #f08dc3 0%, #b56294 100%);
        box-shadow:
          0 2px 4px rgba(0, 0, 0, 0.6),
          0 0 0 3px #8d8299,
          0 0 20px rgba(240, 141, 195, 0.32),
          inset 0 1px 0 rgba(255, 255, 255, 0.2);
        transform: scale(0.93);
      }
      .ab-label {
        font-family: "Press Start 2P", monospace;
        font-size: clamp(6px, 1vw, 8px);
        color: #675d75;
        text-align: center;
        margin-top: 4px;
      }
      .grooves {
        position: absolute;
        bottom: 20px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 3px;
      }
      .groove {
        width: 40px;
        height: 3px;
        border-radius: 2px;
        background: #16161e;
      }
      @media (max-width: 600px) {
        body {
          align-items: flex-end;
        }
        .controller {
          width: 100vw;
          height: 100vh;
          height: 100dvh;
          border-radius: 0;
          padding: 12px;
          padding-top: max(12px, env(safe-area-inset-top));
          padding-bottom: max(20px, env(safe-area-inset-bottom));
          box-shadow:
            inset 0 1px 0 rgba(255, 255, 255, 0.04),
            inset 0 -2px 0 rgba(0, 0, 0, 0.3);
        }
        .screen-bar {
          margin: 0 4px 10px;
        }
        .controls {
          padding: 0 4px;
        }
        .dpad-wrap {
          width: 156px;
          height: 156px;
        }
        .dpad {
          width: 136px;
          height: 136px;
        }
        .dpad-h {
          height: 46px;
        }
        .dpad-v {
          width: 46px;
        }
        .dpad-btn {
          font-size: 17px;
        }
        .dpad-up,
        .dpad-down {
          width: 46px;
          height: 46px;
        }
        .dpad-left,
        .dpad-right {
          width: 46px;
          height: 46px;
        }
        .face-btn {
          width: 62px;
          height: 62px;
        }
        .ab-wrap {
          width: 156px;
          height: 156px;
        }
        .grooves {
          bottom: max(14px, env(safe-area-inset-bottom));
        }
        .groove {
          width: 28px;
        }
      }
      @media (max-width: 380px) {
        .dpad-wrap {
          width: 134px;
          height: 134px;
        }
        .dpad {
          width: 118px;
          height: 118px;
        }
        .dpad-h {
          height: 40px;
        }
        .dpad-v {
          width: 40px;
        }
        .dpad-up,
        .dpad-down {
          width: 40px;
          height: 40px;
        }
        .dpad-left,
        .dpad-right {
          width: 40px;
          height: 40px;
        }
        .dpad-btn {
          font-size: 15px;
        }
        .ab-wrap {
          width: 134px;
          height: 134px;
        }
        .face-btn {
          width: 54px;
          height: 54px;
        }
        .ab-row {
          gap: 14px;
        }
        .meta-btn {
          width: 52px;
          height: 20px;
        }
        .meta-row {
          gap: 10px;
        }
      }
      @media (max-width: 600px) and(min-height:700px) {
        .controls {
          align-items: flex-end;
          padding-bottom: 30px;
        }
        .center-btns {
          padding-top: 20px;
          align-self: flex-end;
          padding-bottom: 40px;
        }
      }
      @media (orientation: landscape) and(max-height:500px) {
        .controller {
          width: 100vw;
          height: 100vh;
          height: 100dvh;
          border-radius: 0;
          padding: 6px 16px;
          padding-left: max(16px, env(safe-area-inset-left));
          padding-right: max(16px, env(safe-area-inset-right));
        }
        .top-bar {
          padding: 0 8px 4px;
        }
        .screen-bar {
          margin: 0 8px 6px;
          padding: 4px 10px;
          min-height: 22px;
        }
        .center-btns {
          padding-top: 10px;
        }
        .grooves {
          bottom: 8px;
        }
        .groove {
          width: 24px;
        }
      }
      @media (min-width: 601px) {
        .dpad-wrap {
          width: 180px;
          height: 180px;
        }
        .dpad {
          width: 158px;
          height: 158px;
        }
        .dpad-h {
          height: 54px;
        }
        .dpad-v {
          width: 54px;
        }
        .dpad-up,
        .dpad-down {
          width: 54px;
          height: 54px;
        }
        .dpad-left,
        .dpad-right {
          width: 54px;
          height: 54px;
        }
        .dpad-btn {
          font-size: 22px;
        }
        .ab-wrap {
          width: 180px;
          height: 180px;
        }
        .face-btn {
          width: 72px;
          height: 72px;
        }
        .ab-row {
          gap: 20px;
        }
      }
    </style>
  </head>
  <body>
    <div class="controller" id="ctrl">
<div class="top-bar"><div class="brand">BRUNOROQUE</div></div>
      <div class="screen-bar">
        <span class="screen-label">NES CONTROLLER</span>
        <button class="hid-btn" id="hid-btn">&#x1F3AE; CONNECT</button>
        <div class="status-wrap">
          <div class="status-dot" id="dot"></div>
          <span id="status">CONNECTING...</span>
        </div>
      </div>
      <div class="controls">
        <div class="dpad-wrap">
          <div class="dpad">
            <div class="dpad-bg dpad-h"></div>
            <div class="dpad-bg dpad-v"></div>
            <div class="dpad-center"></div>
            <button class="dpad-btn dpad-up" data-b="16">&#9650;</button>
            <button class="dpad-btn dpad-down" data-b="32">&#9660;</button>
            <button class="dpad-btn dpad-left" data-b="64">&#9664;</button>
            <button class="dpad-btn dpad-right" data-b="128">&#9654;</button>
          </div>
        </div>
        <div class="center-btns">
          <div class="meta-row">
            <div>
              <button class="meta-btn" data-b="4"></button>
              <div class="meta-label">SELECT</div>
            </div>
            <div>
              <button class="meta-btn" data-b="8"></button>
              <div class="meta-label">START</div>
            </div>
          </div>
          <div style="margin-top: 12px">
            <button
              class="meta-btn"
              data-b="255"
              style="
                width: 80px;
                background: linear-gradient(180deg, #9e6787 0%, #7b4d68 100%);
              "
            ></button>
            <div class="meta-label">EXIT EMU</div>
          </div>
        </div>
        <div class="ab-wrap">
          <div class="ab-tilt">
            <div class="ab-row">
              <div>
                <button class="face-btn btn-b" data-b="2">B</button>
                <div class="ab-label">B</div>
              </div>
              <div>
                <button class="face-btn btn-a" data-b="1">A</button>
                <div class="ab-label">A</div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="grooves">
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
        <div class="groove"></div>
      </div>
    </div>
    <script>
      (function () {
        var S = document.getElementById("status"),
          DOT = document.getElementById("dot"),
          HIDBTN = document.getElementById("hid-btn");
        var state = 0,
          connected = false,
          gpIdx = null;
        function doSend() {
          try {
            fetch("/b" + state, { method: "POST", keepalive: true });
          } catch (e) {}
          if (!connected) {
            connected = true;
            DOT.classList.add("on");
            S.textContent = "CONNECTED";
          }
        }
        function send() {
          doSend();
        }
        function press(mask) {
          if (mask >= 254) {
            state = mask;
            send();
            state = 0;
            return;
          }
          if (!(state & mask)) {
            state |= mask;
            send();
          }
        }
        function release(mask) {
          if (mask >= 254) return;
          if (state & mask) {
            state &= ~mask;
            send();
          }
        }
        function btnOn(m) {
          document
            .querySelectorAll('[data-b="' + m + '"]')
            .forEach(function (e) {
              e.classList.add("active");
            });
        }
        function btnOff(m) {
          document
            .querySelectorAll('[data-b="' + m + '"]')
            .forEach(function (e) {
              e.classList.remove("active");
            });
        }
        function applyMask(m) {
          [1, 2, 4, 8, 16, 32, 64, 128].forEach(function (b) {
            if (m & b) btnOn(b);
            else btnOff(b);
          });
          state = m;
          send();
        }
        var touchMap = new Map();
        function processTouch(e) {
          e.preventDefault();
          var liveIds = new Set();
          for (var i = 0; i < e.touches.length; i++) {
            var t = e.touches[i];
            liveIds.add(t.identifier);
            var el = document.elementFromPoint(t.clientX, t.clientY);
            var m = el && el.dataset.b ? +el.dataset.b : null;
            var prev = touchMap.get(t.identifier);
            if (prev !== undefined && prev !== m) {
              touchMap.delete(t.identifier);
              release(prev);
              btnOff(prev);
            }
            if (m !== null && touchMap.get(t.identifier) !== m) {
              touchMap.set(t.identifier, m);
              press(m);
              btnOn(m);
            }
          }
          for (var p of touchMap) {
            if (!liveIds.has(p[0])) {
              touchMap.delete(p[0]);
              release(p[1]);
              btnOff(p[1]);
            }
          }
        }
        function processEnd(e) {
          e.preventDefault();
          var liveIds = new Set();
          for (var i = 0; i < e.touches.length; i++)
            liveIds.add(e.touches[i].identifier);
          for (var p of touchMap) {
            if (!liveIds.has(p[0])) {
              touchMap.delete(p[0]);
              release(p[1]);
              btnOff(p[1]);
            }
          }
        }
        document.addEventListener("touchstart", processTouch, {
          passive: false,
        });
        document.addEventListener("touchmove", processTouch, {
          passive: false,
        });
        document.addEventListener("touchend", processEnd, { passive: false });
        document.addEventListener("touchcancel", processEnd, {
          passive: false,
        });
        var mouseBtn = null;
        document.querySelectorAll("[data-b]").forEach(function (el) {
          el.addEventListener("mousedown", function (e) {
            e.preventDefault();
            var m = +el.dataset.b;
            mouseBtn = m;
            press(m);
            btnOn(m);
          });
        });
        window.addEventListener("mouseup", function () {
          if (mouseBtn !== null) {
            var m = mouseBtn;
            mouseBtn = null;
            release(m);
            btnOff(m);
          }
        });
        var KM = {
          ArrowUp: 16,
          w: 16,
          W: 16,
          ArrowDown: 32,
          s: 32,
          S: 32,
          ArrowLeft: 64,
          a: 64,
          A: 64,
          ArrowRight: 128,
          d: 128,
          D: 128,
          x: 1,
          X: 1,
          ".": 1,
          z: 2,
          Z: 2,
          ",": 2,
          Shift: 4,
          Enter: 8,
          " ": 8,
          Escape: 254,
          Tab: 255,
        };
        var kDown = new Set();
        window.addEventListener("keydown", function (e) {
          var m = KM[e.key];
          if (m !== undefined && !kDown.has(e.key)) {
            kDown.add(e.key);
            if (m >= 254) {
              state = m;
              send();
              state = 0;
            } else {
              press(m);
              btnOn(m);
            }
            e.preventDefault();
          }
        });
        window.addEventListener("keyup", function (e) {
          var m = KM[e.key];
          if (m !== undefined) {
            kDown.delete(e.key);
            if (m < 254) {
              release(m);
              btnOff(m);
            }
            e.preventDefault();
          }
        });
        var gpActive = false,
          hidConnected = false;
        window.addEventListener("gamepadconnected", function (e) {
          gpIdx = e.gamepad.index;
          S.textContent = e.gamepad.id.substring(0, 22);
          S.style.color = "#8af";
          gpActive = true;
          HIDBTN.classList.remove("show");
        });
        window.addEventListener("gamepaddisconnected", function () {
          gpIdx = null;
          gpActive = false;
          S.textContent = connected ? "CONNECTED" : "CONNECTING...";
          S.style.color = "";
          if (!hidConnected) showHidButton();
        });
        var prevGP = 0,
          gpFrames = 0;
        function pollGP() {
          try {
            var gps = navigator.getGamepads();
            if (gpIdx === null && gps) {
              for (var i = 0; i < gps.length; i++) {
                if (!gps[i] || !gps[i].connected) continue;
                for (var b = 0; b < gps[i].buttons.length; b++) {
                  if (gps[i].buttons[b].pressed) {
                    gpIdx = i;
                    gpActive = true;
                    S.textContent = gps[i].id.substring(0, 22);
                    S.style.color = "#8af";
                    HIDBTN.classList.remove("show");
                    break;
                  }
                }
                if (gpIdx !== null) break;
              }
            }
            if (gpIdx !== null && gps[gpIdx] && gps[gpIdx].connected) {
              var gp = gps[gpIdx];
              var m = 0;
              var nb = gp.buttons.length;
              if (nb > 0 && gp.buttons[0].pressed) m |= 1;
              if (nb > 2 && gp.buttons[2].pressed) m |= 2;
              if (nb > 1 && gp.buttons[1].pressed) m |= 2;
              if (nb > 8 && gp.buttons[8].pressed) m |= 4;
              if (nb > 6 && gp.buttons[6].pressed) m |= 4;
              if (nb > 9 && gp.buttons[9].pressed) m |= 8;
              if (nb > 7 && gp.buttons[7].pressed) m |= 8;
              if (nb > 12 && gp.buttons[12].pressed) m |= 16;
              if (nb > 13 && gp.buttons[13].pressed) m |= 32;
              if (nb > 14 && gp.buttons[14].pressed) m |= 64;
              if (nb > 15 && gp.buttons[15].pressed) m |= 128;
              if (gp.axes.length >= 2) {
                if (gp.axes[1] < -0.5) m |= 16;
                if (gp.axes[1] > 0.5) m |= 32;
                if (gp.axes[0] < -0.5) m |= 64;
                if (gp.axes[0] > 0.5) m |= 128;
              }
              if (gp.axes.length >= 4) {
                if (gp.axes[3] < -0.5 || gp.axes[3] > 3) m |= 16;
                if (gp.axes[3] > 0.5 && gp.axes[3] < 2) m |= 32;
                if (gp.axes[2] < -0.5) m |= 64;
                if (gp.axes[2] > 0.5) m |= 128;
              }
              if (gp.axes.length >= 8) {
                if (gp.axes[7] < -0.5) m |= 16;
                if (gp.axes[7] > 0.5) m |= 32;
                if (gp.axes[6] < -0.5) m |= 64;
                if (gp.axes[6] > 0.5) m |= 128;
              }
              if (nb > 4 && gp.buttons[4].pressed) {
                state = 254;
                send();
                state = 0;
                prevGP = m;
                requestAnimationFrame(pollGP);
                return;
              }
              if (nb > 5 && gp.buttons[5].pressed) {
                state = 255;
                send();
                state = 0;
                prevGP = m;
                requestAnimationFrame(pollGP);
                return;
              }
              gpFrames++;
              if (m !== prevGP || (m !== 0 && gpFrames % 5 === 0)) {
                applyMask(m);
                prevGP = m;
              }
            } else if (
              gpIdx !== null &&
              (!gps[gpIdx] || !gps[gpIdx].connected)
            ) {
              gpIdx = null;
              gpActive = false;
            }
          } catch (e) {}
          requestAnimationFrame(pollGP);
        }
        requestAnimationFrame(pollGP);
        var DS_VID = 0x054c,
          DS_PID = 0x0ce6,
          DS_EDGE = 0x0df2;
        var hidDevice = null,
          hidMode = null,
          hidPrevMask = -1;
        var HAT = [16, 16 | 128, 128, 32 | 128, 32, 32 | 64, 64, 16 | 64, 0];
        function parseDualSense(rid, data) {
          var m = 0,
            db,
            b0,
            b1,
            lx,
            ly;
          if (rid === 0x01 && data.byteLength >= 9 && data.byteLength <= 10) {
            lx = data.getUint8(0);
            ly = data.getUint8(1);
            db = data.getUint8(4);
            b0 = db;
            b1 = data.getUint8(5);
            var h = db & 0x0f;
            m |= HAT[h > 8 ? 8 : h];
            if (b0 & 0x20) m |= 1;
            if (b0 & 0x40) m |= 2;
            if (b0 & 0x10) m |= 2;
            if (b1 & 0x10) m |= 4;
            if (b1 & 0x20) m |= 8;
            if (b1 & 0x01) {
              state = 254;
              send();
              state = 0;
              return;
            }
            if (b1 & 0x02) {
              state = 255;
              send();
              state = 0;
              return;
            }
            if (lx < 64) m |= 64;
            if (lx > 192) m |= 128;
            if (ly < 64) m |= 16;
            if (ly > 192) m |= 32;
            hidMode = "bt-simple";
          } else if (rid === 0x01 && data.byteLength >= 63) {
            lx = data.getUint8(0);
            ly = data.getUint8(1);
            db = data.getUint8(7);
            b1 = data.getUint8(8);
            var h = db & 0x0f;
            m |= HAT[h > 8 ? 8 : h];
            if (db & 0x20) m |= 1;
            if (db & 0x40) m |= 2;
            if (db & 0x10) m |= 2;
            if (b1 & 0x10) m |= 4;
            if (b1 & 0x20) m |= 8;
            if (b1 & 0x01) {
              state = 254;
              send();
              state = 0;
              return;
            }
            if (b1 & 0x02) {
              state = 255;
              send();
              state = 0;
              return;
            }
            if (lx < 64) m |= 64;
            if (lx > 192) m |= 128;
            if (ly < 64) m |= 16;
            if (ly > 192) m |= 32;
            hidMode = "usb";
          } else if (rid === 0x31 && data.byteLength >= 77) {
            var o = 1;
            lx = data.getUint8(o);
            ly = data.getUint8(o + 1);
            db = data.getUint8(o + 7);
            b1 = data.getUint8(o + 8);
            var h = db & 0x0f;
            m |= HAT[h > 8 ? 8 : h];
            if (db & 0x20) m |= 1;
            if (db & 0x40) m |= 2;
            if (db & 0x10) m |= 2;
            if (b1 & 0x10) m |= 4;
            if (b1 & 0x20) m |= 8;
            if (b1 & 0x01) {
              state = 254;
              send();
              state = 0;
              return;
            }
            if (b1 & 0x02) {
              state = 255;
              send();
              state = 0;
              return;
            }
            if (lx < 64) m |= 64;
            if (lx > 192) m |= 128;
            if (ly < 64) m |= 16;
            if (ly > 192) m |= 32;
            hidMode = "bt-ext";
          } else return;
          if (m !== hidPrevMask) {
            applyMask(m);
            hidPrevMask = m;
          }
        }
        async function tryExt(dev) {
          try {
            await dev.receiveFeatureReport(0x05);
          } catch (e) {}
        }
        async function connectHID() {
          if (!navigator.hid) {
            S.textContent = "WebHID N/A";
            S.style.color = "#f44";
            return;
          }
          try {
            var devs = await navigator.hid.requestDevice({
              filters: [
                { vendorId: DS_VID, productId: DS_PID },
                { vendorId: DS_VID, productId: DS_EDGE },
              ],
            });
            if (!devs || devs.length === 0) {
              S.textContent = "NO DEVICE";
              S.style.color = "#f44";
              return;
            }
            hidDevice = devs[0];
            if (!hidDevice.opened) await hidDevice.open();
            hidConnected = true;
            DOT.classList.add("on");
            connected = true;
            HIDBTN.classList.remove("show");
            var nm = hidDevice.productName || "DualSense";
            S.textContent = "\u{1F3AE} " + nm.substring(0, 18);
            S.style.color = "#4f8";
            hidDevice.addEventListener("inputreport", function (e) {
              parseDualSense(e.reportId, e.data);
            });
            await tryExt(hidDevice);
          } catch (e) {
            if (e.name !== "NotAllowedError") {
              S.textContent = "HID ERROR";
              S.style.color = "#f44";
            }
          }
        }
        function showHidButton() {
          if (navigator.hid && !hidConnected && gpIdx === null)
            HIDBTN.classList.add("show");
        }
        HIDBTN.addEventListener("click", function (e) {
          e.preventDefault();
          e.stopPropagation();
          connectHID();
        });
        async function autoReconnect() {
          if (!navigator.hid) return;
          try {
            var devs = await navigator.hid.getDevices();
            for (var i = 0; i < devs.length; i++) {
              var d = devs[i];
              if (
                d.vendorId === DS_VID &&
                (d.productId === DS_PID || d.productId === DS_EDGE)
              ) {
                hidDevice = d;
                if (!hidDevice.opened) await hidDevice.open();
                hidConnected = true;
                DOT.classList.add("on");
                connected = true;
                HIDBTN.classList.remove("show");
                var nm = hidDevice.productName || "DualSense";
                S.textContent = "\u{1F3AE} " + nm.substring(0, 18);
                S.style.color = "#4f8";
                hidDevice.addEventListener("inputreport", function (e) {
                  parseDualSense(e.reportId, e.data);
                });
                await tryExt(hidDevice);
                return;
              }
            }
          } catch (e) {}
          setTimeout(showHidButton, 2000);
        }
        autoReconnect();
      })();
    </script>
  </body>
</html>
]=]

local html_resp = "HTTP/1.1 200 OK\r\nContent-Type:text/html\r\nConnection:close\r\n\r\n" .. html_body
local html_len = #html_resp
local html_mem = malloc(html_len + 16)
write_buffer(html_mem, html_resp)
ulog("HTML: " .. html_len .. " bytes")



local ftp_srv = create_socket(AF_INET, 1, 0)
if ftp_srv >= 0 then
    local en = malloc(4); write32(en, 1)
    syscall.setsockopt(ftp_srv, 0xFFFF, 0x0004, en, 4)   -- SO_REUSEADDR
    syscall.setsockopt(ftp_srv, 0xFFFF, 0x0200, en, 4)    -- SO_REUSEPORT
    local ba = make_sockaddr_in(1337)
    local ret = syscall.bind(ftp_srv, ba, 16)
    ulog("ftp_srv fd=" .. tostring(ftp_srv) .. " bind=" .. tostring(ret))
    syscall.listen(ftp_srv, 128)
end

local ftp_data = create_socket(AF_INET, 1, 0)
if ftp_data >= 0 then
    local en = malloc(4); write32(en, 1)
    syscall.setsockopt(ftp_data, 0xFFFF, 0x0004, en, 4)
    syscall.setsockopt(ftp_data, 0xFFFF, 0x0200, en, 4)
    local ba = make_sockaddr_in(1338)
    local ret = syscall.bind(ftp_data, ba, 16)
    ulog("ftp_data fd=" .. tostring(ftp_data) .. " bind=" .. tostring(ret))
    syscall.listen(ftp_data, 128)
end

sc = sc:gsub("%s", "")
local bin = hex_to_binary(sc)
local JIT_SIZE = 0x10000
local bfd = jit_malloc(8)
local rwfd = jit_malloc(8)
local rxfd = jit_malloc(8)
local rwa = jit_malloc(8)  
local rxa = malloc(8)       
local nm = jit_malloc(8)
jit_write_buffer(nm, "nv4b")
jit_sceKernelJitCreateSharedMemory(nm, JIT_SIZE, 7, bfd)
jit_sceKernelJitCreateAliasOfSharedMemory(jit_read32(bfd), PROT_READ|PROT_WRITE, rwfd)
jit_sceKernelJitCreateAliasOfSharedMemory(jit_read32(bfd), PROT_READ|PROT_EXECUTE, rxfd)
jit_sceKernelJitMapSharedMemory(jit_read32(rwfd), PROT_READ|PROT_WRITE, rwa)
local rw = jit_read64(rwa)
local mfd = jit_send_recv_fd(jit_read32(rxfd), NEW_JIT_SOCK, NEW_MAIN_SOCK)
sceKernelJitMapSharedMemory(mfd, PROT_READ|PROT_EXECUTE, rxa)
local rx = read64(rxa)
write_shellcode(rw, sc)
ulog("Code: " .. #bin .. " bytes")

-- ext_args layout 
--   +0x00  s64 status       
--   +0x08  s64 step         
--   +0x10  u32 frame_count
--   +0x18  s32 log_fd
--   +0x1C  s32 pad_fd      
--   +0x20  u8  log_addr[16] (sockaddr_in for UDP log target)
--   +0x30  u64 dbg[0]       web controller listen fd
--   +0x38  u64 dbg[1]       HTML response buffer pointer
--   +0x40  u64 dbg[2]       HTML response length
--   +0x48  u64 dbg[3]       userId
--   +0x50  u64 dbg[4]       FTP control fd (port 1337)
--   +0x58  u64 dbg[5]       FTP data fd (port 1338)
local ext = malloc(0x80)
memset(ext, 0, 0x80)
write64(ext+0x00, 0xDEAD)
write32(ext+0x18, log_sock)
write32(ext+0x1C, -1)
for i=0,15 do write8(ext+0x20+i, read8(log_sa+i)) end
write64(ext+0x30, web_sock >= 0 and web_sock or -1)
write64(ext+0x38, html_mem)
write64(ext+0x40, html_len)
write64(ext+0x48, userId)
write64(ext+0x50, ftp_srv >= 0 and ftp_srv or -1)
write64(ext+0x58, ftp_data >= 0 and ftp_data or -1)
local current_ip = get_current_ip()
ulog("IP: " .. current_ip)
send_notification("BrunoRoque SNES EMU\nhttp://" .. current_ip .. ":" .. WEB_PORT)

func_wrap(rx)(EBOOT_BASE, SCE_KERNEL_DLSYM, ext)

local status = read64(ext+0x00)
local step = read64(ext+0x08)
local frames = read32(ext+0x10)
ulog("Done! status=" .. status .. " step=" .. step .. " frames=" .. frames)
send_notification("BrunoRoque SNES done\nstatus=" .. status .. " step=" .. step .. " frames=" .. frames)

