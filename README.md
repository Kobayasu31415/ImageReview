# ImageReview

画像や PDF に番号タグと手書きで修正指示を書き込み、印刷・PDF 保存できる Mac / Windows アプリです。スクリーンショットを撮って、そのまま書き込めます。

https://github.com/user-attachments/assets/b557cfc5-a264-4f50-9ac3-d81c82523f6a

紹介動画（45 秒・音声なし）。元のファイルは [demo/ImageReview-demo.mp4](demo/ImageReview-demo.mp4) にあります。

## インストール

### Windows 版（このブランチからビルド）

1. Windows で Node.js 22.13 以降と .NET 10 SDK を用意し、`winapp\build.cmd` を実行します。
2. `dist\ImageReview-Windows\ImageReview.exe` を起動します。別の PC に移すときはフォルダーごとコピーし、.NET 10 Desktop Runtime と Microsoft Edge WebView2 Runtime を用意してください。
3. 通知領域の ImageReview アイコンを右クリックし、「エクスプローラーの『プログラムから開く』に登録」を一度選びます。その後は画像・PDF・保存したノート（`.review.json`）を右クリックし、「プログラムから開く」→「ImageReview」で編集できます。アプリを移動した場合は再登録してください。

| 撮影ショートカット | 操作 |
| --- | --- |
| `Ctrl+Shift+7` | ポインターのあるモニター全体を撮影 |
| `Ctrl+Shift+8` | ドラッグした範囲を撮影 |
| `Ctrl+Shift+9` | ウィンドウをクリックして、画面に見えている範囲を撮影 |

範囲・ウィンドウ選択は `Esc` で取り消せます。撮った画像は新しい編集ウィンドウに開きます。編集ウィンドウを閉じた後も撮影できます。終了するときは通知領域の「ImageReview を終了」を選んでください。ショートカットが他のアプリと重なる場合は、同じメニューからも撮影できます。

**AIに送る**　画面下で ChatGPT、Claude（チャット）、または Claude Code と、新規・直近のチャットを選べます。番号タグ、手書き、修正指示をまとめた画像をクリップボードにコピーし、対応するデスクトップアプリの入力欄に貼り付けます。内容を確認して、チャット側で送信してください。

デスクトップ連携が見つからない場合、新規チャットはブラウザーで開きます。直近のチャットを使う場合は目的の会話を表示し、`Ctrl+V` で貼り付けてください。Claude Code は Claude デスクトップの連携が使えるときに表示されます。

### Mac 版

1. [Releases](https://github.com/Kobayasu31415/ImageReview/releases/latest) から `ImageReview-1.1.dmg` をダウンロードして開く
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

## Mac 版の使い方

- **Finder から開く**: 画像（PNG / JPEG / WebP / GIF / BMP）や PDF を右クリック →「このアプリケーションで開く」→ ImageReview
- **スクリーンショット**: `⌘⇧7` 画面全体 / `⌘⇧8` 範囲を選択 / `⌘⇧9` ウインドウを選択。撮った画像がそのまま開きます
- **書き出す**: 右上の「書き出す」から、番号タグと手書きを焼き込んだ画像（JPEG / PNG）の保存と、印刷 / PDF 保存ができます。画像は長辺 2000px に縮めて軽くでき、指示文を画像の下に入れることもできます
- **AIに送る**: 画面下のバーで送り先（Claude のチャット / Claude Code / ChatGPT）と送り方（新規チャット / 直近のチャット）を選んでおくと、ボタン 1 回で相手のアプリを開いて指示文と画像を渡します。貼り付けまで自動で行うには、初回に求められる「アクセシビリティ」の許可が必要です（許可しない場合は、相手の画面で `⌘V` を押して貼り付けます）
- **常駐**: ウインドウを閉じても、`⌘Q` や Dock の「終了」を選んでも、メニューバーで動き続けるので、ショートカットはいつでも使えます。待機中は 20MB ほどしか使いません（ウインドウを閉じて 20 秒たつと、編集画面を読み込んでいない軽い状態に切り替わります）。完全に終了するには、メニューバーのアイコンから「ImageReview を完全に終了」を選びます。同じメニューで、ショートカットの変更と個別オフ、ログイン時の起動も設定できます

## Mac 版をソースからビルド

必要なものは、Command Line Tools（`xcode-select --install`）と Node.js です。Xcode は要りません。

```bash
./macapp/build.sh        # ビルドして /Applications にインストール
./macapp/build.sh --dmg  # 配布用の dmg を dist/ に作成
```

キーチェーンにコード署名用の証明書（Apple Development など）があれば、インストール時にそれで署名します。簡易署名のままだと、ビルドし直すたびに「画面収録」と「アクセシビリティ」の許可が外れます。配布用の dmg は簡易署名のままです。

### 構成

- `web/` — 編集画面。React と [Astryx](https://github.com/meta/astryx) で作っていて、ビルドしたものをアプリに同梱します。画面だけを動かすなら `npm --prefix web install` のあと `npm --prefix web run dev`
- `macapp/` — Mac アプリ本体（Swift）。ウインドウ、Finder 連携、スクリーンショット、AI への受け渡しを担当します
- `winapp/` — Windows アプリ本体（C# / WinForms / WebView2）。エクスプローラー連携と通知領域からの撮影を担当します
- `demo/` — 紹介動画と、その台本・撮影ツール
