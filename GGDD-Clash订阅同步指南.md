# GGDD × Clash Verge 订阅同步指南

> 更新日期:2026-10-11(第 2 版,包含内核修复方案) | 适用:本机 Clash Verge Rev v2.5.8
> 背景:GGDD 关闭了标准订阅接口,且**节点必须配合他们的定制内核才能正常翻墙**。
> 标准内核连节点只会得到"国内出口"的降级通道(HTTP 通、HTTPS 全废)。
> 本方案已完整部署并验证:Google / GitHub / YouTube 全部 200。

---

## 一、当前状态

| 项目 | 值 |
|------|-----|
| Clash Verge | `D:\Clash_Verge\clash-verge.exe`(v2.5.8) |
| **GGDD 定制内核** | `D:\Clash_Verge\verge-mihomo-real.exe`(**核心!不能删**) |
| **内核包装器** | `D:\Clash_Verge\verge-mihomo.exe`(源码 core-wrapper.cs 同目录) |
| 原版内核备份 | `D:\Clash_Verge\verge-mihomo.exe.orig` |
| 配置文件 | `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\ggddSub2026.yaml` |
| 节点 | 29 个 Trojan 节点(香港/美国/新加坡/日本/台湾/韩国等) |
| 代理端口 | 7897(HTTP+SOCKS 混合) |
| 系统代理 | 已开启,随 Clash Verge 自动打开 |
| 分流 | 国内直连 + 国外走代理 |

## 二、工作原理(为什么这么复杂)

GGDD 的节点是"魔改 Trojan"协议:

1. **用标准 Clash 内核连接** → 隧道能建立,但服务端只给你一个**国内出口的降级通道**:
   - HTTP 网站能通(所以"测速 204"是绿的,极具迷惑性)
   - HTTPS 到 Google/GitHub 全部被掐(表现和 GFW 一模一样)
2. **用 GGDD 官方客户端的定制内核连接** → 私有握手认证通过 → 真实境外出口

所以本方案从 GGDD 官方客户端(实为换皮 Mihomo Party)里提取了他们的定制内核,
并做了一个 C# 包装器嵌进 Clash Verge:

```
Clash Verge(界面/系统代理)
   └─ verge-mihomo.exe(包装器:修正配置兼容性)
        └─ verge-mihomo-real.exe(GGDD 定制内核:私有协议认证)
             └─ 29 个节点 → 真实境外出口 ✅
```

包装器的作用:CVR 生成的配置里有个 `tun: stack: mips` 的哨兵值,官方内核宽容、
GGDD 内核会直接崩溃,包装器在启动前把它改成合法值。

## 三、日常使用

- **开关代理**:Clash Verge 主界面「系统代理」开关(或托盘图标)
- **切换节点**:「代理」→「🚀 节点选择」分组;默认「♻️ 自动选择」自动挑最快
- **测速**:「代理」页顶部 ⚡(现在测出的都是真实延迟了)

## 四、更新订阅 / 排查问题

**最简单:直接跟 ZCode 说**「更新 ggdd 订阅」或「google 打不开了」,
skill 会自动处理(含下表的全部场景)。

**手动刷新节点:**

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Admin\.agents\skills\ggdd-clash-sync\scripts\update-ggdd.ps1"
```

**常见问题速查:**

| 现象 | 原因 | 解决 |
|------|------|------|
| Google/GitHub 打不开,但测速是绿的 | Clash Verge 更新后用回原版内核(覆盖了包装器) | 重编译包装器(见下节),或找 ZCode |
| 内核起不来,日志 `invalid tun stack` | 包装器丢失 | 同上 |
| 个别节点超时 | 节点波动 | 换节点或跑更新脚本 |
| 全部节点失效 | GGDD 换服务器 | 跑更新脚本或找 ZCode |

**修复包装器(仅当 CVR 更新后代理失效时用):**

```bat
cd /d D:\Clash_Verge
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /out:verge-mihomo.exe core-wrapper.cs
```
(前提:`verge-mihomo-real.exe` 还在;若被删,从 GGDD 官方客户端安装包里再提取,或找 ZCode)

## 五、验证代理是否真的能用

⚠️ 教训:HTTP 测试(204)在降级通道下也是通的,**不能作为验证标准**。必须测 HTTPS:

```bash
curl -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" https://github.com     # 期望 200
curl -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" https://www.google.com # 期望 200/302
```

## 六、相关文件

| 文件 | 说明 |
|------|------|
| `~\.agents\skills\ggdd-clash-sync\` | ZCode skill(入口 SKILL.md + 更新脚本 + 逆向笔记) |
| `D:\Clash_Verge\verge-mihomo-real.exe` | GGDD 定制内核(从官方客户端提取) |
| `D:\Clash_Verge\core-wrapper.cs` | 包装器源码(修复用) |
| `%APPDATA%\...\profiles\ggddSub2026.yaml` | 当前配置(含 token,勿外传) |

> ⚠️ 配置里的 token 和密码等同账号凭证,不要外传。
> ⚠️ 不要手动升级 Clash Verge 的「内核」(设置里的内核更新会覆盖定制内核)。
