import {
  ArrowDownTrayIcon, ArrowUturnLeftIcon, BookmarkSquareIcon, DocumentTextIcon, FolderOpenIcon, HashtagIcon,
  PaintBrushIcon, PaperAirplaneIcon, PhotoIcon, PrinterIcon,
} from '@heroicons/react/24/outline';
import {Button} from '@astryxdesign/core/Button';
import {Divider} from '@astryxdesign/core/Divider';
import {DropdownMenu} from '@astryxdesign/core/DropdownMenu';
import {EmptyState} from '@astryxdesign/core/EmptyState';
import {HStack} from '@astryxdesign/core/HStack';
import {Icon} from '@astryxdesign/core/Icon';
import {IconButton} from '@astryxdesign/core/IconButton';
import {Layout, LayoutContent, LayoutFooter, LayoutHeader, LayoutPanel} from '@astryxdesign/core/Layout';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {Selector} from '@astryxdesign/core/Selector';
import {Heading, Text} from '@astryxdesign/core/Text';
import {useToast} from '@astryxdesign/core/Toast';
import {Toolbar} from '@astryxdesign/core/Toolbar';
import {VStack} from '@astryxdesign/core/VStack';
import {useEffect, useState} from 'react';
import {chooseFiles, destinations, MEDIA_TYPES, openFile, saveNote, sendToAI, setUIReady, ui} from './actions';
import {Board, BoardArtwork} from './Board';
import {ExportDialog, PdfPageDialog, remembered, type PdfRequest} from './dialogs';
import {editor, useEditor, type Tool, type Zoom} from './editor';
import {BOARD_WIDTH, type StrokeWidth} from './model';
import {NotesPanel} from './NotesPanel';

const COLORS = [
  {value: '#c93235', label: '赤'},
  {value: '#e07b00', label: 'オレンジ'},
  {value: '#2f6fde', label: '青'},
  {value: '#1d8a4e', label: '緑'},
  {value: '#1c2a27', label: '黒'},
];
const ZOOMS: {value: Zoom; label: string}[] = [
  {value: 'fit', label: '全体を表示'},
  {value: '1', label: '幅に合わせる'},
  {value: '1.5', label: '150%'},
  {value: '2', label: '200%'},
  {value: '3', label: '300%'},
];

/** アプリアイコンと同じ図柄（画像のカードに赤い番号タグ）を、小さく簡略にしたロゴ。 */
function Mark() {
  return (
    <svg className="mark" viewBox="0 0 24 24" aria-hidden>
      <rect className="mark-plate" width="24" height="24" rx="6" />
      <rect className="mark-card" x="4" y="8" width="13.5" height="11" rx="2" />
      <circle className="mark-tag" cx="17.5" cy="7.5" r="4.4" />
    </svg>
  );
}

/** いちばん上の段：何を開いているかと、ファイルに対する操作。 */
function FileBar({onExport}: {onExport: () => void}) {
  const {doc, dirty} = useEditor();
  const hasDocument = Boolean(doc.image);
  return (
    <Toolbar
      label="ファイル"
      startContent={
        <HStack gap={3} vAlign="center">
          <Mark />
          <Heading level={4} accessibilityLevel={1}>ImageReview</Heading>
          {hasDocument && (
            <Text color="secondary" maxLines={1} hasTruncateTooltip>
              {doc.name}
              {dirty ? '（未保存）' : ''}
            </Text>
          )}
        </HStack>
      }
      endContent={
        <HStack gap={2} vAlign="center">
          <DropdownMenu
            button={{label: '開く', variant: 'secondary', icon: <Icon icon={FolderOpenIcon} />}}
            items={[
              {label: '画像・PDF…', icon: PhotoIcon, onClick: () => chooseFiles(MEDIA_TYPES, false, ([file]) => file && void openFile(file, false))},
              {label: '保存したノート…', icon: DocumentTextIcon, onClick: () => chooseFiles('.json', false, ([file]) => file && void openFile(file, true))},
            ]}
          />
          <Button label="ノート保存" icon={<Icon icon={BookmarkSquareIcon} />} isDisabled={!hasDocument} onClick={saveNote} />
          <DropdownMenu
            button={{label: '書き出す', icon: <Icon icon={ArrowDownTrayIcon} />, isDisabled: !hasDocument}}
            alignment="end"
            items={[
              {label: '画像として書き出す…', icon: PhotoIcon, onClick: onExport},
              {label: '印刷 / PDF保存', icon: PrinterIcon, onClick: () => window.print()},
            ]}
          />
        </HStack>
      }
    />
  );
}

