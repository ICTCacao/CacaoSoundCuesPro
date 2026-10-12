#!/bin/zsh
# Pro 版のマニュアル（Marp、日本語版と英語版）を PDF にして manual/ と dist/ に置く。要: brew install marp-cli、Google Chrome
# 画面写真（img/）は、開発版を起動引数でサンプルのキューシートを開いて撮る（README の「マニュアル」）
set -euo pipefail
cd "$(dirname "$0")"
for src in "CacaoSoundCuesPro-マニュアル.md" "CacaoSoundCuesPro-Manual-en.md"; do
  pdf="${src%.md}.pdf"
  marp --pdf --allow-local-files "$src" -o "$pdf" < /dev/null
  mkdir -p ../dist
  cp "$pdf" "../dist/$pdf"
  echo "作成: manual/$pdf → dist/$pdf"
done
