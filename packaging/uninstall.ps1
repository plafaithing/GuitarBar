Write-Host "================================================" -ForegroundColor Cyan
Write-Host "             GuitarBar 卸载程序" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " [警告] 卸载将删除本目录（含全部曲谱、打卡数据）。"
Write-Host " 如需保留数据，请先手动备份："
Write-Host "    data\guitarbar.sqlite   （打卡/曲谱数据库）"
Write-Host "    data\scores\            （曲谱源文件与页图）"
Write-Host ""
Write-Host " [提示] 请先关闭正在运行的 GuitarBar。"
Write-Host ""
$confirm = Read-Host "确认卸载？(Y/N)"
if ($confirm -notin @('Y', 'y')) {
    Write-Host "已取消卸载。"
    exit 0
}
$running = Get-Process guitarbar -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "[错误] GuitarBar 正在运行，请先关闭后重试。" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}
Write-Host "正在卸载..."
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $env:TEMP
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "卸载完成。"
Start-Sleep -Seconds 2