/** 2 段目：描き込みの道具と、表示の調整。 */
function ToolBar() {
  const {doc, tool, color, width, zoom, canUndo} = useEditor();
  const hasDocument = Boolean(doc.image);
  return (
    <Toolbar
      label="描き込み"
      size="sm"
      startContent={
        <HStack gap={3} vAlign="center">
          <SegmentedControl label="ツール" value={tool} onChange={value => editor.setTool(value as Tool)}>
            <SegmentedControlItem value="tag" label="番号タグ" icon={<Icon icon={HashtagIcon} />} />
            <SegmentedControlItem value="brush" label="ブラシ" icon={<Icon icon={PaintBrushIcon} />} />
          </SegmentedControl>
          <Divider orientation="vertical" />
          <SegmentedControl label="色" value={color} onChange={value => editor.setColor(value)}>
            {COLORS.map(c => (
              <SegmentedControlItem
                key={c.value} value={c.value} label={c.label} isLabelHidden
                icon={<span className="swatch" style={{background: c.value}} />}
              />
            ))}
          </SegmentedControl>
          <SegmentedControl
            label="線の太さ" value={String(width)} onChange={value => editor.setWidth(Number(value) as StrokeWidth)}
            isDisabled={tool !== 'brush'} disabledMessage="太さはブラシのときに選べます">
            <SegmentedControlItem value="2" label="細" />
            <SegmentedControlItem value="4" label="中" />
            <SegmentedControlItem value="8" label="太" />
          </SegmentedControl>
        </HStack>
      }
      endContent={
        <HStack gap={2} vAlign="center">
          <IconButton
            label="元に戻す" tooltip="元に戻す（⌘Z）" variant="ghost" icon={<Icon icon={ArrowUturnLeftIcon} />}
            isDisabled={!canUndo} onClick={() => editor.undo()}
          />
          <Selector
            label="表示" isLabelHidden variant="ghost" value={zoom} options={ZOOMS} isDisabled={!hasDocument}
            onChange={value => editor.setZoom(value as Zoom)}
          />
        </HStack>
      }
    />
  );
}

/** いちばん下の段：送り先と送り方を選んでおき、ボタン 1 回で AI に渡す。 */
function SendBar() {
  const {doc} = useEditor();
  const ids = Object.keys(destinations);
  const [target, setTarget] = useState(() => {
    const saved = remembered.get('sendTarget', '');
    return destinations[saved] ? saved : ids[0];
  });
  const [mode, setMode] = useState(() => remembered.get<'new' | 'recent'>('sendMode', 'new'));
  return (
    <HStack gap={3} vAlign="center" hAlign="between" wrap="wrap">
      <Text color="secondary" size="sm">
        {mode === 'new' ? '新しいチャットを開いて、指示文と画像を渡します。' : 'いま開いているチャットに、指示文と画像を渡します。'}
      </Text>
      <HStack gap={3} vAlign="center">
        <SegmentedControl label="送り先" value={target} onChange={value => { setTarget(value); remembered.set('sendTarget', value); }}>
          {ids.map(id => (
            <SegmentedControlItem key={id} value={id} label={destinations[id].name} />
          ))}
        </SegmentedControl>
        <SegmentedControl label="送り方" value={mode} onChange={value => { setMode(value as 'new' | 'recent'); remembered.set('sendMode', value); }}>
          <SegmentedControlItem value="new" label="新規チャット" />
          <SegmentedControlItem value="recent" label="直近のチャット" />
        </SegmentedControl>
        <Button
          label="AIに送る" variant="primary" icon={<Icon icon={PaperAirplaneIcon} />} isDisabled={!doc.image}
          clickAction={() => sendToAI(target, mode === 'new')}
        />
      </HStack>
    </HStack>
  );
}

