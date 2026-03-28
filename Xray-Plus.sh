#!/usr/bin/env bash
# ============================================================
#  Xray-Plus 管理脚本
#  项目地址：https://github.com/Alvin9999-newpac/Xray-Plus
# ============================================================
 
set -Eeuo pipefail
stty erase ^H 2>/dev/null || true
 
# ──────────── 颜色 ────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; PLAIN='\033[0m'
 
ok()   { echo -e " ${GREEN}[OK]${PLAIN}  $*"; }
warn() { echo -e " ${YELLOW}[!!]${PLAIN}  $*"; }
err()  { echo -e " ${RED}[ERR]${PLAIN} $*"; }
info() { echo -e " ${CYAN}--${PLAIN}   $*"; }
 
press_enter() { echo; read -rp " 按 Enter 返回主菜单..." _; }
 
# ──────────── 常量 ────────────
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/xray-plus"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CRED_FILE="${CONFIG_DIR}/.credentials"
SERVICE_FILE="/etc/systemd/system/xray-plus.service"
# ENC 在安装时动态生成（mlkem768x25519plus.native.0rtt.5 + 公钥）
 
REALITY_DOMAINS=(
  "www.microsoft.com"
  "www.bing.com"
  "www.yahoo.com"
  "www.amazon.com"
  "www.swift.org"
  "www.adobe.com"
  "www.cloudflare.com"
)
 
# ──────────── 系统检测 ────────────
detect_arch() {
  case "$(uname -m)" in
    x86_64)  ARCH="64" ;;
    aarch64) ARCH="arm64-v8a" ;;
    armv7l)  ARCH="arm32-v7a" ;;
    *) err "不支持的架构：$(uname -m)"; exit 1 ;;
  esac
}
 
# ──────────── 状态查询 ────────────
get_version() {
  [[ -f "${INSTALL_DIR}/xray" ]] \
    && "${INSTALL_DIR}/xray" version 2>/dev/null | awk 'NR==1{print $2}' \
    || echo "未安装"
}
 
get_status() {
  systemctl is-active xray-plus 2>/dev/null | grep -q "^active" \
    && echo "运行中" || echo "未运行"
}
 
get_bbr() {
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' \
    | grep -q "bbr" && echo "已启用" || echo "未启用"
}
 
get_ip() {
  curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
    || echo "未知"
}
 
# ──────────── 随机工具 ────────────
rand_port() { python3 -c "import random; print(random.randint(10000,65535))"; }
rand_uuid()  { python3 -c "from uuid import uuid4; print(uuid4())"; }
rand_str()   { python3 -c "import random,string; print(''.join(random.choices(string.ascii_letters+string.digits, k=${1})))"; }
rand_hex()   { python3 -c "import random; print(''.join(random.choices('0123456789abcdef', k=${1})))"; }
rand_domain() {
  python3 -c "import random; d=['www.microsoft.com','www.bing.com','www.yahoo.com','www.amazon.com','www.swift.org','www.adobe.com','www.cloudflare.com']; print(random.choice(d))"
}
 
# ──────────── 防火墙 ────────────
open_port() {
  local port=$1 proto=${2:-tcp}
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
    ufw allow "${port}/${proto}" &>/dev/null || true
  fi
  if command -v iptables &>/dev/null; then
    iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
      || iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    command -v netfilter-persistent &>/dev/null \
      && netfilter-persistent save &>/dev/null || true
  fi
}
 
