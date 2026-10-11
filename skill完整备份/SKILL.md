---
name: ggdd-clash-sync
description: Refresh the user's GGDD airport subscription into Clash Verge Rev on this Windows machine, and maintain the patched-core setup GGDD requires. Use whenever the user mentions GGDD nodes not connecting, wanting to update/refresh the GGDD subscription, Google/GitHub being unreachable through the proxy, Clash Verge GGDD profile issues, or after a Clash Verge app update broke the proxy. Covers fetching/decrypting the subscription, regenerating the Clash profile, keeping the patched mihomo core + wrapper in place, restarting, and verifying.
---

# GGDD → Clash Verge subscription sync

GGDD is an airport whose nodes only work through their **custom-patched mihomo core**.
A stock mihomo connects to the same trojan nodes but gets a degraded China-egress channel:
plain HTTP works (204 smoke tests pass!) while HTTPS to blocked sites (google/github) fails.
Everything below is already deployed on this machine.

## Architecture (memorize this before touching anything)

```
Clash Verge Rev (D:\Clash_Verge\clash-verge.exe)
  └─ spawns D:\Clash_Verge\verge-mihomo.exe      ← C# wrapper (core-wrapper.cs, ~10KB)
       ├─ rewrites "tun: stack: mips" → "stack: mixed" in generated configs
       │  (CVR hardcodes stack:mips when TUN is off; stock mihomo tolerates it,
       │   GGDD's core fatals with "invalid tun stack")
       └─ starts D:\Clash_Verge\verge-mihomo-real.exe   ← GGDD patched mihomo ("v1.0.7")
          (Job Object kill-on-close so CVR's process management still works)
```

- `verge-mihomo.exe.orig` = pristine stock core (61MB) — restore it to go back to vanilla.
- `core-wrapper.cs` = wrapper source (canonical copy in this skill at `scripts/core-wrapper.cs`,
  deployed copies live next to the cores in the Clash Verge dir); recompile with
  `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /out:verge-mihomo.exe core-wrapper.cs`
  (paths with spaces need quotes)
- Profile: `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\ggddSub2026.yaml`
  (29 trojan nodes, header comment carries the sub-token).

## Normal case: refresh the node list

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.agents\skills\ggdd-clash-sync\scripts\update-ggdd.ps1"
```

Per-machine tweaks when deploying: pass `-VergeExe` if the Clash Verge install path
differs from the default in the script's param block (e.g. `D:\Clash Verge\clash-verge.exe`
on a machine where the dir has a space).

Fetches + decrypts the subscription (tk token, no login needed), regenerates the profile,
restarts Clash Verge, verifies `HTTP 204` through 127.0.0.1:7897.

## Symptom → fix map

| Symptom | Meaning | Action |
|---|---|---|
| Google/GitHub unreachable, but 204-over-HTTP works; bing https works | Stock core is running (CVR update overwrote the wrapper) | Recompile wrapper: `ren verge-mihomo.exe stock.tmp` (if it's ~61MB stock), ensure `verge-mihomo-real.exe` exists, recompile core-wrapper.cs to verge-mihomo.exe, restart CVR. Verify GitHub=200. |
| Core won't start, sidecar log: `invalid tun stack` | Wrapper missing/not patching | Recompile wrapper from D:\Clash_Verge\core-wrapper.cs. |
| GitHub still failing WITH patched core | Nodes/servers changed | Run update-ggdd.ps1; if still bad, fetch fresh full YAML via getNXorYaml (needs JWT — see references/technical-details.md). |
| Decrypt failed in script | XOR key rotated | Re-extract key from panel frontend JS (references). |
| 404 layui HTML on sub fetch | Wrong token | Token = 32-hex `# sub-token:` in profile header; obtain new one via panel API (references). |
| 502 on sub fetch | Went through proxy | Script uses curl.exe (direct) by design; keep it that way. |

## Verify like you mean it

HTTP 204 via `http://www.gstatic.com/generate_204` passes even on the degraded
China-egress channel — it is NOT proof of a working proxy. Always verify with:

```
curl -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" https://github.com    # expect 200
curl -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" https://www.google.com # expect 200/302
```

## Read on demand

- `references/technical-details.md` — full reverse-engineering notes: encrypted panel API,
  JWT handling, getNXorYaml official flow (special headers + per-response key), official
  client analysis (Mihomo Party fork), patched-core discovery, all config gotchas.