/** 印刷（PDF 保存）用の 1 枚。画面では隠してあり、印刷のときだけ画面全体と入れ替わる。 */
function PrintSheet() {
  const {doc, height} = useEditor();
  if (!doc.image) return null;
  return (
    <section className="print-sheet" aria-hidden>
      <h1>修正指示　{doc.name}</h1>
      <svg viewBox={`0 0 ${BOARD_WIDTH} ${height}`}>
        <BoardArtwork doc={doc} height={height} />
      </svg>
      <h2>修正指示</h2>
      {doc.notes.map(note => (
        <div key={note.id} className="print-note">
          <p>
            <b>＃{note.id}</b>
            {note.text}
          </p>
          {note.references?.length ? (
            <div className="print-references">
              {note.references.map((reference, i) => (
                <figure key={i}>
                  <img src={reference.src} alt="" />
                  <figcaption>{reference.name}</figcaption>
                </figure>
              ))}
            </div>
          ) : null}
        </div>
      ))}
    </section>
  );
}

export function App() {
  const {doc, dirty, tool, zoom} = useEditor();
  const showToast = useToast();
  const [pdfRequest, setPdfRequest] = useState<PdfRequest | null>(null);
  const [isExportOpen, setExportOpen] = useState(false);
  const hasDocument = Boolean(doc.image);

  // 画面の外（ファイルを開く処理や Mac アプリ）から、通知とページ選択を使えるようにする。
  useEffect(() => {
    ui.notify = (message, isError) => showToast({body: message, type: isError ? 'error' : 'info'});
    ui.pickPage = (pdf, name) => new Promise(resolve => setPdfRequest({doc: pdf, name, resolve}));
    setUIReady();
  }, [showToast]);

  useEffect(() => {
    document.title = doc.name ? `${doc.name} - ImageReview` : 'ImageReview';
  }, [doc.name]);

  useEffect(() => {
    const onDragOver = (e: DragEvent) => e.preventDefault();
    const onDrop = (e: DragEvent) => {
      e.preventDefault();
      const file = e.dataTransfer?.files[0];
      if (file) void openFile(file);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      // 入力欄の中では、文字の取り消しを優先する。
      const isTyping = e.target instanceof HTMLElement && e.target.matches('input, textarea, [contenteditable]');
      if ((e.metaKey || e.ctrlKey) && !e.shiftKey && e.key.toLowerCase() === 'z' && !isTyping) {
        e.preventDefault();
        editor.undo();
      }
    };
    document.addEventListener('dragover', onDragOver);
    document.addEventListener('drop', onDrop);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('dragover', onDragOver);
      document.removeEventListener('drop', onDrop);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, []);

  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);

  return (
    <>
      <main className="screen">
        <Layout
          height="fill"
          header={
            <LayoutHeader hasDivider padding={0}>
              <VStack gap={0}>
                <FileBar onExport={() => setExportOpen(true)} />
                <Divider />
                <ToolBar />
              </VStack>
            </LayoutHeader>
          }
          content={
            <LayoutContent padding={4} isScrollable={false}>
              {hasDocument ? (
                <VStack gap={2} height="100%">
                  <figure className="board-viewport" data-zoom={zoom}>
                    <Board />
                  </figure>
                  <Text color="secondary" size="sm">
                    {tool === 'tag'
                      ? 'クリックで番号タグを追加。番号をドラッグすると位置を調整できます。'
                      : 'ドラッグして描き込みます。線を取り消すには「元に戻す」を押してください。'}
                  </Text>
                </VStack>
              ) : (
                <figure className="board-viewport" data-empty>
                  <EmptyState
                    icon={<Icon icon={PhotoIcon} />}
                    title="直したい画像・PDFをここにドロップ"
                    description="PNG / JPEG / WebP / GIF / BMP / PDF を開けます。ショートカットで撮ったスクリーンショットも、ここに開きます。"
                    actions={
                      <Button
                        label="画像・PDFを開く" variant="primary" icon={<Icon icon={FolderOpenIcon} />}
                        onClick={() => chooseFiles(MEDIA_TYPES, false, ([file]) => file && void openFile(file, false))}
                      />
                    }
                  />
                </figure>
              )}
            </LayoutContent>
          }
          end={
            <LayoutPanel hasDivider width={340} padding={4} label="修正指示" role="complementary">
              <NotesPanel />
            </LayoutPanel>
          }
          footer={
            Object.keys(destinations).length > 0 && (
              <LayoutFooter hasDivider padding={3} label="AIに送る">
                <SendBar />
              </LayoutFooter>
            )
          }
        />
      </main>
      <PrintSheet />
      {pdfRequest && <PdfPageDialog request={pdfRequest} onClose={() => setPdfRequest(null)} />}
      {isExportOpen && <ExportDialog onClose={() => setExportOpen(false)} />}
    </>
  );
}
