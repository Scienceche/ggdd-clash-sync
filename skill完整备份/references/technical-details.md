# GGDD → Clash Verge: Technical Reference

Reverse-engineering notes from 2026-10-11. GGDD's panel intentionally disables standard
V2Board subscription endpoints, so syncing into Clash requires decrypting their custom
protocol. All findings below were verified working on this machine.

## THE BIG ONE: nodes require GGDD's patched mihomo core

The trojan node list (from either getXorSub or getNXorYaml) contains plain trojan URIs —
but a STOCK mihomo connecting to them gets a **degraded China-egress channel**:
HTTP:80 flows fine (delay tests and 204 smoke tests PASS — dangerously misleading),
while HTTPS:443 to GFW-blocked sites gets silently killed (bing https still works,
matching China-egress behavior exactly). GGDD's own client bundles a custom core:

- Official client = rebranded **Mihomo Party** (Electron, `resources/sidecar/mihomo.exe`).
- Their core reports `Mihomo Meta v1.0.7` — a fake version (real mihomo is 1.19.x),
  built 2026-10-07, go1.24. It speaks a modified trojan handshake; only then do the
  servers grant real foreign egress.
- Deployment on this machine: `D:\Clash_Verge\verge-mihomo-real.exe` (their core) +
  `verge-mihomo.exe` (C# wrapper, source `core-wrapper.cs` in the same dir) +
  `verge-mihomo.exe.orig` (pristine stock core backup).

### Wrapper necessity

CVR v2.5.8 hardcodes `tun: {enable: false, stack: mips}` into every generated config.
Stock mihomo v1.19.x accepts the unknown stack; GGDD's core fatals:
`Parse config error: invalid tun stack`. The wrapper rewrites `stack: mips → stack: mixed`
in the `-f` config (and the config-dir yaml files) before exec'ing the real core, and ties
it to a kill-on-close Job Object so CVR's lifecycle management still works.

### Getting their client (source of the core)

Tutorial page links `http://app.segjw.top/GGDD/Win10/GGDD-4.10.2.exe` (direct, ~127MB).
NSIS installer → `$PLUGINSDIR\app-64.7z` → Electron app → `resources/sidecar/mihomo.exe`.
`app.asar` (new double-header format: JSON at offset 16, len = uint32@12, data at 16+len)
contains the main bundle `out/main/index.js` with all client logic below.

## Official client's real subscription flow (getNXorYaml)

From `out/main/index.js`: for URLs containing `getNXorYaml`, request with headers:

```
Authorization: <JWT auth_data>
User-Agent: MCUbPwUbXBUBKA==
plaform: JCAUKAJCQg==          (sic - typo'd header name, keep it)
XY-Internal-Sub: d
```

GET `http://47.76.147.109/api/v1/user/getNXorYaml` → base64 body; decrypt with
repeating-key XOR where **the key arrives in the response header `XY-Internal-Ckey`**
(e.g. `065f9bcdf9fe7b5699af56aa5f473caf`). Result = a complete Clash YAML (mixed-port
9674, dns disabled, one `GGDD` select group, huge domain rule list, MATCH,GGDD).
Response headers also carry `subscription-userinfo` and `profile-update-interval: 24` (h).

The decoded YAML's node list is IDENTICAL to the getXorSub trojan URI list — same servers,
ports, password, sni. Node drift between the two endpoints has not been observed; prefer
getXorSub + tk (no login) for refreshes, getNXorYaml only when JWT is already available.

## Infrastructure

| Host | Role |
|---|---|
| `http://8.148.178.30` | User panel (dashboard, login). Alibaba Cloud Shenzhen. Domains: ggdd.fun / ggdd.link also seen in history. |
| `http://47.76.147.109` | API + subscription server (Alibaba Cloud HK). Serves the encrypted node list. |

Panel version string: `v2.5.19` (V2Board-derived, heavily customized, Vue frontend).

## Panel API obfuscation

The frontend wraps every API call as:

```
GET http://8.148.178.30/api/v1?api_name=<b64(xor(path))>&method=get&header=<urlencoded {"Authorization":"<JWT>"}>
```

- Encode/decode = Base64 of repeating-key XOR, key (as of 2026-10-11):
  `SIzLm51puIlCewdfDWCgWXQ_Kq-ST242UBEVBhKReO7guLPFH0=`
- The XOR routines are `lr()` (encode path) and `G()` (decode response) inside the main
  bundle `/assets/index-*.js`. Search for the literal `function G(` — the key is the
  base64-ish string constant in the function body. If decryption ever fails, re-fetch the
  bundle and re-extract (the filename hash changes on each frontend deploy).
- Auth = JWT in the `header` query param (raw token, no Bearer prefix), obtained at login.

Known endpoint names (decode the `api_name` values observed on the dashboard/profile pages):
`/guest/comm/app`, `/guest/comm/config`, `/user/info`, `/user/comm/config`, `/user/getStat`,
`/user/getXorSubscribe`, `/user/notice/fetch`, `/user/knowledge/fetch`.

## Getting the subscription token (when profile header is missing)

`/user/getXorSubscribe` (through the encrypted wrapper, requires JWT) returns JSON:

```json
{ "data": { "token": "<YOUR-SUB-TOKEN-32HEX>",
            "uuid": "<YOUR-ACCOUNT-UUID>",
            "encry_subscribe_url": "http://47.76.147.109/api/v1/client/getXorSub?tk=<token>",
            "subscribe_url": "http://127.0.0.1/api/v1/client/subscribe?token=<token>", ... } }
```

Key distinctions:

- `token` (32 hex) = subscription credential, used as `?tk=` on the client endpoint. **This
  is what the update script needs.** Persisted in the profile YAML header comment
  `# sub-token: <token>` for future recovery.
- `uuid` = the trojan password embedded in every node URI. NOT valid as `tk` (server
  answers a layui 404 "无权限访问" HTML page).
- `subscribe_url` host is a `127.0.0.1` placeholder — the real host is the
  `encry_subscribe_url` host. The standard `/api/v1/client/subscribe` path itself is
  disabled server-side (returns literal `error`).

Re-login route (token reset via panel "重置订阅信息" wipes it): open
`http://8.148.178.30/system/dashboard` in the in-app browser, have the user log in
(email + password; do not ask them to paste credentials into chat), then from page context
`fetch()` the wrapper with a freshly built `api_name` for `/user/getXorSubscribe`.

## Client subscription endpoint

```
curl -A "clash-verge/v2.5.8" "http://47.76.147.109/api/v1/client/getXorSub?tk=<token>"
```

- Must use a clash-like User-Agent and must NOT go through the proxy (source IP must be the
  user's China IP; from a proxy exit the server returns 502). Hence curl.exe in the script,
  never `Invoke-WebRequest` (which honors the Windows system proxy that this very setup
  enables).
- Response body = Base64(XOR(trojan URI list)) with the same key as the panel API.

Node URI shape:

```
trojan://<uuid>@<server>:<port>?allowInsecure=0&peer=<sni>&sni=<sni>#<urlencoded-name>
```

~29 nodes: HK/US/SG/JP/TW/KR/CA/DE/UK/FR/AU/BR/VN/TH/MY/TR/IN/MX. Many share entry IPs
(`183.232.55.107` and `*.cneowiv.top`), one port per node.

## Clash Verge Rev integration

- Install: `D:\Clash_Verge\clash-verge.exe` (v2.5.8, mixed-port 7897, socks 7898, http 7899).
- Config dir: `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\`
  - `profiles/ggddSub2026.yaml` — the generated profile (self-healing: header carries the
    sub-token; `.bak` keeps the previous copy).
  - `profiles.yaml` — registers the profile:
    ```yaml
    current: ggddSub2026
    items:
      - uid: ggddSub2026
        type: local
        name: GGDD 会员订阅(29节点)
        file: ggddSub2026.yaml
        updated: <epoch-ms>
    ```
    Write this file as UTF-8 via Node/`.NET WriteAllText`, never via PowerShell
    `Set-Content` with inline `\uXXXX` (PS does not expand those; the name becomes literal
    mojibake).
  - `verge.yaml` — `enable_system_proxy: true` makes the system proxy toggle on at launch.
- Apply changes: the app only reads the profile at activation → stop `clash-verge.exe` +
  `verge-mihomo.exe`, write files, start the exe. The core's own log lives at
  `logs\sidecar\sidecar_latest.log` (activation success shows
  `Start initial compatible provider <group>` lines).

## Config-format gotchas (each one bit us)

1. **Never quote rule targets.** `- MATCH,"🚀 节点选择"` → mihomo looks for a group whose
   name includes the quotes → `proxy not found` → activation fails → core runs empty
   config → every proxied request 502s. Correct: `- MATCH,🚀 节点选择`.
   Group names under `proxy-groups:`/`proxies:` lists may be quoted normally.
2. The empty-looking `config.yaml` in the config root is just CVR's base template; the real
   runtime config is piped to mihomo (external-controller is disabled by default, so no
   HTTP API to probe — read the sidecar log instead).
3. Profile YAML must be UTF-8 (no BOM needed). mihomo handles emoji group names fine.

## Verification

```
curl -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" http://www.gstatic.com/generate_204
```

Expect `204`. Correlate with `sidecar_latest.log`: healthy lines look like
`[TCP] 127.0.0.1:xxxxx --> host:443 match Match using 🚀 节点选择[A香港0]`.
System proxy state: registry `HKCU\...\Internet Settings` → `ProxyEnable=1`,
`ProxyServer=127.0.0.1:7897`.
