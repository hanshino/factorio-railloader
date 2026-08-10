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

    $excluded = @('.git', 'pack.sh', 'pack.ps1', 'publish.ps1', 'portal-description.md', 'PORTING.md', 'spec', 'resources')
    # Mod Portal 明確拒收可執行檔（exe/bat/ps1/sh/py），回應是 InvalidModUpload。
    # 用副檔名排除而非逐一列名，避免日後新增腳本時又被擋下。
    $excludedExtensions = @('.zip', '.exe', '.bat', '.ps1', '.sh', '.py')
    Get-ChildItem -LiteralPath $modDir -Force | Where-Object {
        if ($_.PSIsContainer) {
            $excluded -notcontains $_.Name
        } else {
            $excludedExtensions -notcontains $_.Extension.ToLowerInvariant() -and $excluded -notcontains $_.Name
        }
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $packageRoot -Recurse -Force
    }

    # 不可用 Compress-Archive：PowerShell 5.1 會把目錄分隔符寫成 Windows 反斜線，
    # Mod Portal 會以 InvalidModUpload 拒收（zip 規範要求正斜線，Linux/macOS 客戶端也讀不到）。
    # 因此手動建立 zip 條目，並明確使用正斜線。
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $prefixLength = $tempRoot.TrimEnd([char]92, [char]47).Length + 1
        Get-ChildItem -LiteralPath $packageRoot -Recurse -Force -File | ForEach-Object {
            $entryName = $_.FullName.Substring($prefixLength).Replace([char]92, [char]47)
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $archive.Dispose()
    }

    Write-Output $zipPath
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
