import react from '@vitejs/plugin-react';
import {defineConfig} from 'vite';

// 出来上がった dist/ は、Mac アプリの中で irn://app/ から配信される。
// どこに置かれても動くよう、参照はすべて相対パスにする。
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    target: 'safari16',
    chunkSizeWarningLimit: 1500,
  },
});
