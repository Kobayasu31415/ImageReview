// 注釈を焼き込んだ画像の書き出しと、AI アプリへの受け渡し。
// index.html のインラインスクリプトが定義する $ / state / height / read を使う。

const AI_MAX_EDGE = 2000;      // AI は大きい画像を内部で縮小して読むので、これ以上は容量が増えるだけ
const remembered = {
 get(key, fallback) { try { return localStorage.getItem('imagereview.' + key) ?? fallback } catch { return fallback } },
 set(key, value) { try { localStorage.setItem('imagereview.' + key, value) } catch {} },
};
const writtenNotes = () => state.notes.filter(n => n.text.trim());

function wrapLines(ctx, text, width) {
 const lines = [];
 for (const paragraph of text.split('\n')) {
  let line = '';
  for (const ch of paragraph) {
   if (line && ctx.measureText(line + ch).width > width) { lines.push(line); line = ch } else line += ch;
  }
  lines.push(line);
 }
 return lines;
}

function drawTag(ctx, x, y, r, note) {
 ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
 ctx.fillStyle = note.color; ctx.fill();
 ctx.lineWidth = r * .15; ctx.strokeStyle = '#fff'; ctx.stroke();
 ctx.font = `bold ${r * 1.1}px "Hiragino Sans", "Yu Gothic UI", system-ui, sans-serif`;
 ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.lineJoin = 'round';
 ctx.lineWidth = r * .12; ctx.strokeStyle = '#222'; ctx.strokeText(note.id, x, y + r * .38);
 ctx.fillStyle = '#fff'; ctx.fillText(note.id, x, y + r * .38);
}

/** 画像に手書きと番号タグを焼き込む。withNotes なら画像の下に指示文の一覧も付ける。 */
async function composeImage({maxEdge, withNotes}) {
 const source = new Image(); source.src = state.image; await source.decode();
 const fit = maxEdge ? Math.min(1, maxEdge / Math.max(source.naturalWidth, source.naturalHeight)) : 1;
 const w = Math.max(1, Math.round(source.naturalWidth * fit)), h = Math.max(1, Math.round(source.naturalHeight * fit));
 const k = w / 1000;   // 注釈は「幅 1000」の座標で持っている

 const notes = withNotes ? writtenNotes() : [];
 const size = Math.max(15, Math.round(w * .017)), pad = Math.round(size * 1.3), lineHeight = Math.round(size * 1.6), badge = size * .8;
 const textFont = `${size}px "Hiragino Sans", "Yu Gothic UI", system-ui, sans-serif`;
 const canvas = document.createElement('canvas'), ctx = canvas.getContext('2d');
 ctx.font = textFont;
 const blocks = notes.map(n => wrapLines(ctx, n.text.trim(), w - pad * 2 - badge * 2 - size * .7));
 const listHeight = notes.length ? pad * 2 + blocks.reduce((sum, lines) => sum + lines.length * lineHeight, 0) + (notes.length - 1) * Math.round(size * .6) : 0;

 canvas.width = w; canvas.height = h + listHeight;
 ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
 ctx.drawImage(source, 0, 0, w, h);

 ctx.lineJoin = ctx.lineCap = 'round';
 for (const s of state.strokes) {
  ctx.strokeStyle = ctx.fillStyle = s.color; ctx.lineWidth = s.width * k;
  ctx.beginPath();
  if (s.points.length === 1) { ctx.arc(s.points[0][0] * k, s.points[0][1] * k, s.width * k / 2, 0, Math.PI * 2); ctx.fill(); continue }
  s.points.forEach(([x, y], i) => i ? ctx.lineTo(x * k, y * k) : ctx.moveTo(x * k, y * k));
  ctx.stroke();
 }
 const r = Math.min(13, height * .055) * k;
 for (const n of state.notes) drawTag(ctx, n.x * k, n.y * k, r, n);

 if (notes.length) {
  ctx.fillStyle = '#d5dbd3'; ctx.fillRect(0, h, w, Math.max(1, Math.round(k)));
  let y = h + pad;
  notes.forEach((n, i) => {
   drawTag(ctx, pad + badge, y + lineHeight / 2, badge, n);
   ctx.font = textFont; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#1c2a27';
   for (const line of blocks[i]) { ctx.fillText(line, pad + badge * 2 + size * .7, y + lineHeight / 2); y += lineHeight }
   y += Math.round(size * .6);
  });
 }
 return canvas;
}

