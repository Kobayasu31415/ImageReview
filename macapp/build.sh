#!/bin/zsh
# ImageReview.app をビルドする。Xcode は不要（Command Line Tools の swiftc だけで動く）。
#   ./macapp/build.sh            → /Applications にインストール
#   ./macapp/build.sh ~/Desktop  → 指定したフォルダにインストール
#   ./macapp/build.sh --dmg      → 配布用の dist/ImageReview-<バージョン>.dmg を作る（インストールはしない）
#
# 注意: 署名はこのMacで付ける簡易署名（Apple の公証なし）。ビルドし直すと macOS が別のアプリと
# みなし、「画面収録」の許可をもう一度求められることがある。
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
cp "$root/index.html" "$root/pdf-import.js" "$app/Contents/Resources/web/"
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

codesign --force --sign - "$app"

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
target="$dest/$name.app"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
osascript -e "if application id \"$bundle_id\" is running then tell application id \"$bundle_id\" to quit" 2>/dev/null || true
mkdir -p "$dest"
rm -rf "$target"
ditto "$app" "$target"
"$lsregister" -f "$target"
print "インストールしました: $target"