# ──────────── 主菜单 ────────────
show_menu() {
  clear
  local VER STATUS BBR SC BC
  VER=$(get_version); STATUS=$(get_status); BBR=$(get_bbr)
  [[ "$STATUS" == "运行中" ]] && SC="$GREEN" || SC="$RED"
  [[ "$BBR"    == "已启用" ]] && BC="$GREEN" || BC="$YELLOW"
 
  echo -e "${BOLD}${CYAN}"
  echo " ================================================"
  echo "   Xray-Plus 管理脚本 v1.3.0"
  echo "   https://github.com/Alvin9999-newpac/Xray-Plus"
  echo -e " ================================================${PLAIN}"
  printf " %-12s ${BC}%s${PLAIN}\n"   "BBR 加速："  "$BBR"
  printf " %-12s ${SC}%s${PLAIN}\n"   "服务状态："  "$STATUS"
  printf " %-12s ${CYAN}%s${PLAIN}\n" "当前版本："  "$VER"
  echo " ------------------------------------------------"
  echo -e " ${BOLD}1.${PLAIN} 安装 / 重装"
  echo -e " ${BOLD}2.${PLAIN} 查看节点 & 分享链接"
  echo -e " ${BOLD}3.${PLAIN} 重启服务"
  echo -e " ${BOLD}4.${PLAIN} 一键开启 BBR"
  echo -e " ${BOLD}5.${PLAIN} 查看实时日志"
  echo -e " ${BOLD}6.${PLAIN} 卸载"
  echo -e " ${BOLD}0.${PLAIN} 退出"
  echo " ================================================"
  echo
  read -rp " 请输入选项 [0-6]: " CHOICE
}
 
# ──────────── 公共客户端 JSON 片段 ────────────
_client_header() {
  cat <<'JSONEOF'
{
  "log": { "loglevel": "warning" },
  "dns": {
    "hosts": {
      "dns.google":                        ["8.8.8.8","8.8.4.4","2001:4860:4860::8888","2001:4860:4860::8844"],
      "dns.alidns.com":                    ["223.5.5.5","223.6.6.6","2400:3200::1","2400:3200:baba::1"],
      "one.one.one.one":                   ["1.1.1.1","1.0.0.1","2606:4700:4700::1111","2606:4700:4700::1001"],
      "1dot1dot1dot1.cloudflare-dns.com":  ["1.1.1.1","1.0.0.1","2606:4700:4700::1111","2606:4700:4700::1001"],
      "cloudflare-dns.com":                ["104.16.249.249","104.16.248.249","2606:4700::6810:f8f9","2606:4700::6810:f9f9"],
      "dns.cloudflare.com":                ["104.16.132.229","104.16.133.229","2606:4700::6810:84e5","2606:4700::6810:85e5"],
      "dot.pub":                           ["1.12.12.12","120.53.53.53"],
      "doh.pub":                           ["1.12.12.12","120.53.53.53"],
      "dns.quad9.net":                     ["9.9.9.9","149.112.112.112","2620:fe::fe","2620:fe::9"],
      "dns.umbrella.com":                  ["208.67.220.220","208.67.222.222","2620:119:35::35","2620:119:53::53"],
      "engage.cloudflareclient.com":       ["162.159.192.1","2606:4700:d0::a29f:c001"]
    },
    "servers": [
      { "address": "https://dns.alidns.com/dns-query", "domains": ["geosite:private"], "skipFallback": true },
      { "address": "223.5.5.5", "domains": ["full:dns.alidns.com","full:cloudflare-dns.com"], "skipFallback": true },
      "https://cloudflare-dns.com/dns-query"
    ]
  },
  "inbounds": [
    {
      "tag": "socks",
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": false },
      "settings": { "auth": "noauth", "udp": true }
    },
    {
      "tag": "http",
      "port": 1081,
      "listen": "127.0.0.1",
      "protocol": "http",
      "sniffing": { "enabled": true, "destOverride": ["http","tls"], "routeOnly": false },
      "settings": { "auth": "noauth" }
    }
  ],
JSONEOF
}
 
_client_footer() {
  cat <<'JSONEOF'
  ,
  { "tag": "direct", "protocol": "freedom" },
  { "tag": "block",  "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "outboundTag": "block",  "ip":     ["geoip:private"] },
      { "type": "field", "outboundTag": "direct", "domain": ["geosite:private"] },
      { "type": "field", "outboundTag": "proxy",  "port":   "0-65535" }
    ]
  }
}
JSONEOF
}
 
