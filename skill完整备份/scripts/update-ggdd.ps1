# update-ggdd.ps1 - GGDD subscription refresh into Clash Verge Rev
# Flow: fetch encrypted sub -> Base64+XOR decrypt -> parse trojan:// -> regen YAML -> restart Clash Verge -> verify
# This file is intentionally ASCII-only: emoji/Chinese group names are built at runtime via code points,
# so the script survives any file encoding (PS 5.1 reads non-BOM files as ANSI).
param(
  [string]$Token,
  [string]$SubUrl = "http://47.76.147.109/api/v1/client/getXorSub",
  [string]$Key = "SIzLm51puIlCewdfDWCgWXQ_Kq-ST242UBEVBhKReO7guLPFH0=",
  [string]$ProfilePath = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev\profiles\ggddSub2026.yaml",
  [string]$VergeExe = "D:\Clash_Verge\clash-verge.exe",
  [switch]$NoRestart
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# --- 0a. locate the Clash Verge exe if the default path misses (per-machine install dirs) ---
if (-not (Test-Path $VergeExe)) {
  foreach ($cand in @("D:\Clash Verge\clash-verge.exe", "$env:LOCALAPPDATA\Programs\Clash Verge\clash-verge.exe")) {
    if (Test-Path $cand) { $VergeExe = $cand; break }
  }
}

# --- 0. patched-core sanity check (GGDD nodes REQUIRE their custom core) ---
$vergeDir = Split-Path $VergeExe -Parent
if (-not (Test-Path (Join-Path $vergeDir "verge-mihomo-real.exe"))) {
  Write-Output "[0] WARNING: verge-mihomo-real.exe (GGDD patched core) missing in $vergeDir - proxy will only reach China egress!"
}
if (-not (Test-Path (Join-Path $vergeDir "core-wrapper.cs"))) {
  Write-Output "[0] WARNING: core-wrapper.cs missing - cannot repair wrapper if a CVR update overwrites it."
}

# --- 1. token: param > existing profile ('# sub-token:' comment header) ---
# NOTE: the subscription token (tk= param, 32 hex chars) is DIFFERENT from the trojan password (account uuid).
# Do NOT recover it from 'password:' fields - that yields the uuid and the server answers 404 no-permission.
if (-not $Token -and (Test-Path $ProfilePath)) {
  $m = Select-String -Path $ProfilePath -Pattern '# sub-token: ([0-9a-f]{32})' | Select-Object -First 1
  if ($m) { $Token = $m.Matches[0].Groups[1].Value; Write-Output "[1] token recovered from existing profile header" }
}
if (-not $Token) { throw "No token found. Pass -Token <32-hex ggdd sub token> (obtainable via the panel's encrypted /user/getXorSubscribe API - see references/technical-details.md)." }
Write-Output "[1] token: $($Token.Substring(0,8))..."

# --- 2. fetch encrypted subscription ---
# Use curl.exe, NOT Invoke-WebRequest: IWR honors the system proxy (which this very proxy setup enables),
# and the GGDD sub server rejects requests arriving from proxy exits (502). curl.exe goes direct by default.
# A clash-like User-Agent is REQUIRED: without it the server returns a 404 HTML admin error page.
$enc = (& curl.exe -s -m 30 -A "clash-verge/v2.5.8" "$SubUrl`?tk=$Token").Trim()
if (-not $enc -or $enc.Length -lt 100) { throw "Fetch failed or empty response: '$enc'" }
Write-Output "[2] fetched $($enc.Length) chars encrypted payload"

# --- 3. decrypt (Base64 then repeating-key XOR) ---
$bytes = [Convert]::FromBase64String($enc)
$kb = [Text.Encoding]::UTF8.GetBytes($Key)
$dec = New-Object byte[] $bytes.Length
for ($i = 0; $i -lt $bytes.Length; $i++) { $dec[$i] = $bytes[$i] -bxor $kb[$i % $kb.Length] }
$text = [Text.Encoding]::UTF8.GetString($dec)
if ($text -notmatch '(?m)^trojan://') {
  throw "Decrypt failed - key may have rotated. Re-extract from http://8.148.178.30/assets/index-*.js (search 'function G('). Head: $($text.Substring(0,[Math]::Min(60,$text.Length)))"
}
Write-Output "[3] decrypted OK"

# --- 4. parse trojan URIs ---
$proxies = @()
foreach ($line in ($text -split '\r?\n')) {
  if ($line -match '^trojan://([^@]+)@([^:]+):(\d+)\?([^#]*)#(.*)\s*$') {
    $pwd = $Matches[1]; $srv = $Matches[2]; $port = $Matches[3]; $query = $Matches[4]; $nameEnc = $Matches[5]
    $sni = $null
    if ($query -match 'sni=([^&]+)') { $sni = $Matches[1] }
    $name = [Uri]::UnescapeDataString($nameEnc)
    $proxies += [pscustomobject]@{ Name = $name; Server = $srv; Port = [int]$port; Password = $pwd; Sni = $sni }
  }
}
if ($proxies.Count -eq 0) { throw "No trojan nodes parsed" }
Write-Output "[4] parsed $($proxies.Count) nodes"

# --- 5. build YAML ---
# Group names contain emoji/Chinese (runtime-built, ASCII-safe here).
# CRITICAL: the MATCH rule target must NOT be quoted; quoting makes mihomo treat quotes as part of the group name -> "proxy not found".
$SEL = [char]::ConvertFromUtf32(0x1F680) + " " + [char]::ConvertFromUtf32(0x8282) + [char]::ConvertFromUtf32(0x70B9) + [char]::ConvertFromUtf32(0x9009) + [char]::ConvertFromUtf32(0x62E9)
$AUTO = [char]::ConvertFromUtf32(0x267B) + [char]::ConvertFromUtf32(0xFE0F) + " " + [char]::ConvertFromUtf32(0x81EA) + [char]::ConvertFromUtf32(0x52A8) + [char]::ConvertFromUtf32(0x9009) + [char]::ConvertFromUtf32(0x62E9)

$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("# GGDD subscription - refreshed $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$sb.AppendLine("# sub-token: $Token")
[void]$sb.AppendLine("# $($proxies.Count) trojan nodes")
[void]$sb.AppendLine("mixed-port: 7897")
[void]$sb.AppendLine("allow-lan: false")
[void]$sb.AppendLine("mode: rule")
[void]$sb.AppendLine("log-level: info")
[void]$sb.AppendLine("unified-delay: true")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("dns:")
[void]$sb.AppendLine("  enable: true")
[void]$sb.AppendLine("  listen: 127.0.0.1:1053")
[void]$sb.AppendLine("  enhanced-mode: fake-ip")
[void]$sb.AppendLine("  fake-ip-range: 198.18.0.1/16")
[void]$sb.AppendLine("  default-nameserver:")
[void]$sb.AppendLine("    - 223.5.5.5")
[void]$sb.AppendLine("    - 119.29.29.29")
[void]$sb.AppendLine("  nameserver:")
[void]$sb.AppendLine("    - 223.5.5.5")
[void]$sb.AppendLine("    - 119.29.29.29")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("proxies:")
foreach ($p in $proxies) {
  [void]$sb.AppendLine('  - name: "' + $p.Name + '"')
  [void]$sb.AppendLine("    type: trojan")
  [void]$sb.AppendLine("    server: $($p.Server)")
  [void]$sb.AppendLine("    port: $($p.Port)")
  [void]$sb.AppendLine("    password: $($p.Password)")
  if ($p.Sni) { [void]$sb.AppendLine("    sni: $($p.Sni)") }
  [void]$sb.AppendLine("    udp: true")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("proxy-groups:")
[void]$sb.AppendLine('  - name: "' + $SEL + '"')
[void]$sb.AppendLine("    type: select")
[void]$sb.AppendLine("    proxies:")
[void]$sb.AppendLine('      - "' + $AUTO + '"')
foreach ($p in $proxies) { [void]$sb.AppendLine('      - "' + $p.Name + '"') }
[void]$sb.AppendLine('  - name: "' + $AUTO + '"')
[void]$sb.AppendLine("    type: url-test")
[void]$sb.AppendLine("    url: http://www.gstatic.com/generate_204")
[void]$sb.AppendLine("    interval: 300")
[void]$sb.AppendLine("    tolerance: 50")
[void]$sb.AppendLine("    proxies:")
foreach ($p in $proxies) { [void]$sb.AppendLine('      - "' + $p.Name + '"') }
[void]$sb.AppendLine("")
[void]$sb.AppendLine("rules:")
[void]$sb.AppendLine("  - IP-CIDR,47.76.147.109/32,DIRECT,no-resolve")
[void]$sb.AppendLine("  - IP-CIDR,8.148.178.30/32,DIRECT,no-resolve")
[void]$sb.AppendLine("  - GEOIP,LAN,DIRECT,no-resolve")
[void]$sb.AppendLine("  - GEOSITE,CN,DIRECT")
[void]$sb.AppendLine("  - GEOIP,CN,DIRECT")
[void]$sb.AppendLine("  - MATCH,$SEL")

$yaml = $sb.ToString()
if (Test-Path $ProfilePath) { Copy-Item $ProfilePath "$ProfilePath.bak" -Force }
[IO.File]::WriteAllText($ProfilePath, $yaml, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "[5] profile written: $ProfilePath ($($yaml.Length) chars, backup kept at .bak)"

if ($NoRestart) { Write-Output "[6] -NoRestart given, done."; return }

# --- 6. restart Clash Verge ---
Stop-Process -Name clash-verge, verge-mihomo -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
if (-not (Test-Path $VergeExe)) { throw "Clash Verge exe not found at $VergeExe - pass -VergeExe" }
Start-Process $VergeExe
Start-Sleep -Seconds 10
$listen = (netstat -ano | Select-String ':7897 .*LISTENING')
if (-not $listen) { throw "Port 7897 not listening after restart - check %APPDATA%\io.github.clash-verge-rev.clash-verge-rev\logs\sidecar\sidecar_latest.log" }
Write-Output "[6] Clash Verge restarted, 7897 listening"

# --- 7. verify through proxy ---
$code = & curl.exe -s -m 25 -x http://127.0.0.1:7897 -o NUL -w "%{http_code}" "http://www.gstatic.com/generate_204"
if ($code -eq "204") { Write-Output "[7] VERIFY OK - proxy works (HTTP 204 via node)" }
else { Write-Output "[7] VERIFY FAILED - proxy returned HTTP $code. Check node status in Clash Verge UI." }
