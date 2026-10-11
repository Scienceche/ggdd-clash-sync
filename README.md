# GGDD × Clash Verge 订阅同步方案

> 机场关闭标准订阅接口 + 节点强制要求定制内核的情况下,把订阅接入标准 Clash Verge 的完整逆向方案。

## 这是什么

某机场(代号 GGDD)做了三层防护:

1. **关闭标准订阅接口** —— V2Board 的 /client/subscribe 返回 error,只开放自家的 XOR+Base64 加密接口
2. **面板 API 全混淆** —— 接口名和响应都经过 repeating-key XOR 加密,密钥藏在前端 JS 里
3. **节点协议魔改** —— 用标准 mihomo 内核连节点,只给"国内出口"的降级通道(HTTP 通、HTTPS 全废);
   只有他们官方客户端里定制的 mihomo 内核(私有 trojan 握手)才能拿到真实境外出口

本方案逐层破解并落地:

- 🔓 解密订阅,提取 29 个 trojan 节点,生成标准 Clash 配置
- 🔍 从官方客户端安装包(NSIS → 7z → Electron asar)提取定制内核
- 🔧 写 C# 包装器嵌入 Clash Verge(解决 `tun: stack: mips` 兼容性问题),界面/系统代理照常使用
- ✅ 最终验证:Google / GitHub / YouTube 全部 HTTP 200

## 目录结构

| 文件 | 说明 |
|------|------|
| `GGDD-Clash订阅同步指南.md` | 面向使用者的完整指南(日常使用/排查/修复) |
| `skill完整备份/SKILL.md` | ZCode 技能入口(说"更新ggdd订阅"自动执行全流程) |
| `skill完整备份/scripts/update-ggdd.ps1` | 一键更新脚本(取订阅→解密→重写配置→重启→验证) |
| `skill完整备份/scripts/core-wrapper.cs` | C# 内核包装器源码(2026-10-12 重写版,见下) |
| `skill完整备份/references/technical-details.md` | 完整逆向笔记(接口协议/密钥提取/内核分析/踩坑记录) |

## 技术要点速览

- 订阅解密:Base64 + repeating-key XOR(密钥可从前端 JS 的 `function G(` 处重新提取)
- 官方完整配置接口 getNXorYaml 需要特殊请求头(`User-Agent: MCUbPwUbXBUBKA==` 等),
  解密密钥在响应头 `XY-Internal-Ckey` 里动态下发
- 定制内核识别技巧:版本号造假("v1.0.7",真实 mihomo 是 1.19.x)+ 编译时间新
- 判断节点是"降级通道"的鉴别法:bing 的 HTTPS 能通但 google/github 不通 = 国内出口特征

## 第二台机器部署记录(2026-10-12)

原仓库缺少 `core-wrapper.cs` 源码,换机重部署时按 technical-details.md 的行为描述重写并验证通过:

- 重写的包装器行为与文档一致:改写 `-f` 配置与 `-d` 目录下 yaml 的 `stack: mips → stack: mixed`,
  透传全部命令行参数给 `verge-mihomo-real.exe`,并把子进程挂进 kill-on-close Job Object
- 本机差异:安装目录 `D:\Clash Verge`(带空格)、用户目录 `C:\Users\<user>`,
  `update-ggdd.ps1` 用 `-VergeExe` 参数覆盖默认路径即可,无需改脚本
- 定制内核直接从已安装的官方客户端 `D:\GGDD\resources\sidecar\mihomo.exe` 复制,
  不必再解 NSIS 安装包
- 编译命令(路径含空格时加引号):
  `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /out:verge-mihomo.exe core-wrapper.cs`
- 验证结果:Google/GitHub/YouTube/Wikipedia 全部 200,百度直连 200

## 声明

- 本仓库仅作为个人技术研究的记录与备份,**已脱敏**(不含任何账号凭证)
- 文档中的密钥/接口信息源自公开的前端代码分析