# ──────────── 配置展示 ────────────
_show_config() {
  [[ ! -f "$CRED_FILE" ]] && { warn "未找到凭据，请先安装"; return; }
  source "$CRED_FILE"
  local IP; IP=$(get_ip)
 
  # VMess base64 链接
  local VMESS_JSON L6
  VMESS_JSON="{\"v\":\"2\",\"ps\":\"VMess-ws\",\"add\":\"${IP}\",\"port\":\"${P6}\",\"id\":\"${UUID6}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"${PATH6}\",\"tls\":\"\"}"
  L6="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
 
  # ── 分享链接汇总 ──────────────────────────────────────────
  echo -e "\n${BOLD}${GREEN} ========== 节点分享链接 ==========${PLAIN}\n"
 
  echo -e " ${BOLD}${CYAN}[1] VLESS-xhttp-Reality-Vision-enc${PLAIN}"
  echo " vless://${UUID1}@${IP}:${P1}?security=reality&flow=xtls-rprx-vision&pbk=${PBK}&sid=${SID}&sni=${SNI}&fp=chrome&type=xhttp&path=${PATH1}&mode=auto&encryption=${ENC}#VLESS-xhttp-Reality-Vision-enc"
  echo
  echo -e " ${BOLD}${CYAN}[2] VLESS-xhttp-Reality-Vision${PLAIN}"
  echo " vless://${UUID2}@${IP}:${P2}?encryption=none&security=reality&pbk=${PBK}&sid=${SID}&sni=${SNI}&fp=chrome&type=xhttp&path=${PATH2}#VLESS-xhttp-Reality-Vision"
  echo
  echo -e " ${BOLD}${CYAN}[3] VLESS-tcp-Reality-Vision${PLAIN}"
  echo " vless://${UUID3}@${IP}:${P3}?security=reality&flow=xtls-rprx-vision&pbk=${PBK}&sid=${SID}&sni=${SNI}&fp=chrome&type=tcp#VLESS-tcp-Reality-Vision"
  echo
  echo -e " ${BOLD}${CYAN}[4] VLESS-xhttp-Vision-enc${PLAIN}"
  echo " vless://${UUID4}@${IP}:${P4}?security=none&flow=xtls-rprx-vision&type=xhttp&path=${PATH4}&mode=auto&encryption=${ENC}#VLESS-xhttp-Vision-enc"
  echo
  echo -e " ${BOLD}${CYAN}[5] VLESS-ws-Vision-enc${PLAIN}"
  echo " vless://${UUID5}@${IP}:${P5}?security=none&flow=xtls-rprx-vision&type=ws&path=${PATH5}&encryption=${ENC}#VLESS-ws-Vision-enc"
  echo
  echo -e " ${BOLD}${CYAN}[6] VMess-ws${PLAIN}"
  echo " ${L6}"
  echo
  echo -e " ${BOLD}${CYAN}[7] VLESS-xhttp3-Reality-Vision-force-brutal${PLAIN}"
  echo " vless://${UUID7}@${IP}:${P7}?security=reality&flow=xtls-rprx-vision&pbk=${PBK}&sid=${SID}&sni=${SNI}&fp=chrome&type=xhttp&path=${PATH7}&mode=auto#VLESS-xhttp3-Reality-Vision-brutal"
  echo
  echo -e " ${BOLD}${CYAN}[8] VLESS-xhttp3-Reality-Vision-force-brutal-enc${PLAIN}"
  echo " vless://${UUID8}@${IP}:${P8}?security=reality&flow=xtls-rprx-vision&pbk=${PBK}&sid=${SID}&sni=${SNI}&fp=chrome&type=xhttp&path=${PATH8}&mode=auto&encryption=${ENC}#VLESS-xhttp3-Reality-Vision-brutal-enc"
 
  echo -e "\n${BOLD}${GREEN} ==================================${PLAIN}\n"
 
  # ── 客户端 config.json ────────────────────────────────────
  echo -e "${BOLD}${GREEN} ========== 客户端 config.json ==========${PLAIN}"
  echo -e " ${YELLOW}（socks 1080 / http 1081，私有IP直连，其余走代理）${PLAIN}\n"
 
  # 节点1：VLESS-xhttp-Reality-Vision-enc
  echo -e " ${BOLD}${CYAN}---- [1] VLESS-xhttp-Reality-Vision-enc ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P1},
          "users": [{ "id": "${UUID1}", "flow": "xtls-rprx-vision", "encryption": "${ENC}" }]
        }]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": { "serverName": "${SNI}", "fingerprint": "chrome", "publicKey": "${PBK}", "shortId": "${SID}" },
        "xhttpSettings": { "path": "${PATH1}", "mode": "auto" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点2：VLESS-xhttp-Reality-Vision
  echo -e " ${BOLD}${CYAN}---- [2] VLESS-xhttp-Reality-Vision ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P2},
          "users": [{ "id": "${UUID2}", "flow": "xtls-rprx-vision", "encryption": "none" }]
        }]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": { "serverName": "${SNI}", "fingerprint": "chrome", "publicKey": "${PBK}", "shortId": "${SID}" },
        "xhttpSettings": { "path": "${PATH2}" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点3：VLESS-tcp-Reality-Vision
  echo -e " ${BOLD}${CYAN}---- [3] VLESS-tcp-Reality-Vision ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P3},
          "users": [{ "id": "${UUID3}", "flow": "xtls-rprx-vision", "encryption": "none" }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": { "serverName": "${SNI}", "fingerprint": "chrome", "publicKey": "${PBK}", "shortId": "${SID}" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点4：VLESS-xhttp-plain-enc（无TLS，需反代）
  echo -e " ${BOLD}${CYAN}---- [4] VLESS-xhttp-Vision-enc（无TLS，建议套反代）----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P4},
          "users": [{ "id": "${UUID4}", "flow": "xtls-rprx-vision", "encryption": "${ENC}" }]
        }]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "${PATH4}", "mode": "auto" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点5：VLESS-ws-plain-enc（无TLS，需反代）
  echo -e " ${BOLD}${CYAN}---- [5] VLESS-ws-Vision-enc（无TLS，建议套反代）----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P5},
          "users": [{ "id": "${UUID5}", "flow": "xtls-rprx-vision", "encryption": "${ENC}" }]
        }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${PATH5}" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点6：VMess-ws
  echo -e " ${BOLD}${CYAN}---- [6] VMess-ws ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P6},
          "users": [{ "id": "${UUID6}", "alterId": 0, "security": "auto" }]
        }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${PATH6}" }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点7：VLESS-xhttp3-Reality-Vision-force-brutal
  echo -e " ${BOLD}${CYAN}---- [7] VLESS-xhttp3-Reality-Vision-force-brutal ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P7},
          "users": [{ "id": "${UUID7}", "flow": "xtls-rprx-vision", "encryption": "none" }]
        }]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": { "serverName": "${SNI}", "fingerprint": "chrome", "publicKey": "${PBK}", "shortId": "${SID}" },
        "xhttpSettings": { "path": "${PATH7}", "mode": "auto" },
        "finalmask": { "quicParams": { "congestion": "force-brutal", "brutalUp": 100 } }
      }
    }
