<#
.SYNOPSIS
  在 Miao-Yunzai 里一键安装 / 更新 / 卸载 shotium 渲染后端。

.DESCRIPTION
  在 Yunzai 根目录运行：
    .\renderers\shotium\install.ps1              # 安装或更新，并把 renderer.yaml 切到 shotium
    .\renderers\shotium\install.ps1 -Mode daemon # 同时生成 config.yaml 并把引擎切到守护进程模式
    .\renderers\shotium\install.ps1 -Uninstall   # 切回 puppeteer 并删除 renderers/shotium

  还没克隆时可以直接远程执行（在 Yunzai 根目录）：
    irm https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.ps1 | iex
  远程执行并传参：
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.ps1))) -Mode daemon

.PARAMETER Root
  Yunzai 根目录。默认取当前目录；在 renderers/shotium 里运行时自动取上两级。

.PARAMETER Mode
  引擎运行方式：inprocess（进程内，默认）或 daemon（常驻守护进程）。不传时不生成 config.yaml。

.PARAMETER Uninstall
  卸载：renderer.yaml 的 name 清空（回到 puppeteer），删除 renderers/shotium。
#>
param(
  [string]$Root,
  [string]$Mode,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
# PowerShell 7.4+ 默认让原生命令的非零退出码跟着 $ErrorActionPreference 抛异常，
# 那样 pnpm / git 一失败就直接中断，下面的 $LASTEXITCODE 判断和回退分支都走不到。
$PSNativeCommandUseErrorActionPreference = $false
if ($Mode -and $Mode -notin @('inprocess', 'daemon')) {
  Write-Host "[shotium] -Mode 只能是 inprocess 或 daemon" -ForegroundColor Red
  exit 1
}
$Repo = if ($env:SHOTIUM_RENDERER_REPO) { $env:SHOTIUM_RENDERER_REPO } else { 'https://github.com/sj817/yunzai-renderer-shotium' }

function Info($msg) { Write-Host "[shotium] $msg" }
function Fail($msg) { Write-Host "[shotium] $msg" -ForegroundColor Red; exit 1 }

# ---- 定位 Yunzai 根目录 -------------------------------------------------------
if (-not $Root) {
  $cwd = (Get-Location).Path
  if ((Split-Path $cwd -Leaf) -eq 'shotium' -and (Split-Path (Split-Path $cwd -Parent) -Leaf) -eq 'renderers') {
    $Root = Split-Path (Split-Path $cwd -Parent) -Parent
  } else {
    $Root = $cwd
  }
}
$Root = (Resolve-Path $Root).Path
if (-not (Test-Path (Join-Path $Root 'package.json')) -or -not (Test-Path (Join-Path $Root 'lib\renderer\Renderer.js'))) {
  Fail "$Root 不是 Miao-Yunzai 根目录（缺少 package.json 或 lib/renderer/Renderer.js），请在 Yunzai 根目录运行，或用 -Root 指定"
}
Info "Yunzai 根目录: $Root"

$Dir = Join-Path $Root 'renderers\shotium'
$ConfigDir = Join-Path $Root 'config\config'
$RendererYaml = Join-Path $ConfigDir 'renderer.yaml'

# ---- 写 renderer.yaml 的 name -------------------------------------------------
function Set-RendererName([string]$name) {
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  $line = if ($name) { "name: $name" } else { 'name:' }
  if (Test-Path $RendererYaml) {
    $content = Get-Content $RendererYaml -Raw
    if ($content -match '(?m)^name:.*$') {
      $content = [regex]::Replace($content, '(?m)^name:.*$', $line, 1)
    } else {
      $content = $content.TrimEnd() + "`n$line`n"
    }
  } else {
    $content = "# 渲染后端, 默认为 puppeteer`n$line`n"
  }
  [IO.File]::WriteAllText($RendererYaml, $content, (New-Object Text.UTF8Encoding $false))
  Info "config/config/renderer.yaml -> $line"
}

# ---- 卸载 --------------------------------------------------------------------
if ($Uninstall) {
  Set-RendererName ''
  if (Test-Path $Dir) {
    Remove-Item -Recurse -Force $Dir
    Info "已删除 renderers/shotium"
  }
  Info "卸载完成，重启 Yunzai 后回到 puppeteer"
  exit 0
}

# ---- 克隆或更新 --------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail '未找到 git' }
if (Test-Path (Join-Path $Dir '.git')) {
  Info '更新 renderers/shotium ...'
  git -C $Dir pull --ff-only
  if ($LASTEXITCODE -ne 0) { Fail 'git pull 失败' }
} elseif (Test-Path $Dir) {
  Fail "$Dir 已存在但不是 git 仓库，请先手动处理"
} else {
  Info "克隆 $Repo -> renderers/shotium ..."
  git clone --depth 1 $Repo $Dir
  if ($LASTEXITCODE -ne 0) { Fail 'git clone 失败' }
}

# ---- 安装依赖 ----------------------------------------------------------------
# 与 install.sh 一致：装没装上只看 @pixel.js/shotium 的实际路径，不看包管理器的退出码。
# renderers/shotium 一般不在 Yunzai 的 pnpm workspace 里，根目录 pnpm install
# 打印 "Already up to date" 并返回 0，也完全可能压根没碰渲染器的依赖。
function Test-ShotiumDep {
  (Test-Path (Join-Path $Dir 'node_modules\@pixel.js\shotium')) -or
  (Test-Path (Join-Path $Root 'node_modules\@pixel.js\shotium'))
}

if (Get-Command pnpm -ErrorAction SilentlyContinue) {
  Info '根目录 pnpm install ...'
  Push-Location $Root
  try { pnpm install } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { Info '根目录 pnpm install 没跑成功（通常是别的依赖拉不下来），继续往下走' }
  if (Test-ShotiumDep) {
    Info '@pixel.js/shotium 已就位，跳过单独安装'
  } else {
    Info '根目录安装没有装上 @pixel.js/shotium，改为只安装渲染器自身的依赖 ...'
    Push-Location $Dir
    try { pnpm install --ignore-workspace } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Info 'pnpm install --ignore-workspace 没跑成功' }
  }
} elseif (Get-Command npm -ErrorAction SilentlyContinue) {
  Info '未找到 pnpm，在 renderers/shotium 里用 npm install ...'
  Push-Location $Dir
  try { npm install --no-package-lock } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { Info 'npm install 没跑成功' }
} else {
  Fail '未找到 pnpm 或 npm'
}

if (-not (Test-ShotiumDep)) {
  Fail '@pixel.js/shotium 没有装上，请检查上面的安装日志（deprecated、peer dependency 之类的告警可以忽略，要找的是网络或权限错误）'
}

# ---- 写配置 ------------------------------------------------------------------
Set-RendererName 'shotium'

if ($Mode) {
  $cfg = Join-Path $Dir 'config.yaml'
  if (-not (Test-Path $cfg)) { Copy-Item (Join-Path $Dir 'config_default.yaml') $cfg }
  $content = Get-Content $cfg -Raw
  $content = [regex]::Replace($content, '(?m)^mode:.*$', "mode: $Mode", 1)
  [IO.File]::WriteAllText($cfg, $content, (New-Object Text.UTF8Encoding $false))
  Info "renderers/shotium/config.yaml -> mode: $Mode"
}

Info '完成。重启 Yunzai，日志出现「加载渲染后端 shotium」即生效'
