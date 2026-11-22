# -*- coding: utf-8 -*-
"""Generate README diagrams for CivLink (architecture + usage flow) using PIL."""
from PIL import Image, ImageDraw, ImageFont
import os

FONT = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)

# palette
BG      = (248, 250, 252)
NAVY    = (30, 58, 95)
BLUE    = (37, 99, 235)
GREEN   = (5, 150, 105)
RED     = (220, 38, 38)
AMBER   = (180, 83, 9)
SLATE   = (71, 85, 105)
SOFT    = (100, 116, 139)
BORDER  = (228, 231, 235)
WHITE   = (255, 255, 255)
CARD_A  = (232, 240, 254)   # light blue card
CARD_G  = (236, 253, 245)   # light green card
CARD_R  = (254, 242, 242)   # light red card
CARD_Y  = (255, 247, 237)   # light amber card

def box(d, x, y, w, h, fill, outline, label, sub=None, fs=15, fsub=12, tc=(15,23,42), bold=False):
    d.rounded_rectangle([x, y, x+w, y+h], radius=10, fill=fill, outline=outline, width=2)
    d.text((x+w/2, y+h/2 - (14 if sub else 0)), label, font=font(fs, bold), fill=tc, anchor="mm")
    if sub:
        d.text((x+w/2, y+h/2 + 16), sub, font=font(fsub), fill=SOFT, anchor="mm")

def arrow(d, x1, y1, x2, y2, color=BLUE, width=3, dashed=False, label=None, lx=None, ly=None, fs=12):
    import math
    if dashed:
        length = math.hypot(x2-x1, y2-y1)
        steps = int(length // 14)
        for i in range(0, steps, 2):
            t0 = i / max(steps, 1)
            t1 = min((i+1) / max(steps, 1), 1.0)
            ax, ay = x1+(x2-x1)*t0, y1+(y2-y1)*t0
            bx, by = x1+(x2-x1)*t1, y1+(y2-y1)*t1
            d.line([ax, ay, bx, by], fill=color, width=width)
    else:
        d.line([x1, y1, x2, y2], fill=color, width=width)
    ang = math.atan2(y2-y1, x2-x1)
    hx, hy = 8, 5
    p1 = (x2 - hx*math.cos(ang) - hy*math.sin(ang), y2 - hx*math.sin(ang) + hy*math.cos(ang))
    p2 = (x2 - hx*math.cos(ang) + hy*math.sin(ang), y2 - hx*math.sin(ang) - hy*math.cos(ang))
    d.polygon([(x2, y2), p1, p2], fill=color)
    if label:
        d.text((lx if lx is not None else (x1+x2)/2, ly if ly is not None else (y1+y2)/2),
               label, font=font(fs), fill=SLATE, anchor="mm")

def make_architecture(path):
    W, H = 1560, 980
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 28), "CivLink 联机助手 —— 组件架构", font=font(26, True), fill=NAVY)
    d.text((40, 62), "civlink-gui.exe（Tauri 前端） · civlink_ctl.exe（注入控制器） · civlink_hook/client.dll（游戏内 DLL） · civlink-agent.exe（转发/发现）", font=font(14), fill=SOFT)

    gx, gy, gw, gh = 950, 120, 570, 300
    box(d, gx, gy, gw, gh, CARD_R, RED, "游戏进程  CivilizationVI_DX12.exe",
        sub="（服务端或客户端）", fs=18, bold=True)
    box(d, gx+40, gy+80, 220, 90, WHITE, BLUE, "civlink_hook.dll", sub="观测转发（审计）", fs=14)
    box(d, gx+310, gy+80, 220, 90, WHITE, GREEN, "civlink_client.dll", sub="固定出口网卡", fs=14)
    box(d, gx+40, gy+195, 490, 70, CARD_Y, AMBER, "客户端配置 client-iface.txt",
        sub="%LOCALAPPDATA%\\CivLink", fs=13)

    ux, uy, uw, uh = 60, 120, 420, 160
    box(d, ux, uy, uw, uh, CARD_A, BLUE, "civlink-gui.exe（图形界面）",
        sub="三个页签：注入 / 节点发现 / 关于", fs=17, bold=True)
    cx, cy, cw, ch = 60, 330, 420, 120
    box(d, cx, cy, cw, ch, WHITE, NAVY, "civlink_ctl.exe",
        sub="注入 / 卸载 / 状态 / 计数 / 诊断", fs=17, bold=True)

    ax, ay, aw, ah = 950, 480, 570, 170
    box(d, ax, ay, aw, ah, CARD_G, GREEN, "civlink-agent.exe",
        sub="发现补全（服务端转发真实房间广告） · 节点发现（广播+路径探测）", fs=17, bold=True)

    nx, ny, nw, nh = 60, 760, 1460, 150
    d.rounded_rectangle([nx, ny, nx+nw, ny+nh], radius=12, fill=WHITE, outline=BORDER, width=2)
    d.text((nx+30, ny+16), "网络（同一广播域 / Radmin 等 VPN）", font=font(17, True), fill=NAVY)
    d.text((nx+30, ny+52), "UDP 62900  游戏建房广告（客户端发现房间）", font=font(14), fill=SLATE)
    d.text((nx+30, ny+76), "UDP 63010  节点发现广播 · UDP 63011  路径探测 · TCP 62056  数据面", font=font(14), fill=SLATE)
    d.text((nx+30, ny+100), "广播 / 反射按勾选网卡约束（--ifaces / IP_UNICAST_IF）", font=font(14), fill=SOFT)

    arrow(d, ux+uw/2, uy+uh, cx+cw/2, cy, color=NAVY, label="run_ctl", lx=ux+uw/2+30, ly=uy+uh+40)
    arrow(d, cx+cw, cy+40, gx, gy+110, color=BLUE, label="LoadLibrary + CivLinkHookState 轮询", lx=760, ly=gy+60)
    arrow(d, gx+gx, gy+gh, ax, ay, color=GREEN, dashed=True, label="CVLH2 帧（loopback 观测/转发）", lx=880, ly=gy+gh+30)
    arrow(d, ax, ay+20, ux+uw, uy+120, color=GREEN, dashed=True, label="peers-live.json 结果", lx=600, ly=ay-20)
    arrow(d, ax+aw/2, ay+ah, nx+nw/2, ny, color=GREEN, label="63010 广播 / 63011 探测", lx=ax+aw/2+80, ly=ay+ah+30)
    arrow(d, gx+gw/2, gy+gh, nx+nw*0.75, ny, color=RED, label="62900 房间广告", lx=gx+gw/2+10, ly=gy+gh+40)

    img.save(path)
    print("wrote", path)

