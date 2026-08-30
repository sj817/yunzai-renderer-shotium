/**
 * 读取编码后图片的像素尺寸，只看文件头，不解码
 *
 * 分片截图需要知道第一次整张渲染出来的容器有多高，
 * 引擎只返回编码后的字节，所以在这里从 PNG / JPEG / WebP 的头部把宽高读出来。
 *
 * @param {Buffer} buf 图片数据
 * @returns {{width: number, height: number} | null} 尺寸（设备像素），无法识别时返回 null
 */
export function imageSize(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null

  /** PNG: 8 字节签名 + IHDR */
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
    if (buf.length < 24) return null
    return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) }
  }

  /** JPEG: 顺着 marker 找 SOFn */
  if (buf[0] === 0xff && buf[1] === 0xd8) {
    let offset = 2
    while (offset + 9 < buf.length) {
      if (buf[offset] !== 0xff) {
        offset++
        continue
      }
      const marker = buf[offset + 1]
      /** 填充字节 */
      if (marker === 0xff) {
        offset++
        continue
      }
      /** SOF0-SOF15，去掉 DHT(C4)、JPG(C8)、DAC(CC) */
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { height: buf.readUInt16BE(offset + 5), width: buf.readUInt16BE(offset + 7) }
      }
      /** 没有长度字段的独立 marker */
      if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        offset += 2
        continue
      }
      offset += 2 + buf.readUInt16BE(offset + 2)
    }
    return null
  }

  /** WebP: RIFF....WEBP + VP8 / VP8L / VP8X */
  if (buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") {
    const chunk = buf.toString("ascii", 12, 16)
    if (chunk === "VP8X" && buf.length >= 30) {
      return {
        width: 1 + buf.readUIntLE(24, 3),
        height: 1 + buf.readUIntLE(27, 3),
      }
    }
    if (chunk === "VP8L" && buf.length >= 25) {
      const bits = buf.readUInt32LE(21)
      return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff) }
    }
    if (chunk === "VP8 " && buf.length >= 30) {
      return {
        width: buf.readUInt16LE(26) & 0x3fff,
        height: buf.readUInt16LE(28) & 0x3fff,
      }
    }
  }

  return null
}
