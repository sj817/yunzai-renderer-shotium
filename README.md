# yunzai-renderer-shotium

Miao-Yunzai 的 [shotium](https://github.com/sj817/shotium) 渲染后端，放进 `renderers/` 目录即可替代 puppeteer 出图。

shotium 是裁掉 V8 的 Chromium 内核：只保留 Blink 布局、Skia 光栅化、字体与图片解码和网络栈，以 Node-API 扩展的形式直接运行在 Yunzai 进程里。没有浏览器进程，没有 CDP 往返，也不需要下载一百多 MB 的 Chromium。代价是模板里的 `<script>` 不会执行，只能渲染服务端已经填好数据的静态 HTML。

上层调用方式保持不变：`e.runtime.render()`、`Common.render()`、`puppeteer.screenshot()`、`puppeteer.screenshots()` 都照常使用，插件侧不需要改动。

## 环境要求

- Miao-Yunzai 3.1 及以上（带 `renderers/` 目录的版本）
- Node.js 18 及以上
- Windows、macOS、Linux 的 x64 或 arm64；引擎二进制随 `@pixel.js/shotium` 的 optionalDependencies 自动安装，不需要本地编译

## 快速配置

在 Yunzai 根目录执行一条命令，脚本会完成克隆（已存在则更新）、安装依赖、把 `renderer.yaml` 切到 `shotium`：

```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.ps1 | iex
```

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.sh | bash
```

克隆之后脚本就在 `renderers/shotium` 里，可以带参数本地运行：

| 参数 | `install.ps1` | `install.sh` | 作用 |
| --- | --- | --- | --- |
| 运行方式 | `-Mode daemon` | `--mode daemon` | 生成 `config.yaml` 并把引擎切到守护进程模式（`inprocess` 为进程内） |
| 卸载 | `-Uninstall` | `--uninstall` | `renderer.yaml` 的 `name` 清空（回到 puppeteer），删除 `renderers/shotium` |
| 指定根目录 | `-Root <dir>` | `--root <dir>` | 不在 Yunzai 根目录运行时使用 |

```powershell
.\renderers\shotium\install.ps1 -Mode daemon
```

```bash
bash renderers/shotium/install.sh --mode daemon
```

远程执行时也可以传参：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.ps1))) -Mode daemon
```

```bash
curl -fsSL https://raw.githubusercontent.com/sj817/yunzai-renderer-shotium/main/install.sh | bash -s -- --mode daemon
```

依赖安装先跑根目录 `pnpm install`，跑完以 `renderers/shotium/node_modules/@pixel.js/shotium` 是否存在为准，而不是看 pnpm 的退出码：探不到就在 `renderers/shotium` 里再跑一次 `pnpm install --ignore-workspace`，仍然探不到才报错。没有 pnpm 时退回 npm。环境变量 `SHOTIUM_RENDERER_REPO` 可以替换仓库地址，用于镜像。

## 手动安装

在 Yunzai 根目录执行：

```bash
git clone https://github.com/sj817/yunzai-renderer-shotium renderers/shotium
pnpm install
```

Miao-Yunzai 的 `pnpm-workspace.yaml` 包含 `renderers/**`，正常情况下根目录 `pnpm install` 会一并安装 `@pixel.js/shotium`。但根目录安装返回成功不等于渲染器的依赖装上了——workspace 配置被改过，或者根目录安装被别的依赖卡住时，pnpm 可能只打印 `Already up to date` 就结束。装完确认一下：

```bash
ls renderers/shotium/node_modules/@pixel.js/shotium
```

```powershell
Test-Path renderers\shotium\node_modules\@pixel.js\shotium
```

目录不存在就在渲染器目录里单独装一次：

```bash
cd renderers/shotium
pnpm install --ignore-workspace
```

然后把 `config/config/renderer.yaml` 改为：

```yaml
name: shotium
```

重启 Yunzai。日志出现 `加载渲染后端 shotium`，第一次出图时出现 `shotium 引擎已启动`，即表示生效。

Miao-Yunzai 自带的 `renderers/.gitignore` 会忽略 `puppeteer` 以外的所有渲染器目录，因此这份克隆不会污染 Yunzai 自身的 Git 状态。

## 更新

```bash
cd renderers/shotium
git pull
cd ../..
pnpm install
```

`@pixel.js/shotium` 的版本有变化时同样确认一次 `renderers/shotium/node_modules/@pixel.js/shotium`，没更新到就在该目录下跑 `pnpm install --ignore-workspace`。跑 `bash renderers/shotium/install.sh`（或 `.\renderers\shotium\install.ps1`）会把这一套检查和回退都做掉。

## 配置

复制 `config_default.yaml` 为 `config.yaml` 后修改，改完需要重启。`config.yaml` 已在 `.gitignore` 中，不会被 `git pull` 覆盖。

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `mode` | `inprocess` | `inprocess` 引擎跑在 Yunzai 进程里；`daemon` 引擎跑在独立常驻进程里，Yunzai 重启不用重新冷启动，断线自动重连 |
| `viewport` | `800 x 600` | 默认视窗，与 puppeteer 默认值一致，模板布局不变 |
| `scale` | `1` | 设备像素比。喵喵的模板通过 `body` 上的 `transform:scale` 放大，这里保持 `1` |
| `waitUntil` | `load` | 见下方「等待策略」 |
| `timeout` | `30000` | 页面加载超时（毫秒） |
| `imgType` | `jpeg` | 默认图片类型，`jpeg` / `png` / `webp` |
| `quality` | `90` | `jpeg` / `webp` 压缩质量 |
| `multiPageHeight` | `4000` | 分片截图单张高度（CSS 像素），上限 32000 |
| `releaseMemoryEvery` | `100` | 每渲染多少张把引擎可重建的内存还给系统，`0` 关闭 |
| `cacheDir` | 空 | HTTP 磁盘缓存目录，用于模板引用的远程图片、字体；留空用引擎默认目录，填 `off` 关闭 |
| `cacheMaxBytes` | `268435456` | 磁盘缓存上限（字节） |
| `userAgent` | 空 | 自定义 User-Agent，留空用引擎内置 |
| `idleTimeoutMs` | `300000` | `daemon` 模式下守护进程空闲退出时间（毫秒），`0` 不退出 |
| `logStats` | `false` | 日志附带引擎侧耗时与网络统计 |

### 等待策略

`runtime.render()` 固定传 `pageGotoParams.waitUntil: networkidle2`。引擎的 `networkidle` 要在 load 之后再等 500 ms 无请求，本地静态模板没有必要为此每张多等半秒，所以默认忽略调用方的取值，按 `load` 处理：DOM 解析完、所有资源请求结束即截图。

只有模板会在 load 之后继续拉取资源时，才需要把配置改成 `networkidle`，或改成 `auto` 跟随调用方。

## 与 puppeteer 渲染器的参数对照

| 调用方参数 | 行为 |
| --- | --- |
| `tplFile` / `saveId` | 与原来一致：art-template 渲染后写入 `temp/html`，再以 `file://` 交给引擎 |
| 截图区域 | 先找 `#container`，没有则退回 `body`，与 `page.$("#container") \|\| page.$("body")` 一致 |
| `imgType` / `quality` | 原样传给引擎；`png` 不带 `quality` |
| `omitBackground` | `png` / `webp` 生效；`jpeg` 没有 alpha 通道，忽略 |
| `path` | 另存一份到指定路径，返回值仍是 Buffer |
| `multiPage` / `multiPageHeight` | 交给引擎的分片接口 `screenshotTiles()`，一次布局切成若干横条。片数按 `ceil(高度 / 单页高度)` 计算，最后一片是余数，固定输出 `jpeg` |
| `pageGotoParams.timeout` | 大于 `0` 时优先于配置中的 `timeout` |
| `pageGotoParams.waitUntil` | 默认忽略，见「等待策略」 |
| 每 100 张重启浏览器 | 换成每 `releaseMemoryEvery` 张调用一次引擎的 `releaseMemory()` |

分片截图与 puppeteer 的差别：puppeteer 是改视窗高度、滚动、重截几次，一次 `multiPage` 要重新布局 N 遍；这里文档只加载、布局、光栅化一次，引擎在光栅化的过程中按行切开、逐片编码，同一时刻只存在一片的位图。每一片都来自同一次布局，分片之间不会出现样式对不上的情况。

片数的算法与 puppeteer 不同：puppeteer 用 `round`，最后一片不足半页时会并进上一页（所以最后一页可能有 1.5 倍高）；这里用 `ceil`，`multiPageHeight` 是每一片的硬上限，最后一片是余数。

## 已知限制

- 不执行 JavaScript。喵喵插件的模板全部是静态的，不受影响。genshin 插件里少数模板依赖前端脚本画图，用 shotium 渲染时对应部分会缺失：
  - `ledger`（札记，G2Plot 饼图）
  - `payLog`（充值记录，ECharts）
  - `mysNews`（米游社公告，右下角二维码）
- 缩放请继续使用模板里 `body` 上的 `transform:scale`（即 `Common.render` 的 `scale` 参数）。配置中的 `scale` 是设备像素比，两者叠加会把图放得很大。

## 卸载

把 `config/config/renderer.yaml` 的 `name` 改回空或 `puppeteer`，删除 `renderers/shotium` 目录，重启即可。

## 许可

MIT
