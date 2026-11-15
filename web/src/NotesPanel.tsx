import {PlusIcon, TrashIcon} from '@heroicons/react/24/outline';
import {Badge} from '@astryxdesign/core/Badge';
import {Button} from '@astryxdesign/core/Button';
import {Card} from '@astryxdesign/core/Card';
import {EmptyState} from '@astryxdesign/core/EmptyState';
import {HStack} from '@astryxdesign/core/HStack';
import {Icon} from '@astryxdesign/core/Icon';
import {IconButton} from '@astryxdesign/core/IconButton';
import {Heading, Text} from '@astryxdesign/core/Text';
import {TextArea} from '@astryxdesign/core/TextArea';
import {Thumbnail} from '@astryxdesign/core/Thumbnail';
import {VStack} from '@astryxdesign/core/VStack';
import {useEffect, useRef, type DragEvent} from 'react';
import {chooseFiles, MEDIA_TYPES, ui} from './actions';
import {editor, useEditor} from './editor';
import {importMedia} from './media';
import {IMAGE_DATA, type Note, type Reference} from './model';

/** 指示に添える参考画像を読み込む（画像か PDF の 1 ページ）。 */
async function attach(note: Note, files: File[]) {
  if (!files.length) return;
  try {
    const batch: Reference[] = [];
    for (const file of files) {
      const media = await importMedia(file, ui.pickPage);
      if (!media) continue;
      if (!IMAGE_DATA.test(media.src)) throw new Error('unsupported');
      const image = new Image();
      image.src = media.src;
      await image.decode();
      batch.push(media);
    }
    editor.addReferences(note.id, batch);
  } catch {
    ui.notify('参考画像を読み込めませんでした。画像またはパスワード保護のないPDFを選んでください。', true);
  }
}

function NoteCard({note, isSelected, register}: {note: Note; isSelected: boolean; register: (el: HTMLTextAreaElement | null) => void}) {
  // 入力の途中経過を 1 文字ずつ履歴に積まないよう、フォーカスしてから最初の変更でだけ覚える。
  const remembered = useRef(false);
  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    void attach(note, Array.from(e.dataTransfer.files));
  };
  return (
    <article className="note" data-selected={isSelected} onDragOver={e => { e.preventDefault(); e.stopPropagation(); }} onDrop={onDrop}>
      <Card padding={3}>
        <VStack gap={2}>
          <HStack gap={2} vAlign="center" hAlign="between">
            <HStack gap={2} vAlign="center">
              <span className="note-tag" style={{background: note.color}} aria-hidden>{note.id}</span>
              <Text type="label" color="secondary">指示 {note.id}</Text>
            </HStack>
            <IconButton
              label={`指示 ${note.id} を削除`} tooltip="削除" variant="ghost" size="sm"
              icon={<Icon icon={TrashIcon} size="sm" />} onClick={() => editor.deleteNote(note.id)}
            />
          </HStack>
          <TextArea
            ref={register} label={`修正指示 ${note.id}`} isLabelHidden placeholder="修正内容を入力" rows={3} width="100%"
            value={note.text}
            onFocus={() => { remembered.current = false; editor.select(note.id); }}
            onChange={text => {
              if (!remembered.current) {
                editor.remember();
                remembered.current = true;
              }
              editor.setNoteText(note.id, text);
            }}
          />
          {note.references?.length ? (
            <HStack gap={2} wrap="wrap">
              {note.references.map((reference, i) => (
                <Thumbnail
                  key={i} src={reference.src} alt={`指示 ${note.id} の参考画像 ${reference.name}`} label={reference.name}
                  showRemoveOn="hover" onRemove={() => editor.removeReference(note.id, i)}
                />
              ))}
            </HStack>
          ) : null}
          <HStack>
            <Button
              label="参考画像を追加" variant="ghost" size="sm" icon={<Icon icon={PlusIcon} size="sm" />}
              onClick={() => chooseFiles(MEDIA_TYPES, true, files => void attach(note, files))}
            />
          </HStack>
        </VStack>
      </Card>
    </article>
  );
}

/** 画面右の「修正指示」一覧。番号タグ 1 つにつき 1 枚。 */
export function NotesPanel() {
  const {doc, selected, focus} = useEditor();
  const fields = useRef(new Map<number, HTMLTextAreaElement>());

  useEffect(() => {
    if (focus) fields.current.get(focus.id)?.focus();
  }, [focus]);

  return (
    <VStack gap={3}>
      <HStack gap={2} vAlign="center">
        <Heading level={5} accessibilityLevel={2}>修正指示</Heading>
        {doc.notes.length > 0 && <Badge label={doc.notes.length} />}
      </HStack>
      {doc.notes.length === 0 ? (
        <EmptyState
          isCompact title="指示はまだありません"
          description={doc.image ? '画像をクリックして、指示を書く場所を指定します。' : '画像を開くと、ここに指示を書けます。'}
        />
      ) : (
        doc.notes.map(note => (
          <NoteCard
            key={note.id} note={note} isSelected={note.id === selected}
            register={el => { if (el) fields.current.set(note.id, el); else fields.current.delete(note.id); }}
          />
        ))
      )}
    </VStack>
  );
}
