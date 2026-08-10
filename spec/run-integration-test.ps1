<#
.SYNOPSIS
  Runs the railloader-continued headless integration tests inside a real
  Factorio container.

.DESCRIPTION
  The tests in spec/integration exercise engine behaviour that cannot be mocked,
  most importantly that surface.create_entity returns nil when a position is
  already occupied. They run during on_init of a throwaway map and abort with a
  sentinel error instead of writing a save.

  Exit code 0 means every assertion passed.

.EXAMPLE
  .\spec\run-integration-test.ps1
  .\spec\run-integration-test.ps1 -FactorioVersion 2.0.77
#>
[CmdletBinding()]
param(
    [string]$FactorioVersion = "2.0.77"
)

$ErrorActionPreference = "Stop"

$modRoot = Split-Path -Parent $PSScriptRoot
$image = "factoriotools/factorio:$FactorioVersion"

Write-Host "Running railloader-continued integration tests on $image" -ForegroundColor Cyan

$script = @'
set -e
mkdir -p /tmp/mods/railloader-continued /tmp/mods/railloader-integration-test
cp -r /mod/* /tmp/mods/railloader-continued/
rm -rf /tmp/mods/railloader-continued/spec
cp -r /mod/spec/integration/* /tmp/mods/railloader-integration-test/
/opt/factorio/bin/x64/factorio --mod-directory /tmp/mods --create /tmp/test-map.zip 2>&1 || true
'@

$output = & docker run --rm `
    -v "${modRoot}:/mod:ro" `
    --entrypoint sh $image -c $script 2>&1

$testLines = $output | Select-String -Pattern "RLTEST"
$testLines | ForEach-Object {
    $line = $_.Line
    if ($line -match "FAIL") { Write-Host $line -ForegroundColor Red }
    elseif ($line -match "PASS") { Write-Host $line -ForegroundColor Green }
    else { Write-Host $line }
}

$result = $output | Select-String -Pattern "RLTEST RESULT" | Select-Object -Last 1
if (-not $result) {
    Write-Host "`nNo test result found. Full output:" -ForegroundColor Red
    $output | ForEach-Object { Write-Host $_ }
    exit 1
}

if ($result.Line -match "fail=(\d+)") {
    $failCount = [int]$Matches[1]
    if ($failCount -gt 0) {
        Write-Host "`n$failCount test(s) FAILED" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nAll integration tests passed." -ForegroundColor Green
exit 0
