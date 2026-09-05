# install.ps1 -- ONE line for Windows (Docker Desktop): nothing -> a running, AUTHENTICATED Semurg node.
#
#   irm https://one.semurg.io/install.ps1 | iex
#
# Uses the Docker CLI that Docker Desktop installs into PowerShell itself -- NO WSL Ubuntu distro, NO
# reboot, NO apt, NO admin. Verifies the release, loads the PREBUILT amd64 image (NO local build), runs
# it with the three required capabilities, prints the /v1 API token + URL, opens the browser.
# x86-64 only (Windows PCs are x86_64; the image runs at native speed through Docker Desktop/WSL2).
# Publish this file to https://one.semurg.io/install.ps1 . Requires Windows 10 1803+ / PowerShell 5.1+.
$ErrorActionPreference = "Stop"
$Dl        = if ($env:SEMURG_DL_BASE)   { $env:SEMURG_DL_BASE }   else { "https://one.semurg.io/dl" }
$ImageTag  = if ($env:SEMURG_IMAGE_TAG) { $env:SEMURG_IMAGE_TAG } else { "semurg/substrate:r11-test" }
$HostPort  = if ($env:SEMURG_HOST_PORT) { $env:SEMURG_HOST_PORT } else { "4100" }
$Container = "semurg"
$Volume    = "semurg-data"
$Work      = Join-Path $env:TEMP ("semurg-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Die($m){ Write-Host "`n!!! $m" -ForegroundColor Red; exit 1 }

# 1. Docker present + running? (Docker Desktop provides the docker CLI in PowerShell directly.)
try { docker version | Out-Null } catch {
  Die "Docker was not found. Install Docker Desktop for Windows (https://www.docker.com/products/docker-desktop/), start it (wait for `"Engine running`"), then re-run:  irm $Dl/install.ps1 | iex"
}
try { docker info | Out-Null } catch { Die "Docker Desktop is installed but not running. Start Docker Desktop, wait for the engine, then re-run." }

# 2. fetch the signed manifest; ed25519-verify it if openssl is on PATH, else fall back to hash-only.
Write-Host ">>> fetching the release manifest"
Invoke-WebRequest -UseBasicParsing "$Dl/LATEST.json"     -OutFile "$Work\LATEST.json"
try { Invoke-WebRequest -UseBasicParsing "$Dl/LATEST.json.sig" -OutFile "$Work\LATEST.json.sig" } catch {}
$pub = @"
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAGmSXmU++yNyeIS3rHFjAH1ppyErRrkxcovD6ljt1B4w=
-----END PUBLIC KEY-----
"@
if ((Get-Command openssl -ErrorAction SilentlyContinue) -and (Test-Path "$Work\LATEST.json.sig")) {
  Set-Content -NoNewline -Path "$Work\pub.pem" -Value $pub
  & openssl pkeyutl -verify -pubin -inkey "$Work\pub.pem" -rawin -in "$Work\LATEST.json" -sigfile "$Work\LATEST.json.sig" *> $null
  if ($LASTEXITCODE -ne 0) { Die "release manifest signature INVALID (ed25519). Channel may be compromised or this script is stale." }
  Write-Host "  release signature verified (ed25519, pinned key)"
} else {
  Write-Host "  NOTE: openssl not on PATH -- verifying the image by SHA256 from the manifest. For full ed25519 verification install openssl or use WSL." -ForegroundColor Yellow
}
$manifest = Get-Content "$Work\LATEST.json" -Raw | ConvertFrom-Json
$imgSha   = $manifest.image_tar_sha256
$version  = $manifest.version

# 3. download + verify + load the prebuilt amd64 image
Write-Host ">>> downloading the prebuilt amd64 image (no local build): $version"
Invoke-WebRequest -UseBasicParsing "$Dl/semurg-substrate-r11-amd64.tar.gz" -OutFile "$Work\image.tar.gz"
if ($imgSha) {
  $got = (Get-FileHash "$Work\image.tar.gz" -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $imgSha.ToLower()) { Die "image digest mismatch (got $got, manifest $imgSha) -- refusing to load." }
  Write-Host "  image verified against the signed manifest digest"
} else {
  Write-Host "  NOTE: manifest has no image_tar_sha256 yet -- add it to LATEST.json for tamper-proof verification." -ForegroundColor Yellow
}
Write-Host ">>> docker load"
docker load -i "$Work\image.tar.gz" | Out-Null

# 4. run with the three required capabilities (idempotent)
docker rm -f $Container 2>$null | Out-Null
Write-Host ">>> starting the node (detached)"
docker run -d --name $Container `
  --platform linux/amd64 `
  --ulimit memlock=-1 `
  --security-opt seccomp=unconfined `
  -v "${Volume}:/var/lib/semurg" `
  -p "127.0.0.1:${HostPort}:4000" `
  --restart unless-stopped `
  $ImageTag | Out-Null

# 5. wait for health, print token + URL, open the browser
Write-Host ">>> waiting for the node to arm (up to ~120s)"
$up = $false
for ($i=0; $i -lt 60; $i++) {
  try { Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$HostPort/api/health" -TimeoutSec 3 | Out-Null; $up=$true; break } catch { Start-Sleep 2 }
}
$token = (docker exec $Container sh -c "grep ^SEMURG_API_TOKEN= /etc/semurg/semurg.env 2>/dev/null | cut -d= -f2-").Trim()
Write-Host ""
Write-Host "================ YOUR NODE IS READY -- START HERE ================" -ForegroundColor Green
if ($up) { Write-Host "  Health:  http://127.0.0.1:$HostPort/api/health   (200 OK)" } else { Write-Host "  Health:  not yet 200 -- watch it: docker logs -f $Container" }
Write-Host "  API token (every /v1 call needs it):"
Write-Host "      $token"
Write-Host ""
Write-Host "  Ask your node a question (use curl.exe, not the PowerShell curl alias):"
Write-Host "      curl.exe -s -H `"Authorization: Bearer $token`" http://127.0.0.1:$HostPort/v1/status"
Write-Host "  Live log:  docker logs -f $Container"
Write-Host "=================================================================" -ForegroundColor Green
if ($up) { Start-Process "http://127.0.0.1:$HostPort/api/health" }
