import {useSyncExternalStore} from 'react';
import {
  clampTag, EMPTY_DOC, nextNoteId,
  type Doc, type Note, type Point, type Reference, type StrokeWidth,
} from './model';

export type Tool = 'tag' | 'brush';
export type Zoom = 'fit' | '1' | '1.5' | '2' | '3';

export type EditorState = {
  doc: Doc;
  /** 画像の幅を 1000 としたときの高さ。 */
  height: number;
  dirty: boolean;
  canUndo: boolean;
  selected: number | null;
  /** 入力欄にフォーカスを移してほしいノート（タグを置いた直後など）。 */
  focus: {id: number; nonce: number} | null;
  tool: Tool;
  color: string;
  width: StrokeWidth;
  zoom: Zoom;
};

type Snapshot = Pick<Doc, 'notes' | 'strokes'>;
const HISTORY_LIMIT = 60;

/**
 * 編集中のノート 1 件分の状態。React の外（Mac アプリからの呼び出しなど）からも同じものを操作できるよう、
 * コンポーネントの state ではなく単独のストアにしている。
 */
class Editor {
  private state: EditorState = {
    doc: EMPTY_DOC, height: 600, dirty: false, canUndo: false, selected: null, focus: null,
    tool: 'tag', color: '#c93235', width: 4, zoom: 'fit',
  };
  private history: Snapshot[] = [];
  private listeners = new Set<() => void>();

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  getState = () => this.state;

  private set(patch: Partial<EditorState>) {
    this.state = {...this.state, ...patch};
    this.listeners.forEach(listener => listener());
  }

  private edit(change: Partial<Snapshot>) {
    this.set({doc: {...this.state.doc, ...change}, dirty: true});
  }

  /** いまの状態を「元に戻す」の戻り先として覚える。変更の直前に呼ぶ。 */
  remember() {
    const {notes, strokes} = this.state.doc;
    this.history.push({notes, strokes});
    if (this.history.length > HISTORY_LIMIT) this.history.shift();
    this.set({canUndo: true});
  }

  undo() {
    const previous = this.history.pop();
    if (previous) this.set({doc: {...this.state.doc, ...previous}, dirty: true, canUndo: this.history.length > 0});
  }

  open(doc: Doc, height: number) {
    this.history = [];
    this.set({doc, height, dirty: false, canUndo: false, selected: null, focus: null, zoom: 'fit'});
  }

  markSaved() {
    this.set({dirty: false});
  }

  setTool(tool: Tool) { this.set({tool}); }
  setColor(color: string) { this.set({color}); }
  setWidth(width: StrokeWidth) { this.set({width}); }
  setZoom(zoom: Zoom) { this.set({zoom}); }
  select(id: number | null) { this.set({selected: id}); }
  requestFocus(id: number) { this.set({selected: id, focus: {id, nonce: Date.now()}}); }

  // ---- 番号タグ ----
  addNote(at: Point): Note {
    this.remember();
    const [x, y] = clampTag(at, this.state.height);
    const note: Note = {id: nextNoteId(this.state.doc.notes), x, y, text: '', color: this.state.color};
    this.edit({notes: [...this.state.doc.notes, note]});
    return note;
  }

  private updateNote(id: number, change: (note: Note) => Note) {
    this.edit({notes: this.state.doc.notes.map(n => (n.id === id ? change(n) : n))});
  }

  moveNote(id: number, to: Point) {
    const [x, y] = clampTag(to, this.state.height);
    this.updateNote(id, n => ({...n, x, y}));
  }

  setNoteText(id: number, text: string) {
    this.updateNote(id, n => ({...n, text}));
  }

  deleteNote(id: number) {
    this.remember();
    this.edit({notes: this.state.doc.notes.filter(n => n.id !== id)});
  }

  addReferences(id: number, references: Reference[]) {
    if (!references.length || !this.state.doc.notes.some(n => n.id === id)) return;
    this.remember();
    this.updateNote(id, n => ({...n, references: [...(n.references ?? []), ...references]}));
  }

  removeReference(id: number, index: number) {
    this.remember();
    this.updateNote(id, n => ({...n, references: (n.references ?? []).filter((_, i) => i !== index)}));
  }

  // ---- ブラシ ----
  beginStroke(at: Point) {
    this.remember();
    const {color, width, doc} = this.state;
    this.edit({strokes: [...doc.strokes, {color, width, points: [at]}]});
  }

  extendStroke(to: Point) {
    const strokes = this.state.doc.strokes, last = strokes[strokes.length - 1];
    if (last) this.edit({strokes: [...strokes.slice(0, -1), {...last, points: [...last.points, to]}]});
  }
}

export const editor = new Editor();
export const useEditor = () => useSyncExternalStore(editor.subscribe, editor.getState);