def make_flow(path):
    W, H = 1560, 1000
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 28), "CivLink 联机助手 —— 使用流程", font=font(26, True), fill=NAVY)
    d.text((40, 62), "左侧=服务端（建房方 A）　右侧=客户端（加入方 B）　全程只需两步注入，其余自动", font=font(14), fill=SOFT)

    def col(cx, cy, items, w=680):
        y = cy
        for fill, outline, title, sub in items:
            box(d, cx, y, w, 78, fill, outline, title, sub=sub, fs=16, bold=(outline in (NAVY, BLUE, GREEN)))
            y += 104
        return y

    host = [
        (CARD_R, RED, "1. 启动游戏（DX11 / DX12）", None),
        (CARD_A, BLUE, "2. 注入：选「服务端」，执行注入", "civlink_ctl inject → civlink_hook.dll 载入游戏"),
        (WHITE, NAVY, "3. 在游戏内创建联机房间", "游戏监听 UDP 62900"),
        (CARD_G, GREEN, "4.（可选）勾选「启用发现补全」", "自动检测房间 → 自动启动 agent 转发真实广告"),
        (WHITE, SLATE, "5. 等待好友加入，开始游戏", None),
    ]
    client = [
        (CARD_R, RED, "1. 启动游戏（DX11 / DX12）", None),
        (CARD_A, BLUE, "2. 注入：选「客户端」，勾选网卡", "civlink_client.dll 固定出口网卡（如 WLAN）"),
        (WHITE, NAVY, "3. 游戏内刷新房间列表", "能看到真实房名（或经补全转发）"),
        (WHITE, GREEN, "4. 加入房间", None),
        (WHITE, SLATE, "5. 开始游戏", None),
    ]
    col(70, 150, host)
    col(830, 150, client)

    d.text((760, 260), "同一广播域", font=font(18, True), fill=NAVY, anchor="mm")
    d.text((760, 296), "或 Radmin VPN", font=font(15), fill=SOFT, anchor="mm")
    d.rounded_rectangle([700, 220, 830, 330], radius=10, outline=BORDER, width=2, fill=WHITE)

    box(d, 70, 720, 1440, 120, CARD_Y, AMBER, "停止流程",
        sub="游戏内退出房间 → 点「卸载注入」→（勾选过补全则自动一并停止 agent）→ 退出游戏", fs=17, bold=True)

    d.text((70, 860), "常见问题：找不到房间 = 广播被 VPN 网卡抢走（客户端固定出口网卡解决） · SmartScreen 弹窗 = 新构建哈希未知（点「仍要运行」一次，或代码签名） · 节点发现 = 想量化网卡质量时用，非联机必需", font=font(13), fill=SOFT)
    img.save(path)
    print("wrote", path)