const canvasBlob = (canvas, type) => new Promise(done => canvas.toBlob(done, type, .9));
const kilobytes = bytes => bytes < 1e6 ? Math.round(bytes / 1024) + 'KB' : (bytes / 1e6).toFixed(1) + 'MB';

// ---- 画像を書き出す ----
$('export').onclick = () => {
 $('exportSize').value = remembered.get('exportSize', 'fit');
 $('exportType').value = remembered.get('exportType', 'image/jpeg');
 $('exportNotes').checked = remembered.get('exportNotes', '1') === '1';
 $('exportNotes').disabled = !writtenNotes().length;
 $('exportDialog').returnValue = '';
 $('exportDialog').showModal();
};
$('exportDialog').addEventListener('close', async () => {
 if ($('exportDialog').returnValue !== 'export') return;
 const type = $('exportType').value, fit = $('exportSize').value === 'fit', withNotes = $('exportNotes').checked;
 remembered.set('exportSize', $('exportSize').value); remembered.set('exportType', type); remembered.set('exportNotes', withNotes ? '1' : '0');
 try {
  const canvas = await composeImage({maxEdge: fit ? AI_MAX_EDGE : 0, withNotes});
  const blob = await canvasBlob(canvas, type);
  const base = state.name.replace(/\.(png|jpe?g|gif|webp|bmp|pdf)(（\d+ページ）)?$/i, '$2');
  const a = document.createElement('a'), url = URL.createObjectURL(blob);
  a.href = url; a.download = base + '-review.' + (type === 'image/png' ? 'png' : 'jpg'); a.click();
  setTimeout(() => URL.revokeObjectURL(url), 3000);
  $('status').textContent = `画像を書き出しました（${canvas.width}×${canvas.height}・${kilobytes(blob.size)}）`;
 } catch { $('status').textContent = '画像を書き出せませんでした。' }
});

// ---- AI に送る（Mac アプリの中でだけ使える） ----
// フッターのトグルで送り先と送り方を選んでおき、ボタン 1 回で送る。
const native = window.webkit?.messageHandlers?.native, destinations = window.imageReviewAI || {};
if (native && Object.keys(destinations).length) {
 $('sendbar').hidden = false;
 for (const [id, d] of Object.entries(destinations)) {
  const option = document.createElement('button');
  option.dataset.value = id; option.textContent = d.name;
  $('sendTarget').append(option);
 }
 const chosen = group => $(group).querySelector('[aria-pressed=true]').dataset.value;
 const choose = (group, value) => {
  const options = [...$(group).children], pick = options.find(o => o.dataset.value === value) || options[0];
  for (const o of options) o.setAttribute('aria-pressed', o === pick);
  remembered.set(group, pick.dataset.value);
  $('sendHint').textContent = chosen('sendMode') === 'new' ? '新しいチャットを開いて、指示文と画像を渡します。' : 'いま開いているチャットに、指示文と画像を渡します。';
 };
 for (const group of ['sendTarget', 'sendMode']) {
  for (const o of $(group).children) o.onclick = () => choose(group, o.dataset.value);
  for (const o of $(group).children) o.setAttribute('aria-pressed', false);
 }
 choose('sendMode', remembered.get('sendMode', 'new'));
 choose('sendTarget', remembered.get('sendTarget', ''));

 $('send').onclick = async () => {
  const lines = writtenNotes().map(n => `${n.id}. ${n.text.trim().replace(/\n+/g, '\n   ')}`);
  const prompt = lines.length ? '添付した画像の番号の箇所について、次の修正をお願いします。\n\n' + lines.join('\n') : '';
  const png = async withNotes => read(await canvasBlob(await composeImage({maxEdge: AI_MAX_EDGE, withNotes}), 'image/png'), 'readAsDataURL');
  try {
   // 指示文を文字として渡せるかはアプリ側が決めるので、渡せない場合に使う「指示文入り」の画像も一緒に渡す。
   native.postMessage({type: 'send', target: chosen('sendTarget'), fresh: chosen('sendMode') === 'new', prompt,
    image: await png(false), imageWithNotes: lines.length ? await png(true) : ''});
   $('status').textContent = destinations[chosen('sendTarget')].name + 'に送りました';
  } catch { $('status').textContent = '送る画像を作れませんでした。' }
 };
}
