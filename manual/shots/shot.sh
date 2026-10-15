#!/bin/zsh
# 使い方: shot.sh <出力png> <ccsc> <幅> <高さ> [起動引数...]
# 開発版をライトの見た目で起動し、窓を左のディスプレイに置いて、窓だけを撮る（影なし）
set -u
S=$(cd "$(dirname "$0")" && pwd)
APP=/Users/ccostudio/CacaoApps/CacaoSoundCuesPro/build/dbg/Build/Products/Debug/CacaoSoundCuesPro.app/Contents/MacOS/CacaoSoundCuesPro
out=$1; ccsc=$2; w=$3; h=$4; shift 4
pkill -x CacaoSoundCuesPro 2>/dev/null; sleep 0.8
"$APP" -NSRequiresAquaSystemAppearance YES -debugOpen "$ccsc" -pro.sync.role off -lastShowPath "" \
  -keyboardScale 1 -showKeypad NO -showFunctionKeys NO "$@" >/dev/null 2>&1 &
sleep ${SHOT_WAIT:-7}
osascript -e "tell application \"System Events\" to tell process \"CacaoSoundCuesPro\"
  set position of window 1 to {${SHOT_POS:--1900}, 100}
  set size of window 1 to {$w, $h}
end tell" >/dev/null
sleep ${SHOT_SETTLE:-2}
line=$($S/winid CacaoSoundCuesPro | head -1)
id=${line%% *}
screencapture -x -o -l "$id" "$out"
echo "$out <- window $line"
