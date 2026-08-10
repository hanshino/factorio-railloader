<#
.SYNOPSIS
    Publish railloader-continued to the Factorio Mod Portal.

The default is deliberately a dry run.  Add -Yes only after checking the
printed values; publishing a new mod name cannot be undone or renamed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Init', 'Release', 'Details')]
    [string] $Mode,

    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
$modDir = [IO.Path]::GetFullPath($PSScriptRoot)
$infoPath = Join-Path $modDir 'info.json'
$info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($property in @('name', 'version', 'title')) {
    if ([string]::IsNullOrWhiteSpace([string]$info.$property)) {
        throw "info.json 必須包含非空的 $property。"
    }
}

$name = [string]$info.name
$version = [string]$info.version
$title = [string]$info.title
$packageName = '{0}_{1}' -f $name, $version
$zipPath = Join-Path (Split-Path -Parent $modDir) ($packageName + '.zip')
$descriptionPath = Join-Path $modDir 'portal-description.md'

# These are Mod Portal category/license identifiers, not info.json fields.
# Category must be one of the Portal's fixed values: content / overhaul / tweaks /
# utilities / scenarios / mod-packs / localizations / internal.
# "logistics" is a *tag*, not a category -- sending it here fails validation.
# Tags can only be set through -Mode Details (edit_details), not at publish time.
$category = 'content'
$license = 'default_gnulgplv3'
$sourceUrl = 'https://github.com/hanshino/factorio-railloader'
$summary = 'A Factorio 2.0 continuation of Bulk Rail Loaders for fast bulk cargo wagon loading and unloading.'

function Test-ZipLayout([string]$path, [string]$expectedRoot) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Zip not found: $path. Run .\pack.ps1 first."
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $roots = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($entry in $archive.Entries) {
            $parts = $entry.FullName.Replace('\', '/').Split('/')
            if ($parts.Count -eq 0 -or [string]::IsNullOrWhiteSpace($parts[0])) {
                throw 'Zip contains an entry without a top-level directory.'
            }
            [void]$roots.Add($parts[0])
        }
        if ($roots.Count -ne 1 -or -not $roots.Contains($expectedRoot)) {
            throw "Zip must have exactly one top-level directory named '$expectedRoot'; found: $([string]::Join(', ', @($roots)))"
        }
        Write-Output "Zip layout verified (唯一 top-level directory = $expectedRoot)"
    } finally {
        $archive.Dispose()
    }
}

function Get-ApiKey {
    $key = [Environment]::GetEnvironmentVariable('FACTORIO_MOD_API_KEY', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($key)) { return $key.Trim() }

    $envPath = Join-Path (Split-Path -Parent $modDir) '.env'
    if (Test-Path -LiteralPath $envPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
            if ($line -match '^\s*FACTORIO_MOD_API_KEY\s*=\s*(.*)\s*$') {
                $value = $Matches[1].Trim()
                if ($value.Length -ge 2 -and (($value[0] -eq [char]34 -and $value[$value.Length - 1] -eq [char]34) -or ($value[0] -eq [char]39 -and $value[$value.Length - 1] -eq [char]39))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        }
    }
    return $null
}

function Invoke-Multipart([string]$url, [hashtable]$fields, [string]$filePath, [string]$apiKey) {
    # PowerShell 5.1 does not load System.Net.Http by default; without this the
    # HttpClient type cannot be resolved.
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object Net.Http.HttpClient
    $content = New-Object Net.Http.MultipartFormDataContent
    try {
        $client.DefaultRequestHeaders.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer', $apiKey)
        foreach ($key in $fields.Keys) {
            [void]$content.Add((New-Object Net.Http.StringContent([string]$fields[$key])), $key)
        }
        if ($filePath) {
            $stream = [IO.File]::OpenRead($filePath)
            $fileContent = New-Object Net.Http.StreamContent($stream)
            [void]$content.Add($fileContent, 'file', [IO.Path]::GetFileName($filePath))
        }
        $response = $client.PostAsync($url, $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return @{ Status = [int]$response.StatusCode; Body = $body }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($content) { $content.Dispose() }
        $client.Dispose()
    }
}

Write-Output "Name: $name    Title: $title    Version: $version"
Write-Output "Zip: $zipPath"
Write-Output "Category: $category    License: $license    Mode: $Mode"
if ($Mode -ne 'Details') { Test-ZipLayout $zipPath $packageName }

if (-not $Yes) {
    Write-Output '-- dry-run: no requests sent; add -Yes to call the Portal API. --'
    exit 0
}

$apiKey = Get-ApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'FACTORIO_MOD_API_KEY was not found in the process environment or project-root .env.'
}
$api = 'https://mods.factorio.com/api/v2/mods'

try {
    if ($Mode -eq 'Details') {
        $fields = @{ mod = $name; title = $title; summary = $summary; category = $category; license = $license; source_url = $sourceUrl }
        if (Test-Path -LiteralPath $descriptionPath) { $fields.description = Get-Content -LiteralPath $descriptionPath -Raw -Encoding UTF8 }
        $result = Invoke-Multipart "$api/edit_details" $fields $null $apiKey
        $json = $result.Body | ConvertFrom-Json
        if (-not $json.success) { throw "Portal 回應 HTTP $($result.Status)：$($result.Body)" }
    } else {
        $initUrl = if ($Mode -eq 'Init') { "$api/init_publish" } else { "$api/releases/init_upload" }
        $result = Invoke-Multipart $initUrl @{ mod = $name } $null $apiKey
        $initJson = $result.Body | ConvertFrom-Json
        if (-not $initJson.upload_url) { throw "Portal 回應 HTTP $($result.Status)：$($result.Body)" }
        $fields = @{}
        if ($Mode -eq 'Init') {
            $fields.category = $category; $fields.license = $license; $fields.source_url = $sourceUrl
            if (Test-Path -LiteralPath $descriptionPath) { $fields.description = Get-Content -LiteralPath $descriptionPath -Raw -Encoding UTF8 }
        }
        $result = Invoke-Multipart ([string]$initJson.upload_url) $fields $zipPath $apiKey
        $uploadJson = $result.Body | ConvertFrom-Json
        if (-not $uploadJson.success) { throw "Portal 回應 HTTP $($result.Status)：$($result.Body)" }
    }
    Write-Output "完成：https://mods.factorio.com/mod/$name"
} catch {
    $message = $_.Exception.Message.Replace($apiKey, '[REDACTED]')
    throw "Publish failed (API key redacted): $message"
}
