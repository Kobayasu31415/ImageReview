# ImageReview

画像や PDF に番号タグと手書きで修正指示を書き込み、印刷・PDF 保存できる Mac アプリです。スクリーンショットを撮って、そのまま書き込めます。

https://github.com/user-attachments/assets/2f0bb8c0-f416-473d-a114-579aed032907

紹介動画（40 秒・音声なし）。元のファイルは [demo/ImageReview-demo.mp4](demo/ImageReview-demo.mp4) にあります。

## インストール

1. [Releases](https://github.com/Kobayasu31415/ImageReview/releases/latest) から `ImageReview-1.0.dmg` をダウンロードして開く
2. `ImageReview` を `Applications` フォルダにドラッグする
3. 初回だけ起動を許可する（Apple の公証を受けていないため、そのままでは警告が出て開けません）
   1. `ImageReview` を開く。警告が出るので「完了」で閉じる
   2. システム設定 ›「プライバシーとセキュリティ」を開き、下のほうにある「このまま開く」を押す
4. 初めてスクリーンショットを撮るときに「画面収録」の許可を求められるので、システム設定でオンにしてからアプリを起動し直す

ターミナルを使うなら、手順 3 の代わりに次のコマンドでも許可できます。

```bash
xattr -dr com.apple.quarantine /Applications/ImageReview.app
```

対応は macOS 13 以降です。動作確認は Apple シリコンの macOS 27 でのみ行っていて、Intel Mac は未確認です。

## 使い方

- **Finder から開く**: 画像（PNG / JPEG / WebP / GIF / BMP）や PDF を右クリック →「このアプリケーションで開く」→ ImageReview
- **スクリーンショット**: `⌘⇧7` 画面全体 / `⌘⇧8` 範囲を選択 / `⌘⇧9` ウインドウを選択。撮った画像がそのまま開きます
- **画像を書き出す**: 番号タグと手書きを焼き込んだ画像（JPEG / PNG）を保存します。長辺 2000px に縮めて軽くでき、指示文を画像の下に入れることもできます
- **AIに送る**: 画面下のバーで送り先（Claude のチャット / Claude Code / ChatGPT）と送り方（新規チャット / 直近のチャット）を選んでおくと、ボタン 1 回で相手のアプリを開いて指示文と画像を渡します。貼り付けまで自動で行うには、初回に求められる「アクセシビリティ」の許可が必要です（許可しない場合は、相手の画面で `⌘V` を押して貼り付けます）
- **常駐**: ウインドウを閉じてもメニューバーに残ります。メニューバーのアイコンから、ショートカットの変更と個別オフ、ログイン時の起動を設定できます

## ソースからビルド

Xcode は不要で、Command Line Tools（`xcode-select --install`）があればビルドできます。

```bash
./macapp/build.sh        # ビルドして /Applications にインストール
./macapp/build.sh --dmg  # 配布用の dmg を dist/ に作成
```

キーチェーンにコード署名用の証明書（Apple Development など）があれば、インストール時にそれで署名します。簡易署名のままだと、ビルドし直すたびに「画面収録」と「アクセシビリティ」の許可が外れます。配布用の dmg は簡易署名のままです。

編集画面だけなら、`index.html` をブラウザーで開いても使えます。