EOF
  _client_footer
  echo
 
  # 节点8：VLESS-xhttp3-Reality-Vision-force-brutal-enc
  echo -e " ${BOLD}${CYAN}---- [8] VLESS-xhttp3-Reality-Vision-force-brutal-enc ----${PLAIN}"
  _client_header
  cat <<EOF
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "${IP}",
          "port": ${P8},
          "users": [{ "id": "${UUID8}", "flow": "xtls-rprx-vision", "encryption": "${ENC}" }]
        }]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": { "serverName": "${SNI}", "fingerprint": "chrome", "publicKey": "${PBK}", "shortId": "${SID}" },
        "xhttpSettings": { "path": "${PATH8}", "mode": "auto" },
        "finalmask": { "quicParams": { "congestion": "force-brutal", "brutalUp": 100 } }
      }
    }
EOF
  _client_footer
  echo
 
  echo -e "${BOLD}${GREEN} ==========================================${PLAIN}\n"
}
 
# ──────────── 1. 安装 ────────────
do_install() {
  clear
  echo -e "${BOLD}${CYAN}===== 安装 Xray =====${PLAIN}\n"
  detect_arch
 
  for dep in curl unzip python3; do
    command -v "$dep" &>/dev/null || {
      apt-get install -y "$dep" &>/dev/null \
        || yum install -y "$dep" &>/dev/null || true
    }
  done
 
  # 获取最新版本
  info "获取最新版本..."
  local TAG
  TAG=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"\(v[^"]*\)".*/\1/')
  [[ -z "$TAG" ]] && { err "获取版本失败"; press_enter; return; }
  ok "最新版本：${TAG}"
 
  # 下载安装
  local PKG="Xray-linux-${ARCH}.zip"
  local URL="https://github.com/XTLS/Xray-core/releases/download/${TAG}/${PKG}"
  local TMP; TMP=$(mktemp -d); trap "rm -rf $TMP" RETURN
 
  info "下载 ${PKG}..."
  curl -fSL --progress-bar -o "${TMP}/${PKG}" "$URL" \
    || { err "下载失败"; press_enter; return; }
 
  info "解压安装..."
  unzip -o "${TMP}/${PKG}" -d "${TMP}/xray" &>/dev/null
  install -m 755 "${TMP}/xray/xray" "${INSTALL_DIR}/xray"
  ok "安装完成：$(get_version)"
 
  # 生成 Reality 密钥对
  mkdir -p "$CONFIG_DIR"
  info "生成 Reality 密钥对..."
  local X25519_OUT PRK PBK
  X25519_OUT=$("${INSTALL_DIR}/xray" x25519 2>/dev/null)
  # 兼容各版本输出格式：
  #   旧版：  Private key: xxx  /  Public key: xxx
  #   中版：  PrivateKey: xxx   /  Password: xxx
  #   新版(v26.3.27+)：PrivateKey: xxx  /  Password (PublicKey): xxx
  # 注意：新版 "Password (PublicKey):" 用 awk '{print $NF}' 可直接取最后一列，兼容所有格式
  PRK=$(echo "$X25519_OUT" | grep -E "^(Private key|PrivateKey):" | awk '{print $NF}')
  PBK=$(echo "$X25519_OUT" | grep -E "^(Public key|Password)" | awk '{print $NF}')
 
  if [[ -z "$PRK" || -z "$PBK" ]]; then
    err "Reality 密钥生成失败，原始输出："
    echo "$X25519_OUT"
    press_enter; return
  fi
  ok "Reality 密钥对生成成功"
 
  # 用 xray vlessenc 命令生成 VLESS 后量子加密密钥对
  info "生成 VLESS ENC 加密密钥..."
  local VLENC_OUT DEKEY ENKEY
  VLENC_OUT=$("${INSTALL_DIR}/xray" vlessenc 2>/dev/null)
  # vlessenc 输出两段 JSON：第1段是服务端（含 decryption），第2段是客户端（含 encryption）
  # 用 grep 取最后一次出现的对应字段值（客户端侧）
  DEKEY=$(echo "$VLENC_OUT" | grep '"decryption":' | tail -1 | grep -oP '(?<="decryption": ")[^"]+')
  ENKEY=$(echo "$VLENC_OUT" | grep '"encryption":' | tail -1 | grep -oP '(?<="encryption": ")[^"]+')  # 若 grep -P 不可用（如 macOS），回退到 awk
  [[ -z "$DEKEY" ]] && DEKEY=$(echo "$VLENC_OUT" | grep '"decryption":' | tail -1 | awk -F'"' '{print $4}')
  [[ -z "$ENKEY" ]] && ENKEY=$(echo "$VLENC_OUT" | grep '"encryption":' | tail -1 | awk -F'"' '{print $4}')
  if [[ -z "$ENKEY" || -z "$DEKEY" ]]; then
    err "vlessenc 密钥生成失败，原始输出："
    echo "$VLENC_OUT"
    press_enter; return
  fi
  ok "VLESS ENC 密钥生成成功"
  local ENC="$ENKEY"
 
  local SID; SID=$(rand_hex 8)
  local SNI; SNI=$(rand_domain)
  ok "Reality SNI：${SNI}"
 
  # 生成账号和端口
  info "自动生成 6 个节点账号..."
  local UUID1 UUID2 UUID3 UUID4 UUID5 UUID6 UUID7 UUID8
  local P1 P2 P3 P4 P5 P6 P7 P8
  local PATH1 PATH2 PATH4 PATH5 PATH6 PATH7 PATH8
  UUID1=$(rand_uuid); UUID2=$(rand_uuid); UUID3=$(rand_uuid)
  UUID4=$(rand_uuid); UUID5=$(rand_uuid); UUID6=$(rand_uuid)
  UUID7=$(rand_uuid); UUID8=$(rand_uuid)
  P1=$(rand_port);    P2=$(rand_port);    P3=$(rand_port)
  P4=$(rand_port);    P5=$(rand_port);    P6=$(rand_port)
  P7=$(rand_port);    P8=$(rand_port)
  PATH1="/$(rand_str 8)"; PATH2="/$(rand_str 8)"
  PATH4="/$(rand_str 8)"; PATH5="/$(rand_str 8)"; PATH6="/$(rand_str 8)"
  PATH7="/$(rand_str 8)"; PATH8="/$(rand_str 8)"
 
  # 写配置文件
  info "写入服务端配置..."
  cat > "$CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-xhttp-reality-enc",
      "listen": "0.0.0.0",
      "port": ${P1},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID1}", "flow": "xtls-rprx-vision" }],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRK}",
          "shortIds": ["${SID}"]
        },
        "xhttpSettings": { "path": "${PATH1}", "mode": "auto" }
      }
    },
    {
      "tag": "vless-xhttp-reality",
      "listen": "0.0.0.0",
      "port": ${P2},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID2}" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRK}",
          "shortIds": ["${SID}"]
        },
        "xhttpSettings": { "path": "${PATH2}" }
      }
    },
    {
      "tag": "vless-tcp-reality",
      "listen": "0.0.0.0",
      "port": ${P3},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID3}", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRK}",
          "shortIds": ["${SID}"]
        }
      }
    },
    {
      "tag": "vless-xhttp-plain-enc",
      "listen": "0.0.0.0",
      "port": ${P4},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID4}", "flow": "xtls-rprx-vision" }],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "${PATH4}", "mode": "auto" }
      }
    },
    {
      "tag": "vless-ws-plain-enc",
      "listen": "0.0.0.0",
      "port": ${P5},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID5}", "flow": "xtls-rprx-vision" }],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${PATH5}" }
      }
    },
    {
      "tag": "vmess-ws-plain",
      "listen": "0.0.0.0",
      "port": ${P6},
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID6}", "alterId": 0 }]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${PATH6}" }
      }
    },
    {
      "tag": "vless-xhttp3-reality-brutal",
      "listen": "0.0.0.0",
      "port": ${P7},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID7}", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRK}",
          "shortIds": ["${SID}"]
        },
        "xhttpSettings": { "path": "${PATH7}", "mode": "auto" }
      }
    },
    {
      "tag": "vless-xhttp3-reality-brutal-enc",
      "listen": "0.0.0.0",
      "port": ${P8},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID8}", "flow": "xtls-rprx-vision" }],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRK}",
          "shortIds": ["${SID}"]
        },
        "xhttpSettings": { "path": "${PATH8}", "mode": "auto" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF
  ok "配置写入完成"
 
  # 保存凭据
  cat > "$CRED_FILE" <<EOF
UUID1=${UUID1}
UUID2=${UUID2}
UUID3=${UUID3}
UUID4=${UUID4}
UUID5=${UUID5}
UUID6=${UUID6}
UUID7=${UUID7}
UUID8=${UUID8}
P1=${P1}
P2=${P2}
P3=${P3}
P4=${P4}
P5=${P5}
P6=${P6}
P7=${P7}
P8=${P8}
PATH1=${PATH1}
PATH2=${PATH2}
PATH4=${PATH4}
PATH5=${PATH5}
PATH6=${PATH6}
PATH7=${PATH7}
PATH8=${PATH8}
PBK=${PBK}
SID=${SID}
SNI=${SNI}
ENC=${ENC}
DEKEY=${DEKEY}
EOF
  chmod 600 "$CRED_FILE"
 
  # systemd 服务
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray-Plus Proxy Server
After=network.target
 
[Service]
Type=simple
ExecStart=${INSTALL_DIR}/xray run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
 
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable xray-plus &>/dev/null
 
  # 防火墙
  info "放行防火墙端口..."
  for port in $P1 $P2 $P3 $P4 $P5 $P6 $P7 $P8; do
    open_port "$port" tcp
  done
  ok "防火墙放行完成"
 
  # 启动
  systemctl start xray-plus
  sleep 2
  local ST; ST=$(get_status)
  if [[ "$ST" == "运行中" ]]; then
    ok "服务状态：运行中"
  else
    err "服务启动失败，错误日志："
    journalctl -u xray-plus -n 15 --no-pager -o cat 2>/dev/null || true
    press_enter; return
  fi
 
  _show_config
  press_enter
}
 
