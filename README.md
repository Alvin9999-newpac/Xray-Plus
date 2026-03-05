# Xray-Plus

Xray 一键管理脚本，自动搭建 6 种协议节点，支持 Reality、xhttp 传输、后量子加密（ENC）。

---

## 特性

- 一键安装，全程无需手动填写配置
- 自动生成 6 个节点，每个节点独立 UUID 和随机端口
- Reality 伪装域名从苹果、微软、必应、雅虎等大网站随机选取
- 支持后量子加密算法（mlkem768x25519plus）
- 自动生成 Reality 密钥对和 VLESS ENC 密钥对
- 安装完成后直接输出所有节点分享链接，可直接导入客户端
- 自动配置防火墙（支持 ufw / iptables）
- 支持 BBR 加速一键开启
- VPS 重启后服务自动恢复（systemd 托管）
- 支持 Debian / Ubuntu / CentOS / Rocky Linux

---

## 使用方法

**wget 方式：**

```bash
wget -O xray-plus.sh https://raw.githubusercontent.com/Alvin9999-newpac/Xray-Plus/main/xray-plus.sh && chmod +x xray-plus.sh && bash xray-plus.sh
```

**curl 方式：**

```bash
curl -fsSL -o xray-plus.sh https://raw.githubusercontent.com/Alvin9999-newpac/Xray-Plus/main/xray-plus.sh && chmod +x xray-plus.sh && bash xray-plus.sh
```

---

## 菜单说明

```
 ================================================
   Xray-Plus 管理脚本
   https://github.com/Alvin9999-newpac/Xray-Plus
 ================================================
 BBR 加速：  已启用
 服务状态：  运行中
 当前版本：  v26.2.6
 ------------------------------------------------
 1. 安装 / 重装
 2. 查看节点 & 分享链接
 3. 重启服务
 4. 一键开启 BBR
 5. 查看实时日志
 6. 卸载
 0. 退出
 ================================================
```

| 选项 | 说明 |
|------|------|
| 1 | 自动下载最新版 Xray，生成 6 个节点并启动服务 |
| 2 | 查看所有节点分享链接 |
| 3 | 重启 Xray 服务 |
| 4 | 一键开启 BBR 网络加速（需内核 4.9+） |
| 5 | 实时查看 Xray 运行日志（Ctrl+C 退出） |
| 6 | 卸载 Xray 及所有配置文件 |

---

## 节点说明

安装完成后自动生成 6 个节点：

| # | 节点 | 传输 | 安全 | 特性 |
|---|------|------|------|------|
| 1 | VLESS-xhttp-Reality-Vision-enc | xhttp | Reality | 后量子加密 ENC |
| 2 | VLESS-xhttp-Reality-Vision | xhttp | Reality | 标准 xhttp |
| 3 | VLESS-tcp-Reality-Vision | TCP | Reality | 兼容性最好 |
| 4 | VLESS-xhttp-Vision-enc | xhttp | 无 TLS | 后量子加密 ENC |
| 5 | VLESS-ws-Vision-enc | WebSocket | 无 TLS | 后量子加密 ENC |
| 6 | VMess-ws | WebSocket | 无 TLS | VMess 传统加密（抗封锁性不高） |

---

## 安装效果示例

```
 ========== 节点分享链接 ==========

 [1] VLESS-xhttp-Reality-Vision-enc
 vless://uuid@ip:port?security=reality&flow=xtls-rprx-vision&...&encryption=mlkem768x25519plus...#VLESS-xhttp-Reality-Vision-enc

 [2] VLESS-xhttp-Reality-Vision
 vless://uuid@ip:port?encryption=none&security=reality&...&type=xhttp&...#VLESS-xhttp-Reality-Vision

 [3] VLESS-tcp-Reality-Vision
 vless://uuid@ip:port?security=reality&flow=xtls-rprx-vision&...&type=tcp#VLESS-tcp-Reality-Vision

 [4] VLESS-xhttp-Vision-enc
 vless://uuid@ip:port?security=none&flow=xtls-rprx-vision&type=xhttp&...&encryption=mlkem768x25519plus...#VLESS-xhttp-Vision-enc

 [5] VLESS-ws-Vision-enc
 vless://uuid@ip:port?security=none&flow=xtls-rprx-vision&type=ws&...&encryption=mlkem768x25519plus...#VLESS-ws-Vision-enc

 [6] VMess-ws
 vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3Mtd3MiLCJhZGQi...

 ==================================
```

---

## 客户端使用

### 推荐客户端

**桌面端（Windows / macOS / Linux）**
- [v2rayN](https://github.com/2dust/v2rayN/releases)（Windows，需 6.x 以上支持 xhttp）
- [NekoRay](https://github.com/MatsuriDayo/nekoray/releases)（Windows / Linux）
- [Clash Verge Rev](https://www.clashverge.dev/)（支持节点 3、5、6）

**Android**
- [v2rayNG](https://github.com/2dust/v2rayNG/releases)
- [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases)

**iOS**
- [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)
- [Stash](https://apps.apple.com/app/stash/id1596063349)

> **提示：** 节点 1、2、4 使用 xhttp 传输，需要客户端 Xray 内核版本较新才支持。如遇不兼容，优先使用节点 3（TCP+Reality）。

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Debian 10+ / Ubuntu 20.04+ / CentOS 7+ / Rocky Linux 8+ |
| 架构 | x86_64 / aarch64 |
| 内存 | 128MB 以上 |
| 权限 | root |

---

## 常用命令

```bash
# 查看服务状态
systemctl status xray-plus

# 查看日志
journalctl -u xray-plus -f

# 手动启动 / 停止 / 重启
systemctl start xray-plus
systemctl stop xray-plus
systemctl restart xray-plus

# 查看配置文件
cat /etc/xray-plus/config.json
```

---

## 相关项目

- [Xray-core](https://github.com/XTLS/Xray-core) — 本脚本所使用的代理核心
- [Mieru-Plus](https://github.com/Alvin9999-newpac/Mieru-Plus) — mieru 一键脚本
- [Juicity-Plus](https://github.com/Alvin9999-newpac/Juicity-Plus) — juicity 一键脚本
- [Sing-Box-Plus](https://github.com/Alvin9999-newpac/Sing-Box-Plus) — sing-box 一键脚本

---

## License

MIT