def make_topology(path):
    W, H = 1560, 900
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 28), "CivLink —— 典型网络拓扑（Windows + Radmin VPN）", font=font(26, True), fill=NAVY)

    ax, ay, aw, ah = 80, 140, 620, 330
    box(d, ax, ay, aw, ah, CARD_A, BLUE, "机器 A（服务端，桌面机）",
        sub="civlink-gui + hook.dll + agent", fs=19, bold=True)
    box(d, ax+40, ay+90, 250, 70, WHITE, NAVY, "WLAN  192.168.31.60", sub="物理无线网卡", fs=14)
    box(d, ax+330, ay+90, 250, 70, WHITE, GREEN, "Radmin VPN  26.74.126.98", sub="虚拟 VPN 网卡", fs=14)
    box(d, ax+40, ay+200, 540, 80, CARD_Y, AMBER, "civlink-agent（发现补全 / 节点发现）",
        sub="勾选网卡约束广播出口", fs=14)

    bx, by, bw, bh = 900, 140, 620, 330
    box(d, bx, by, bw, bh, CARD_G, GREEN, "机器 B（客户端，VM 虚拟机）",
        sub="civlink_client.dll（固定出口网卡）", fs=19, bold=True)
    box(d, bx+40, by+90, 250, 70, WHITE, NAVY, "桥接 ETHERNET0  192.168.31.176", sub="仅勾选这张卡", fs=14)
    box(d, bx+330, by+90, 250, 70, WHITE, GREEN, "Radmin VPN  26.197.96.55", sub="未勾选（metric 更低）", fs=14)
    box(d, bx+40, by+200, 540, 80, WHITE, SLATE, "client-iface.txt → 26.187.101.177 等",
        sub="注入时写入，DLL 据此定向发包", fs=14)

    nx, ny, nw, nh = 80, 540, 1440, 280
    d.rounded_rectangle([nx, ny, nx+nw, ny+nh], radius=12, fill=WHITE, outline=BORDER, width=2)
    d.text((nx+30, ny+16), "二层广播域", font=font(17, True), fill=NAVY)
    d.text((nx+30, ny+52), "62900 房间广告：WLAN 直连（同网段）可发现；跨网段时由 A 的发现补全转发给 B", font=font(14), fill=SLATE)
    d.text((nx+30, ny+78), "节点发现 63010/63011：B 的受限广播默认走 metric 最低的 Radmin（已修复：limited_egress_checked 抑制未勾选出口）", font=font(14), fill=SOFT)
    d.text((nx+30, ny+104), "路径探测：A 的 Radmin ↔ B 的 Radmin 真实可达（同一 VPN）；WLAN ↔ ETHERNET0 真实可达", font=font(14), fill=SLATE)
    d.text((nx+30, ny+130), "62056 数据面：联机后的游戏数据流（不做代理，只观测）", font=font(14), fill=SOFT)

    arrow(d, ax+aw, ay+160, nx+nw/2-80, ny, color=BLUE, label="WLAN 直连", lx=760, ly=ay+200)
    arrow(d, bx, by+160, nx+nw/2+80, ny, color=GREEN, label="桥接直连", lx=1100, ly=by+200)
    arrow(d, ax+620, ay+120, bx, by+120, color=GREEN, dashed=True, label="Radmin VPN 隧道（26.x ↔ 26.x）", lx=790, ly=ay+90)
    img.save(path)
    print("wrote", path)

os.makedirs(r"C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\docs\images", exist_ok=True)
make_architecture(r"C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\docs\images\architecture.png")
make_flow(r"C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\docs\images\usage-flow.png")
make_topology(r"C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\docs\images\topology.png")