# ──────────── 2. 查看节点 ────────────
do_show() {
  clear
  echo -e "${BOLD}${CYAN}===== 节点信息 & 分享链接 =====${PLAIN}\n"
  [[ ! -f "${INSTALL_DIR}/xray" ]] && { err "Xray 未安装"; press_enter; return; }
  _show_config
  press_enter
}
 
# ──────────── 3. 重启 ────────────
do_restart() {
  clear
  echo -e "${BOLD}${CYAN}===== 重启服务 =====${PLAIN}\n"
  [[ ! -f "${INSTALL_DIR}/xray" ]] && { err "Xray 未安装"; press_enter; return; }
  systemctl restart xray-plus
  sleep 2; ok "重启完成，状态：$(get_status)"
  press_enter
}
 
# ──────────── 4. BBR ────────────
do_bbr() {
  clear
  echo -e "${BOLD}${CYAN}===== 开启 BBR =====${PLAIN}\n"
  [[ "$(get_bbr)" == "已启用" ]] && { ok "BBR 已启用"; press_enter; return; }
 
  local MAJOR MINOR
  MAJOR=$(uname -r | cut -d. -f1); MINOR=$(uname -r | cut -d. -f2)
  if [[ $MAJOR -lt 4 ]] || { [[ $MAJOR -eq 4 ]] && [[ $MINOR -lt 9 ]]; }; then
    err "内核 $(uname -r) 版本过低，需 4.9+"; press_enter; return
  fi
  grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null \
    || echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
  modprobe tcp_bbr 2>/dev/null || true
  grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf \
    || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf \
    || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p &>/dev/null
  ok "BBR 已开启：$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
  press_enter
}
 
