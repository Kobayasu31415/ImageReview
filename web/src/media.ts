import {readAsDataURL, type Reference} from './model';

// PDF は同梱の pdf.js で読む（オフラインで動くよう、本体・ワーカー・フォント類を 1 つのファイルに詰めてある）。
// 5MB ほどあるので、初めて PDF を開くときにだけ読み込む。
type PdfBundle = {main: string; worker: string; assets: Record<string, string>};
declare const pdfBundle: PdfBundle;

export type PdfPage = {getViewport(o: {scale: number}): {width: number; height: number}; render(o: unknown): {promise: Promise<void>}};
export type PdfDocument = {numPages: number; getPage(n: number): Promise<PdfPage>};
type PdfLibrary = {
  GlobalWorkerOptions: {workerSrc: string};
  getDocument(options: unknown): {promise: Promise<PdfDocument>; destroy(): Promise<void>};
};

/** 複数ページの PDF で、読み込むページを選んでもらう（選ばなければ null）。画面側が用意する。 */
export type PickPdfPage = (doc: PdfDocument, name: string) => Promise<number | null>;

const decode = (base64: string) => Uint8Array.from(atob(base64), ch => ch.charCodeAt(0));

let library: Promise<PdfLibrary> | undefined;
function pdfLibrary(): Promise<PdfLibrary> {
  library ??= (async () => {
    await new Promise<void>((resolve, reject) => {
      const script = document.createElement('script');
      script.src = './vendor/pdfjs-local.js';
      script.onload = () => resolve();
      script.onerror = () => reject(new Error('pdf.js を読み込めません'));
      document.head.append(script);
    });
    const moduleURL = (base64: string) => URL.createObjectURL(new Blob([decode(base64)], {type: 'text/javascript'}));
    const lib: PdfLibrary = await import(/* @vite-ignore */ moduleURL(pdfBundle.main));
    lib.GlobalWorkerOptions.workerSrc = moduleURL(pdfBundle.worker);
    return lib;
  })();
  return library;
}

class OfflinePdfResources {
  async fetch({filename}: {filename: string}) {
    const encoded = pdfBundle.assets[filename];
    if (typeof encoded !== 'string') throw new Error('Missing PDF resource');
    return decode(encoded);
  }
}

/** PDF の 1 ページを、長辺が limit ピクセルになる大きさで描く。 */
export async function renderPdfPage(doc: PdfDocument, pageNumber: number, limit: number): Promise<HTMLCanvasElement> {
  const page = await doc.getPage(pageNumber);
  const size = page.getViewport({scale: 1});
  const viewport = page.getViewport({scale: Math.min(limit / Math.max(size.width, size.height), 4)});
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.ceil(viewport.width));
  canvas.height = Math.max(1, Math.ceil(viewport.height));
  await page.render({canvas, viewport}).promise;
  return canvas;
}

const isPdf = (file: File) => file.type === 'application/pdf' || /\.pdf$/i.test(file.name);

/** 画像ファイルはそのまま、PDF は選んだページを画像にして返す。ページ選択を取り消したら null。 */
export async function importMedia(file: File, pickPage: PickPdfPage): Promise<Reference | null> {
  if (!isPdf(file)) return {name: file.name, src: await readAsDataURL(file)};
  const lib = await pdfLibrary();
  const task = lib.getDocument({
    data: new Uint8Array(await file.arrayBuffer()), BinaryDataFactory: OfflinePdfResources,
    useWorkerFetch: false, cMapPacked: true, isEvalSupported: false, useSystemFonts: true,
  });
  try {
    const doc = await task.promise;
    const pageNumber = doc.numPages === 1 ? 1 : await pickPage(doc, file.name);
    if (pageNumber === null) return null;
    const canvas = await renderPdfPage(doc, pageNumber, 3500);
    return {name: `${file.name}（${pageNumber}ページ）`, src: canvas.toDataURL('image/png')};
  } finally {
    await task.destroy();
  }
}
