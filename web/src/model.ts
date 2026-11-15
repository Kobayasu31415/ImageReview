// 修正ノートのデータ。座標は「画像の幅を 1000 とした」値で持ち、表示サイズに左右されない。

export type Point = [number, number];
export type StrokeWidth = 2 | 4 | 8;
export type Stroke = {color: string; width: StrokeWidth; points: Point[]};
export type Reference = {name: string; src: string};
export type Note = {id: number; x: number; y: number; text: string; color: string; references?: Reference[]};
export type Doc = {name: string; image: string; notes: Note[]; strokes: Stroke[]};

export const BOARD_WIDTH = 1000;
export const EMPTY_DOC: Doc = {name: '', image: '', notes: [], strokes: []};

/** 読み込める画像（data URL）。保存したノートを開くときの検証にも使う。 */
export const IMAGE_DATA = /^data:image\/(png|jpe?g|gif|webp|bmp);base64,/i;
const HEX_COLOR = /^#[a-f0-9]{6}$/i;

export const tagRadius = (height: number) => Math.min(13, height * 0.055);

/** 番号タグが画像の外にはみ出さない位置に収める。 */
export function clampTag([x, y]: Point, height: number): Point {
  const r = tagRadius(height) + 1;
  return [Math.min(BOARD_WIDTH - r, Math.max(r, x)), Math.min(height - r, Math.max(r, y))];
}

export const nextNoteId = (notes: Note[]) => Math.max(0, ...notes.map(n => n.id)) + 1;
export const writtenNotes = (doc: Doc) => doc.notes.filter(n => n.text.trim());

/** 保存したノート（.review.json）の中身として正しいか。 */
export function isValidDoc(value: unknown): value is Doc {
  const doc = value as Doc;
  if (!doc || typeof doc.name !== 'string' || typeof doc.image !== 'string' || !IMAGE_DATA.test(doc.image)) return false;
  if (!Array.isArray(doc.notes) || !Array.isArray(doc.strokes)) return false;
  const notesOK = doc.notes.every(
    n =>
      Number.isSafeInteger(n.id) && n.id > 0 && Number.isFinite(n.x) && Number.isFinite(n.y) &&
      typeof n.text === 'string' && HEX_COLOR.test(n.color) &&
      (n.references === undefined ||
        (Array.isArray(n.references) &&
          n.references.every(r => r && typeof r.name === 'string' && typeof r.src === 'string' && IMAGE_DATA.test(r.src)))),
  );
  const strokesOK = doc.strokes.every(
    s =>
      HEX_COLOR.test(s.color) && [2, 4, 8].includes(s.width) && Array.isArray(s.points) && s.points.length > 0 &&
      s.points.every(p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite)),
  );
  return notesOK && strokesOK && new Set(doc.notes.map(n => n.id)).size === doc.notes.length;
}

/** 画像の縦横比から、幅 1000 に対する高さを求める。 */
export async function boardHeight(image: string): Promise<number> {
  const img = new Image();
  img.src = image;
  await img.decode();
  return (BOARD_WIDTH * img.naturalHeight) / img.naturalWidth;
}

export function readAsDataURL(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}
