import {Button} from '@astryxdesign/core/Button';
import {CheckboxInput} from '@astryxdesign/core/CheckboxInput';
import {Dialog, DialogHeader} from '@astryxdesign/core/Dialog';
import {HStack} from '@astryxdesign/core/HStack';
import {NumberInput} from '@astryxdesign/core/NumberInput';
import {Selector} from '@astryxdesign/core/Selector';
import {Spinner} from '@astryxdesign/core/Spinner';
import {Text} from '@astryxdesign/core/Text';
import {VStack} from '@astryxdesign/core/VStack';
import {useEffect, useState} from 'react';
import {exportImage, type ExportOptions} from './actions';
import {useEditor} from './editor';
import {renderPdfPage, type PdfDocument} from './media';
import {writtenNotes} from './model';

/** 選んだ内容を次回も使えるよう、この Mac（ブラウザー）に覚えておく。 */
export const remembered = {
  get<T extends string>(key: string, fallback: T): T {
    try {
      return (localStorage.getItem(`imagereview.${key}`) as T | null) ?? fallback;
    } catch {
      return fallback;
    }
  },
  set(key: string, value: string) {
    try {
      localStorage.setItem(`imagereview.${key}`, value);
    } catch {
      // 保存できない環境でも、その場の操作は続けられる。
    }
  },
};

export type PdfRequest = {doc: PdfDocument; name: string; resolve: (page: number | null) => void};

/** 複数ページの PDF から、読み込む 1 ページを選ぶ。 */
export function PdfPageDialog({request, onClose}: {request: PdfRequest; onClose: () => void}) {
  const [page, setPage] = useState(1);
  const [preview, setPreview] = useState<string | null>(null);
  const [isFailed, setFailed] = useState(false);

  useEffect(() => {
    let isCurrent = true;
    setPreview(null);
    setFailed(false);
    renderPdfPage(request.doc, page, 720).then(
      canvas => isCurrent && setPreview(canvas.toDataURL('image/png')),
      () => isCurrent && setFailed(true),
    );
    return () => {
      isCurrent = false;
    };
  }, [request, page]);

  const finish = (result: number | null) => {
    request.resolve(result);
    onClose();
  };

  return (
    <Dialog isOpen purpose="form" width={540} onOpenChange={isOpen => !isOpen && finish(null)}>
      <DialogHeader title="読み込むページを選択" subtitle={request.name} onOpenChange={isOpen => !isOpen && finish(null)} />
      <VStack gap={4}>
        <figure className="pdf-preview">
          {isFailed ? <Text color="secondary">このページを表示できません。</Text> : preview ? <img src={preview} alt="" /> : <Spinner />}
        </figure>
        <HStack gap={3} vAlign="end" hAlign="between">
          <NumberInput
            label={`ページ（全 ${request.doc.numPages} ページ）`} width={180} min={1} max={request.doc.numPages}
            isIntegerOnly hasNumberSteppers value={page}
            onChange={value => typeof value === 'number' && value >= 1 && value <= request.doc.numPages && setPage(value)}
          />
          <HStack gap={2}>
            <Button label="キャンセル" variant="ghost" onClick={() => finish(null)} />
            <Button label="このページを開く" variant="primary" isDisabled={!preview} onClick={() => finish(page)} />
          </HStack>
        </HStack>
      </VStack>
    </Dialog>
  );
}

/** 注釈を焼き込んだ画像の書き出し設定。 */
export function ExportDialog({onClose}: {onClose: () => void}) {
  const {doc} = useEditor();
  const hasNotes = writtenNotes(doc).length > 0;
  const [size, setSize] = useState(() => remembered.get<ExportOptions['size']>('exportSize', 'fit'));
  const [type, setType] = useState(() => remembered.get<ExportOptions['type']>('exportType', 'image/jpeg'));
  const [withNotes, setWithNotes] = useState(() => remembered.get('exportNotes', '1') === '1');

  const run = () => {
    remembered.set('exportSize', size);
    remembered.set('exportType', type);
    remembered.set('exportNotes', withNotes ? '1' : '0');
    onClose();
    void exportImage({size, type, withNotes: withNotes && hasNotes});
  };

  return (
    <Dialog isOpen purpose="form" width={440} onOpenChange={isOpen => !isOpen && onClose()}>
      <DialogHeader title="画像を書き出す" subtitle="番号タグと手書きを焼き込んだ画像を保存します" onOpenChange={isOpen => !isOpen && onClose()} />
      <VStack gap={4}>
        <Selector
          label="サイズ" width="100%" value={size} onChange={value => setSize(value as ExportOptions['size'])}
          options={[
            {value: 'fit', label: '長辺 2000px に縮小', description: '軽くなります。AI に渡すならこれで十分です'},
            {value: 'full', label: '原寸のまま', description: '細かい文字まで残したいとき'},
          ]}
        />
        <Selector
          label="形式" width="100%" value={type} onChange={value => setType(value as ExportOptions['type'])}
          options={[
            {value: 'image/jpeg', label: 'JPEG', description: '軽い'},
            {value: 'image/png', label: 'PNG', description: '劣化なし'},
          ]}
        />
        <CheckboxInput
          label="指示文を画像の下に入れる" value={withNotes && hasNotes} onChange={setWithNotes}
          isDisabled={!hasNotes} disabledMessage="指示文がまだありません"
        />
        <HStack gap={2} hAlign="end">
          <Button label="キャンセル" variant="ghost" onClick={onClose} />
          <Button label="書き出す" variant="primary" onClick={run} />
        </HStack>
      </VStack>
    </Dialog>
  );
}
