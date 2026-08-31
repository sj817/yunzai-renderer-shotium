#!/usr/bin/env bash
# 在 Miao-Yunzai 里一键安装 / 更新 / 卸载 shotium 渲染后端。
#
# 在 Yunzai 根目录运行：
#   bash renderers/shotium/install.sh                # 安装或更新，并把 renderer.yaml 切到 shotium
#   bash renderers/shotium/install.sh --mode daemon  # 同时生成 config.yaml 并把引擎切到守护进程模式
#   bash renderers/shotium/install.sh --uninstall    # 切回 puppeteer 并删除 renderers/shotium
#
# 还没克隆时可以直接远程执行（在 Yunzai 根目录）：
#   curl -fsSL https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.sh | bash -s -- --mode daemon
#
# 参数：
#   --root <dir>   Yunzai 根目录，默认当前目录；在 renderers/shotium 里运行时自动取上两级
#   --mode <m>     inprocess（进程内，默认）或 daemon（常驻守护进程）；不传时不生成 config.yaml
#   --uninstall    卸载

set -eu

REPO="${SHOTIUM_RENDERER_REPO:-https://github.com/sj817/yunzai-renderer-shotium}"
ROOT=""
MODE=""
UNINSTALL=0

info() { printf '[shotium] %s\n' "$*"; }
fail() { printf '[shotium] %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) fail "未知参数: $1" ;;
  esac
done

case "$MODE" in
  ""|inprocess|daemon) ;;
  *) fail "--mode 只能是 inprocess 或 daemon" ;;
esac

# ---- 定位 Yunzai 根目录 -------------------------------------------------------
if [ -z "$ROOT" ]; then
  cwd="$(pwd)"
  if [ "$(basename "$cwd")" = "shotium" ] && [ "$(basename "$(dirname "$cwd")")" = "renderers" ]; then
    ROOT="$(dirname "$(dirname "$cwd")")"
  else
    ROOT="$cwd"
  fi
fi
ROOT="$(cd "$ROOT" && pwd)"
if [ ! -f "$ROOT/package.json" ] || [ ! -f "$ROOT/lib/renderer/Renderer.js" ]; then
  fail "$ROOT 不是 Miao-Yunzai 根目录（缺少 package.json 或 lib/renderer/Renderer.js），请在 Yunzai 根目录运行，或用 --root 指定"
fi
info "Yunzai 根目录: $ROOT"

DIR="$ROOT/renderers/shotium"
CONFIG_DIR="$ROOT/config/config"
RENDERER_YAML="$CONFIG_DIR/renderer.yaml"

# ---- 写 renderer.yaml 的 name -------------------------------------------------
set_renderer_name() {
  name="$1"
  if [ -n "$name" ]; then line="name: $name"; else line="name:"; fi
  mkdir -p "$CONFIG_DIR"
  if [ -f "$RENDERER_YAML" ]; then
    if grep -q '^name:' "$RENDERER_YAML"; then
      awk -v line="$line" 'BEGIN{done=0} /^name:/ && !done {print line; done=1; next} {print}' "$RENDERER_YAML" > "$RENDERER_YAML.tmp"
    else
      { cat "$RENDERER_YAML"; printf '\n%s\n' "$line"; } > "$RENDERER_YAML.tmp"
    fi
    mv "$RENDERER_YAML.tmp" "$RENDERER_YAML"
  else
    printf '# 渲染后端, 默认为 puppeteer\n%s\n' "$line" > "$RENDERER_YAML"
  fi
  info "config/config/renderer.yaml -> $line"
}

# ---- 卸载 --------------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  set_renderer_name ""
  if [ -d "$DIR" ]; then
    rm -rf "$DIR"
    info "已删除 renderers/shotium"
  fi
  info "卸载完成，重启 Yunzai 后回到 puppeteer"
  exit 0
fi

# ---- 克隆或更新 --------------------------------------------------------------
command -v git >/dev/null 2>&1 || fail "未找到 git"
if [ -d "$DIR/.git" ]; then
  info "更新 renderers/shotium ..."
  git -C "$DIR" pull --ff-only || fail "git pull 失败"
elif [ -e "$DIR" ]; then
  fail "$DIR 已存在但不是 git 仓库，请先手动处理"
else
  info "克隆 $REPO -> renderers/shotium ..."
  git clone --depth 1 "$REPO" "$DIR" || fail "git clone 失败"
fi

# ---- 安装依赖 ----------------------------------------------------------------
# 装没装上只看 @shotkit/shotium 的实际路径，不看包管理器的退出码：
# renderers/shotium 一般不在 Yunzai 的 pnpm workspace 里，根目录 pnpm install
# 打印 "Already up to date" 并返回 0，也完全可能压根没碰渲染器的依赖。
dep_installed() {
  [ -d "$DIR/node_modules/@shotkit/shotium" ] || [ -d "$ROOT/node_modules/@shotkit/shotium" ]
}

if command -v pnpm >/dev/null 2>&1; then
  info "根目录 pnpm install ..."
  (cd "$ROOT" && pnpm install) || info "根目录 pnpm install 没跑成功（通常是别的依赖拉不下来），继续往下走"
  if dep_installed; then
    info "@shotkit/shotium 已就位，跳过单独安装"
  else
    info "根目录安装没有装上 @shotkit/shotium，改为只安装渲染器自身的依赖 ..."
    (cd "$DIR" && pnpm install --ignore-workspace) || info "pnpm install --ignore-workspace 没跑成功"
  fi
elif command -v npm >/dev/null 2>&1; then
  info "未找到 pnpm，在 renderers/shotium 里用 npm install ..."
  (cd "$DIR" && npm install --no-package-lock) || info "npm install 没跑成功"
else
  fail "未找到 pnpm 或 npm"
fi

dep_installed || fail "@shotkit/shotium 没有装上，请检查上面的安装日志（deprecated、peer dependency 之类的告警可以忽略，要找的是网络或权限错误）"

# ---- 写配置 ------------------------------------------------------------------
set_renderer_name shotium

if [ -n "$MODE" ]; then
  cfg="$DIR/config.yaml"
  [ -f "$cfg" ] || cp "$DIR/config_default.yaml" "$cfg"
  awk -v line="mode: $MODE" 'BEGIN{done=0} /^mode:/ && !done {print line; done=1; next} {print}' "$cfg" > "$cfg.tmp"
  mv "$cfg.tmp" "$cfg"
  info "renderers/shotium/config.yaml -> mode: $MODE"
fi

info "完成。重启 Yunzai，日志出现「加载渲染后端 shotium」即生效"
