#!/bin/zsh
# ImageReview.app をビルドする。Xcode は不要（Command Line Tools の swiftc だけで動く）。
#   ./macapp/build.sh            → /Applications にインストール
#   ./macapp/build.sh ~/Desktop  → 指定したフォルダにインストール
#   ./macapp/build.sh --dmg      → 配布用の dist/ImageReview-<バージョン>.dmg を作る（インストールはしない）
#
# 署名について: 簡易署名（ad-hoc）だと、ビルドし直すたびに macOS が別のアプリとみなし、
# 「画面収録」「アクセシビリティ」の許可が外れる。そこでインストール時は、キーチェーンに
# コード署名用の証明書（"ImageReview Local" という名前のもの、なければ Apple Development）があれば
# それで署名する。証明書が同じなら、許可はビルドをまたいで残る。CODESIGN_IDENTITY で明示もできる。
# 配布用の dmg は、作った人の証明書の情報が入らないよう、明示しない限り簡易署名にする。
set -euo pipefail

here=${0:A:h}
root=${here:h}
dest=${1:-/Applications}
name='ImageReview'
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
app="$stage/$name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/web" "$app/Contents/Resources/ja.lproj"

# Apple シリコンと Intel の両方で動くユニバーサルバイナリにする。
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" ${=SWIFTFLAGS:-} \
    "$here"/Sources/*.swift -o "$stage/ImageReview-$arch"
done
lipo -create "$stage"/ImageReview-{arm64,x86_64} -output "$app/Contents/MacOS/ImageReview"

cp "$here/Info.plist" "$app/Contents/Info.plist"
[[ -n ${BUNDLE_ID:-} ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$app/Contents/Info.plist"
# ja.lproj があると、保存・印刷などシステム標準のダイアログも日本語になる。
print 'CFBundleDisplayName = "ImageReview";' > "$app/Contents/Resources/ja.lproj/InfoPlist.strings"

# 編集画面は Web 版と同じファイルをそのまま使う。
cp "$root/index.html" "$root/pdf-import.js" "$root/export.js" "$app/Contents/Resources/web/"
cp -R "$root/vendor" "$app/Contents/Resources/web/vendor"

# アイコン
swift "$here/make-icon.swift" "$stage/icon.png"
iconset="$stage/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$stage/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$stage/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

identity=${CODESIGN_IDENTITY:-}
if [[ -z $identity && $dest != --dmg ]]; then
  # 一覧の各行は「番号) ハッシュ "名前"」。名前で探し、署名にはハッシュを使う。
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  identity=$(print -r -- "$identities" | awk '/"ImageReview Local"/ {print $2; exit}')
  [[ -n $identity ]] || identity=$(print -r -- "$identities" | awk '/"Apple Development:/ {print $2; exit}')
fi
codesign --force --sign "${identity:--}" "$app"

if [[ $dest == --dmg ]]; then
  # 開くと「アプリを Applications にドラッグ」できるディスクイメージ。
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
  volume="$stage/volume"
  mkdir -p "$volume" "$root/dist"
  ditto "$app" "$volume/$name.app"
  ln -s /Applications "$volume/Applications"
  dmg="$root/dist/$name-$version.dmg"
  hdiutil create -quiet -ov -volname "$name" -srcfolder "$volume" -format UDZO "$dmg"
  print "作成しました: $dmg"
  exit
fi

# 起動中なら終了してから入れ替え、Finder の「このアプリケーションで開く」に登録する。
# 未保存の作業があるとアプリは確認を出して終了を待つ。その間に上書きすると作業が失われるので、中止する。
target="$dest/$name.app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
# 実行ファイルのパスが一致するものだけを見る。grep -q は使わない（先に終了して ps が SIGPIPE になり、
# pipefail のもとで「見つからない」と同じ失敗扱いになってしまう）。
running() { [[ -n $(ps -axo comm= | grep -xF "$target/Contents/MacOS/ImageReview") ]] }
if running; then
  osascript -e 'with timeout of 10 seconds' -e "tell application id \"$bundle_id\" to quit" -e 'end timeout' >/dev/null 2>&1 || true
  for _ in {1..20}; do running || break; sleep 0.5; done
  if running; then
    print -u2 "ImageReview が終了していません。未保存の作業を保存するか、終了の確認に答えてから、もう一度実行してください。"
    exit 1
  fi
fi
mkdir -p "$dest"
rm -rf "$target"
ditto "$app" "$target"
"$lsregister" -f "$target"
print "インストールしました: $target"
