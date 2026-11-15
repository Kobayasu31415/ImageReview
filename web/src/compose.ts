import {BOARD_WIDTH, tagRadius, writtenNotes, type Doc, type Note} from './model';

/** AI は大きい画像を内部で縮小して読むので、これ以上の大きさは容量が増えるだけになる。 */
export const AI_MAX_EDGE = 2000;

const FONT = '"Hiragino Sans", "Yu Gothic UI", system-ui, sans-serif';

function wrapLines(ctx: CanvasRenderingContext2D, text: string, width: number): string[] {
  const lines: string[] = [];
  for (const paragraph of text.split('\n')) {
    let line = '';
    for (const ch of paragraph) {
      if (line && ctx.measureText(line + ch).width > width) {
        lines.push(line);
        line = ch;
      } else {
        line += ch;
      }
    }
    lines.push(line);
  }
  return lines;
}

function drawTag(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, note: Note) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = note.color;
  ctx.fill();
  ctx.lineWidth = r * 0.15;
  ctx.strokeStyle = '#fff';
  ctx.stroke();
  ctx.font = `bold ${r * 1.1}px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  ctx.lineJoin = 'round';
  ctx.lineWidth = r * 0.12;
  ctx.strokeStyle = '#222';
  ctx.strokeText(String(note.id), x, y + r * 0.38);
  ctx.fillStyle = '#fff';
  ctx.fillText(String(note.id), x, y + r * 0.38);
}

/**
 * 画像に手書きと番号タグを焼き込む。withNotes なら画像の下に指示文の一覧も付ける。
 * maxEdge が 0 なら原寸、指定すれば長辺がそれ以下になるよう縮める。
 */
export async function composeImage(doc: Doc, height: number, options: {maxEdge: number; withNotes: boolean}): Promise<HTMLCanvasElement> {
  const source = new Image();
  source.src = doc.image;
  await source.decode();
  const fit = options.maxEdge ? Math.min(1, options.maxEdge / Math.max(source.naturalWidth, source.naturalHeight)) : 1;
  const w = Math.max(1, Math.round(source.naturalWidth * fit)), h = Math.max(1, Math.round(source.naturalHeight * fit));
  const k = w / BOARD_WIDTH;

  const notes = options.withNotes ? writtenNotes(doc) : [];
  const size = Math.max(15, Math.round(w * 0.017)), pad = Math.round(size * 1.3), lineHeight = Math.round(size * 1.6);
  const badge = size * 0.8, gap = Math.round(size * 0.6), textFont = `${size}px ${FONT}`;
  const canvas = document.createElement('canvas'), ctx = canvas.getContext('2d')!;
  ctx.font = textFont;
  const blocks = notes.map(n => wrapLines(ctx, n.text.trim(), w - pad * 2 - badge * 2 - size * 0.7));
  const listHeight = notes.length
    ? pad * 2 + blocks.reduce((sum, lines) => sum + lines.length * lineHeight, 0) + (notes.length - 1) * gap
    : 0;

  canvas.width = w;
  canvas.height = h + listHeight;
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(source, 0, 0, w, h);

  ctx.lineJoin = ctx.lineCap = 'round';
  for (const stroke of doc.strokes) {
    ctx.strokeStyle = ctx.fillStyle = stroke.color;
    ctx.lineWidth = stroke.width * k;
    ctx.beginPath();
    if (stroke.points.length === 1) {
      ctx.arc(stroke.points[0][0] * k, stroke.points[0][1] * k, (stroke.width * k) / 2, 0, Math.PI * 2);
      ctx.fill();
      continue;
    }
    stroke.points.forEach(([x, y], i) => (i ? ctx.lineTo(x * k, y * k) : ctx.moveTo(x * k, y * k)));
    ctx.stroke();
  }
  const r = tagRadius(height) * k;
  for (const note of doc.notes) drawTag(ctx, note.x * k, note.y * k, r, note);

  if (notes.length) {
    ctx.fillStyle = '#d5dbd3';
    ctx.fillRect(0, h, w, Math.max(1, Math.round(k)));
    let y = h + pad;
    notes.forEach((note, i) => {
      drawTag(ctx, pad + badge, y + lineHeight / 2, badge, note);
      ctx.font = textFont;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = '#1c2a27';
      for (const line of blocks[i]) {
        ctx.fillText(line, pad + badge * 2 + size * 0.7, y + lineHeight / 2);
        y += lineHeight;
      }
      y += gap;
    });
  }
  return canvas;
}

export const canvasBlob = (canvas: HTMLCanvasElement, type: string) =>
  new Promise<Blob>((resolve, reject) => canvas.toBlob(blob => (blob ? resolve(blob) : reject(new Error('toBlob'))), type, 0.9));

export const formatBytes = (bytes: number) => (bytes < 1e6 ? `${Math.round(bytes / 1024)}KB` : `${(bytes / 1e6).toFixed(1)}MB`);

/** ブラウザーの保存（Mac アプリの中では保存ダイアログ）にファイルを渡す。 */
export function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
}
