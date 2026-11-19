// 生成桌面快捷方式图标（192x192 PNG，蓝色圆角底 + 白色箭头）
// 用法: node scripts/gen-shortcut-icons.cjs
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const SIZE = 192;
const RADIUS = 44;
const BG = [31, 111, 235];   // #1F6FEB
const FG = [255, 255, 255];

function crc32(buf) {
  let c;
  const table = crc32.table || (crc32.table = (() => {
    const t = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c;
    }
    return t;
  })());
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function inRoundedRect(x, y) {
  const r = RADIUS;
  if (x < 0 || y < 0 || x > SIZE - 1 || y > SIZE - 1) return false;
  const cx = Math.min(Math.max(x, r), SIZE - 1 - r);
  const cy = Math.min(Math.max(y, r), SIZE - 1 - r);
  const dx = x - cx;
  const dy = y - cy;
  return dx * dx + dy * dy <= r * r;
}

// 箭头几何（以 192 见方为基准，向上）
function inArrow(x, y) {
  // 箭杆
  if (x >= 84 && x <= 107 && y >= 80 && y <= 138) return true;
  // 箭头三角（顶点 y=42，底边 y=86，半宽 32）
  if (y >= 42 && y <= 86) {
    const halfWidth = ((y - 42) / (86 - 42)) * 32;
    if (Math.abs(x - 96) <= halfWidth) return true;
  }
  // 底部托盘
  if (y >= 148 && y <= 160 && x >= 52 && x <= 140) return true;
  return false;
}

function render(flip) {
  const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);
  for (let y = 0; y < SIZE; y++) {
    raw[y * (SIZE * 4 + 1)] = 0; // filter type: none
    for (let x = 0; x < SIZE; x++) {
      const i = y * (SIZE * 4 + 1) + 1 + x * 4;
      const sy = flip ? SIZE - 1 - y : y;
      if (inRoundedRect(x, y)) {
        const isFg = inArrow(x, sy);
        raw[i] = isFg ? FG[0] : BG[0];
        raw[i + 1] = isFg ? FG[1] : BG[1];
        raw[i + 2] = isFg ? FG[2] : BG[2];
        raw[i + 3] = 255;
      } else {
        raw[i] = 0; raw[i + 1] = 0; raw[i + 2] = 0; raw[i + 3] = 0;
      }
    }
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0);
  ihdr.writeUInt32BE(SIZE, 4);
  ihdr[8] = 8;    // bit depth
  ihdr[9] = 6;    // color type RGBA
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

const outDir = path.join(__dirname, '..', 'entry', 'src', 'main', 'resources', 'base', 'media');
fs.writeFileSync(path.join(outDir, 'shortcut_upload.png'), render(false));
fs.writeFileSync(path.join(outDir, 'shortcut_download.png'), render(true));
console.log('written: shortcut_upload.png, shortcut_download.png ->', outDir);
