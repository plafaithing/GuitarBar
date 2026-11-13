# GuitarBar 一键编译+打包（2026-11-05）
# 用法：
#   powershell -File packaging\build.ps1                        # 编译 + 打包（日期名）
#   powershell -File packaging\build.ps1 -Version V1.0          # 版本名（release 发版）
#   powershell -File packaging\build.ps1 -SkipBuild -Version V1.0
# 产物：dist\GuitarBar-<日期或版本>.zip（解压即用便携包，含内置卸载器）
param([switch]$SkipBuild, [string]$Version = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rel = Join-Path $root 'build\windows\x64\runner\Release'
$packaging = Join-Path $root 'packaging'
$dist = Join-Path $root 'dist'
$stamp = if ($Version) { $Version } else { Get-Date -Format 'yyyyMMdd' }
$zip = Join-Path $dist "GuitarBar-$stamp.zip"

# 1) 编译（-SkipBuild 跳过：只重打包）
if (-not $SkipBuild) {
    Write-Host '[1/4] flutter build windows --release ...' -ForegroundColor Cyan
    Push-Location $root
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'build failed' }
    Pop-Location
} else {
    Write-Host '[1/4] skip build (-SkipBuild)' -ForegroundColor Yellow
}

# 2) 组装 staging：复制 Release，剔除开发数据（用户首次运行自动建库）
Write-Host '[2/4] staging (exclude dev data) ...' -ForegroundColor Cyan
$stageRoot = Join-Path $packaging 'stage'
$stage = Join-Path $stageRoot 'GuitarBar'
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $rel '*') $stage -Recurse -Exclude 'guitarbar.sqlite', 'close-log.txt'
Remove-Item (Join-Path $stage 'data\scores') -Recurse -Force -ErrorAction SilentlyContinue

# 3) 加卸载器与使用说明
Write-Host '[3/4] add uninstaller + docs ...' -ForegroundColor Cyan
Copy-Item (Join-Path $packaging '卸载GuitarBar.bat') $stage -Force
Copy-Item (Join-Path $packaging 'uninstall.ps1') $stage -Force
Copy-Item (Join-Path $packaging '使用说明.txt') $stage -Force

# 4) 压缩
Write-Host '[4/4] compress ...' -ForegroundColor Cyan
New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

# 验证：无开发数据混入、卸载器在
Add-Type -AssemblyName System.IO.Compression.FileSystem
$a = [System.IO.Compression.ZipFile]::OpenRead($zip)
$leak = $a.Entries | Where-Object { $_.FullName -match 'guitarbar\.sqlite|close-log' }
$uninst = $a.Entries | Where-Object { $_.FullName -match 'uninstall\.ps1|卸载GuitarBar\.bat' }
$a.Dispose()
if ($leak) { throw "dev data leaked into zip: $($leak.FullName)" }
if (-not $uninst) { throw 'uninstaller missing in zip' }

$z = Get-Item $zip
Write-Host ''
Write-Host ("DONE  {0}  ({1} MB)" -f $zip, [math]::Round($z.Length / 1MB, 1)) -ForegroundColor Green
