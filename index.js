import Shotium from "./lib/shotium.js"

/**
 * shotium 渲染后端
 *
 * 在 config/config/renderer.yaml 里把 name 改成 shotium 即可启用，
 * 上层的 e.runtime.render / puppeteer.screenshot / puppeteer.screenshots 调用方式不变。
 *
 * @param config 本地 config.yaml 的配置内容
 * @returns renderer 渲染器对象
 * @returns renderer.id 渲染器 ID，对应 renderer.yaml 中选择的 name
 * @returns renderer.type 渲染类型，目前只有 image
 * @returns renderer.render 渲染入口
 */
export default function (config) {
  return new Shotium(config)
}
