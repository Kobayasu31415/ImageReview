import {AI_MAX_EDGE, canvasBlob, composeImage, download, formatBytes} from './compose';
import {editor} from './editor';
import {importMedia, type PickPdfPage} from './media';
import {boardHeight, isValidDoc, readAsDataURL, writtenNotes, type Doc} from './model';

/** 画面（React）が差し込む窓口。ここを通すことで、Mac アプリからの呼び出しも同じ処理を使える。 */
export const ui: {pickPage: PickPdfPage; notify: (message: string, isError?: boolean) => void} = {
  pickPage: async () => null,
  notify: () => {},
};
/** 画面が上の窓口を差し込み終えたら解決する。起動直後に渡されたファイルは、これを待ってから開く。 */
let markReady = () => {};
export const uiReady = new Promise<void>(resolve => (markReady = resolve));
export const setUIReady = () => markReady();

// ---- Mac アプリとの橋渡し ----
export type Destination = {name: string; prefill: boolean};
type NativeBridge = {postMessage(message: unknown): void};
declare global {
  interface Window {
    imageReviewAI?: Record<string, Destination>;
    webkit?: {messageHandlers?: {native?: NativeBridge}};
  }
}
const native = window.webkit?.messageHandlers?.native;
/** 「AIに送る」の送り先。Mac アプリの中でだけ値が入る。 */
export const destinations: Record<string, Destination> = native ? window.imageReviewAI ?? {} : {};

// ---- 開く ----
export async function openFile(file: File, isProject = /\.json$/i.test(file.name)) {
  try {
    let doc: Doc;
    if (isProject) {
      const data = JSON.parse(await file.text());
      if (data.version !== 1 || !isValidDoc(data.state)) throw new Error('invalid note');
      doc = data.state;
    } else {
      const media = await importMedia(file, ui.pickPage);
      if (!media) return;
      doc = {name: media.name, image: media.src, notes: [], strokes: []};
      if (!isValidDoc(doc)) throw new Error('unsupported image');
    }
    const height = await boardHeight(doc.image);
    if (editor.getState().dirty && !window.confirm('未保存の変更があります。別のファイルを開きますか？')) return;
    editor.open(doc, height);
  } catch {
    ui.notify('読み込めませんでした。画像、パスワード保護のないPDF、または保存したノートを選んでください。', true);
  }
}

/** ファイル選択を出して、選ばれたものを渡す。 */
export function chooseFiles(accept: string, isMultiple: boolean, then: (files: File[]) => void) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = accept;
  input.multiple = isMultiple;
  input.onchange = () => then(Array.from(input.files ?? []));
  input.click();
}
export const MEDIA_TYPES = 'image/png,image/jpeg,image/webp,image/gif,image/bmp,application/pdf,.pdf';

// ---- 保存・書き出し ----
export function saveNote() {
  const {doc} = editor.getState();
  download(new Blob([JSON.stringify({version: 1, state: doc})], {type: 'application/json'}), `${doc.name}.review.json`);
  editor.markSaved();
  ui.notify('ノートを書き出しました');
}

export type ExportOptions = {size: 'fit' | 'full'; type: 'image/jpeg' | 'image/png'; withNotes: boolean};

export async function exportImage({size, type, withNotes}: ExportOptions) {
  const {doc, height} = editor.getState();
  try {
    const canvas = await composeImage(doc, height, {maxEdge: size === 'fit' ? AI_MAX_EDGE : 0, withNotes});
    const blob = await canvasBlob(canvas, type);
    const base = doc.name.replace(/\.(png|jpe?g|gif|webp|bmp|pdf)(（\d+ページ）)?$/i, '$2');
    download(blob, `${base}-review.${type === 'image/png' ? 'png' : 'jpg'}`);
    ui.notify(`画像を書き出しました（${canvas.width}×${canvas.height}・${formatBytes(blob.size)}）`);
  } catch {
    ui.notify('画像を書き出せませんでした。', true);
  }
}

// ---- AI に送る ----
export async function sendToAI(target: string, fresh: boolean) {
  const {doc, height} = editor.getState();
  const lines = writtenNotes(doc).map(n => `${n.id}. ${n.text.trim().replace(/\n+/g, '\n   ')}`);
  const prompt = lines.length ? `添付した画像の番号の箇所について、次の修正をお願いします。\n\n${lines.join('\n')}` : '';
  const png = async (withNotes: boolean) =>
    readAsDataURL(await canvasBlob(await composeImage(doc, height, {maxEdge: AI_MAX_EDGE, withNotes}), 'image/png'));
  try {
    // 指示文を文字として渡せるかはアプリ側が決めるので、渡せない場合に使う「指示文入り」の画像も一緒に渡す。
    native?.postMessage({
      type: 'send', target, fresh, prompt,
      image: await png(false), imageWithNotes: lines.length ? await png(true) : '',
    });
    ui.notify(`${destinations[target]?.name ?? 'AI'}に送りました`);
  } catch {
    ui.notify('送る画像を作れませんでした。', true);
  }
}
