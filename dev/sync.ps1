# Push the repo to the router. No scp/sftp on the target, so base64 over ssh.
param(
    [string]$Router = "192.168.1.1",
    [string]$Dest   = "/root/openwrt-tls-frag"
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$files = git ls-files | Where-Object { $_ -notmatch '^(reference/)' }

ssh "root@$Router" "rm -rf '$Dest'; mkdir -p '$Dest'"

foreach ($f in $files) {
    $text  = [IO.File]::ReadAllText($f) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $b64   = [Convert]::ToBase64String($bytes)
    $dir   = [IO.Path]::GetDirectoryName($f) -replace '\\', '/'
    $rp    = $f -replace '\\', '/'
    if ($dir) { ssh "root@$Router" "mkdir -p '$Dest/$dir'" }
    ssh "root@$Router" "echo '$b64' | base64 -d > '$Dest/$rp'"
    Write-Host "  -> $rp"
}

ssh "root@$Router" "chmod +x '$Dest'/*.sh '$Dest'/tests/*.sh '$Dest'/tests/unit/*.sh 2>/dev/null; echo SYNCED"
