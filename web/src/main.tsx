import '@astryxdesign/core/reset.css';
import '@astryxdesign/core/astryx.css';
import './app.css';

import {Theme} from '@astryxdesign/core/theme';
import {ToastViewport} from '@astryxdesign/core/Toast';
import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import {openFile, ui, uiReady} from './actions';
import {App} from './App';
import {defaultThemeSlug, themes} from './astryx-themes';
import {editor} from './editor';

// Mac アプリ（macapp/Sources/ReviewWindow.swift）が呼ぶ窓口。名前と意味を変えるときは、あちらも直す。
const api = {
  /** Finder やスクリーンショットから渡されたファイルを開く。 */
  open: async (file: File, isProject: boolean) => {
    await uiReady;
    await openFile(file, isProject);
  },
  /** まだ何も開いておらず、新しいファイルを受け取れる状態か。 */
  isEmpty: () => !editor.getState().doc.image && !editor.getState().dirty,
  isDirty: () => editor.getState().dirty,
  hasDocument: () => Boolean(editor.getState().doc.image),
  notify: (message: string) => ui.notify(message, true),
  /** 動作確認用。 */
  editor,
};
declare global {
  interface Window {
    imageReview: typeof api;
  }
}
window.imageReview = api;

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Theme theme={themes[defaultThemeSlug]}>
      <ToastViewport position="bottomStart" inset={{bottom: 76}}>
        <App />
      </ToastViewport>
    </Theme>
  </StrictMode>,
);
