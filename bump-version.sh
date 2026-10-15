#!/bin/zsh
# Pro 版のバージョンを上げる。0.0.1 ずつ（例: 5.1.2 → 5.1.3）。Simple 版（../CacaoSoundCues）とは別の番号。
# dist に置くビルドの前に毎回実行する。引数で指定すればその値にする（例: ./bump-version.sh 5.2.0）。
set -euo pipefail
cd "$(dirname "$0")"
cur=$(sed -n 's/.*CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml | head -1)
if [[ $# -ge 1 ]]; then
  new=$1
else
  parts=(${(s:.:)cur})
  new="${parts[1]}.${parts[2]}.$(( parts[3] + 1 ))"
fi
sed -i '' "s/\"$cur\"/\"$new\"/g" project.yml
[[ -f Pro/Resources/Info.plist ]] && sed -i '' "s|<string>$cur</string>|<string>$new</string>|g" Pro/Resources/Info.plist
month="$(date +%Y) 年 $(( $(date +%m) )) 月"
sed -i '' -E "s/バージョン β?[0-9.]+ ／ [0-9]+ 年 [0-9]+ 月/バージョン $new ／ $month/" manual/CacaoSoundCuesPro-マニュアル.md
month_en="$(LC_ALL=en_US.UTF-8 date +'%B %Y')"
sed -i '' -E "s/^Version β?[0-9.]+ \/ .*/Version $new \/ $month_en/" manual/CacaoSoundCuesPro-Manual-en.md
sed -i '' "s/CacaoSoundCuesPro-[0-9.]*\.dmg/CacaoSoundCuesPro-$new.dmg/g" manual/CacaoSoundCuesPro-マニュアル.md manual/CacaoSoundCuesPro-Manual-en.md
echo "$cur → $new（Pro）"
