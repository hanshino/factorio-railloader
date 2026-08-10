<#
部署到本伺服器的摘要：
1. 本地自建 mod 不在 portal 上，UPDATE_MODS_ON_START 會跳過，必須手動複製 zip 到 _data/mods/。
2. _data/ 由 uid 845 擁有，寫入需透過 --user 845 的一次性容器。
3. zip 檔名必須與 info.json 的 name/version 一致。
4. 編輯 mod-list.json 前必須先 docker compose down，再加入 zip 與項目，最後啟動；避免 Factorio 關閉時刪除無 zip 的項目。
5. 上線前先在單機測試地圖驗證，不要直接部署到正在運行的 card-tech-draft 季。

PowerShell 原生打包腳本；預設輸出到 mod 目錄的上一層，亦可用 -OutDir 指定位置。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $OutDir
)

$ErrorActionPreference = 'Stop'

$modDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$infoPath = Join-Path $modDir 'info.json'
$info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($info.name) -or [string]::IsNullOrWhiteSpace($info.version)) {
    throw 'info.json 必須包含非空的 name 與 version。'
}

$packageName = '{0}_{1}' -f $info.name, $info.version
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $outputDir = Split-Path -Parent $modDir
} else {
    $outputDir = [System.IO.Path]::GetFullPath($OutDir)
}
$zipPath = Join-Path $outputDir ($packageName + '.zip')

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('railloader-pack-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot $packageName

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    $excluded = @('.git', 'pack.sh', 'pack.ps1', 'PORTING.md', 'spec', 'resources')
    Get-ChildItem -LiteralPath $modDir -Force | Where-Object {
        if ($_.PSIsContainer) {
            $excluded -notcontains $_.Name
        } else {
            $_.Extension -ne '.zip' -and $excluded -notcontains $_.Name
        }
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $packageRoot -Recurse -Force
    }

    Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
    Write-Output $zipPath
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
