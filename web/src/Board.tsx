import {useRef, type PointerEvent} from 'react';
import {editor, useEditor} from './editor';
import {BOARD_WIDTH, tagRadius, type Doc, type Point} from './model';

/** 画像・手書き・番号タグを描く。画面と印刷の両方で同じものを使う。 */
export function BoardArtwork({doc, height, selected = null}: {doc: Doc; height: number; selected?: number | null}) {
  const r = tagRadius(height);
  return (
    <>
      {/* 透過のある画像でも、書き出しや印刷と同じ白地の上に載せる。 */}
      <rect width={BOARD_WIDTH} height={height} fill="#fff" />
      <image href={doc.image} width={BOARD_WIDTH} height={height} />
      {doc.strokes.map((stroke, i) =>
        stroke.points.length === 1 ? (
          <circle key={i} cx={stroke.points[0][0]} cy={stroke.points[0][1]} r={stroke.width / 2} fill={stroke.color} />
        ) : (
          <polyline
            key={i} points={stroke.points.map(p => p.join(',')).join(' ')} fill="none"
            stroke={stroke.color} strokeWidth={stroke.width} strokeLinejoin="round" strokeLinecap="round"
          />
        ),
      )}
      {doc.notes.map(note => (
        <g key={note.id} data-id={note.id} transform={`translate(${note.x} ${note.y})`} className="board-tag">
          {note.id === selected && <circle r={r + 4} className="board-tag-ring" />}
          <circle r={r} fill={note.color} stroke="white" strokeWidth={2} />
          <text
            textAnchor="middle" y={r * 0.38} fill="#fff" stroke="#222" strokeWidth={0.8} paintOrder="stroke"
            fontSize={r * 1.1} fontWeight="bold">
            {note.id}
          </text>
        </g>
      ))}
    </>
  );
}

type Gesture = {pointerId: number} & ({kind: 'stroke'} | {kind: 'tag'; id: number; origin: Point; moving: boolean});

/** 編集できる画像。クリックで番号タグを置き、ドラッグで動かす。ブラシのときはドラッグで線を描く。 */
export function Board() {
  const {doc, height, tool, zoom, selected} = useEditor();
  const svg = useRef<SVGSVGElement>(null);
  const gesture = useRef<Gesture | null>(null);

  const pointAt = (e: PointerEvent): Point => {
    const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(svg.current!.getScreenCTM()!.inverse());
    const snap = (value: number, max: number) => Math.round(Math.min(max, Math.max(0, value)) * 10) / 10;
    return [snap(p.x, BOARD_WIDTH), snap(p.y, height)];
  };

  const onPointerDown = (e: PointerEvent<SVGSVGElement>) => {
    if (e.button !== 0 || gesture.current) return;
    e.preventDefault();
    const at = pointAt(e);
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      // 合成されたポインター入力（自動操作）ではキャプチャできない。なくても動く。
    }
    if (tool === 'brush') {
      editor.beginStroke(at);
      gesture.current = {pointerId: e.pointerId, kind: 'stroke'};
      return;
    }
    const tagged = Number((e.target as Element).closest('[data-id]')?.getAttribute('data-id'));
    const note = doc.notes.find(n => n.id === tagged) ?? editor.addNote(at);
    editor.select(note.id);
    gesture.current = {pointerId: e.pointerId, kind: 'tag', id: note.id, origin: at, moving: false};
  };

  const onPointerMove = (e: PointerEvent<SVGSVGElement>) => {
    const current = gesture.current;
    if (!current || current.pointerId !== e.pointerId) return;
    const at = pointAt(e);
    if (current.kind === 'stroke') return editor.extendStroke(at);
    if (!current.moving) {
      // 少し動いただけではドラッグ扱いにしない（クリックでタグを選んだだけ）。
      if (Math.hypot(at[0] - current.origin[0], at[1] - current.origin[1]) < 2) return;
      editor.remember();
      current.moving = true;
    }
    editor.moveNote(current.id, at);
  };

  const onPointerEnd = (e: PointerEvent<SVGSVGElement>) => {
    const current = gesture.current;
    if (!current || current.pointerId !== e.pointerId) return;
    gesture.current = null;
    if (current.kind === 'tag' && e.type === 'pointerup') editor.requestFocus(current.id);
  };

  return (
    <svg
      ref={svg} className="board" data-zoom={zoom} data-tool={tool} viewBox={`0 0 ${BOARD_WIDTH} ${height}`}
      role="img" aria-label="修正箇所を指定する画像"
      onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerEnd} onPointerCancel={onPointerEnd}>
      <BoardArtwork doc={doc} height={height} selected={selected} />
    </svg>
  );
}