# ──────────── 5. 日志 ────────────
do_logs() {
  clear
  echo -e "${BOLD}${CYAN}===== 实时日志（Ctrl+C 退出）=====${PLAIN}\n"
  [[ ! -f "${INSTALL_DIR}/xray" ]] && { err "Xray 未安装"; press_enter; return; }
  journalctl -u xray-plus -f --no-hostname -o cat
}
 
# ──────────── 6. 卸载 ────────────
do_uninstall() {
  clear
  echo -e "${BOLD}${RED}===== 卸载 Xray =====${PLAIN}\n"
  [[ ! -f "${INSTALL_DIR}/xray" ]] && { warn "Xray 未安装"; press_enter; return; }
  read -rp " 确认卸载？[y/N]: " _c
  [[ "${_c,,}" != "y" ]] && { press_enter; return; }
  systemctl stop xray-plus &>/dev/null || true
  systemctl disable xray-plus &>/dev/null || true
  rm -f "$SERVICE_FILE"; systemctl daemon-reload
  rm -f "${INSTALL_DIR}/xray"
  rm -rf "$CONFIG_DIR"
  ok "Xray 已卸载"
  press_enter
}
 
# ──────────── 入口 ────────────
[[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 权限运行：sudo bash $0${PLAIN}"; exit 1; }
 
while true; do
  show_menu
  case "$CHOICE" in
    1) do_install   ;;
    2) do_show      ;;
    3) do_restart   ;;
    4) do_bbr       ;;
    5) do_logs      ;;
    6) do_uninstall ;;
    0) echo -e "\n 再见！\n"; exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
