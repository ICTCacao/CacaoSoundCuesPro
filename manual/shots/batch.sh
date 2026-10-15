#!/bin/zsh
# マニュアルの画面写真を全部撮る（日本語・英語）。要: 開発版（Debug）のビルド、左にもう 1 台のディスプレイ（1x）
# 1. 道具（winid・vmidi・crop）を swiftc でビルド 2. 撮影用のキューシートを shots/ に作る 3. 仮想 MIDI 機器を上げて撮る 4. 切り抜いて ../img へ
set -u
S=$(cd "$(dirname "$0")" && pwd)
for t in winid vmidi crop; do [[ -x $S/$t ]] || swiftc -O -o $S/$t $S/$t.swift; done
mkdir -p $S/shots && python3 $S/make_samples.py $S/shots
pkill -f "$S/vmidi" 2>/dev/null; $S/vmidi >/dev/null 2>&1 &
sleep 1
sh=$S/shot.sh; O=$S/shots
for L in ja en; do
  if [[ $L == ja ]]; then A=$O/ja.ccsc; B=$O/ja-h.ccsc; P=""; HX="5b7b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303031222c20226e616d65223a2022e383a1e382a4e383b3222c202270616972223a20307d2c207b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303032222c20226e616d65223a2022e383a2e3838be382bfe383bc222c2022646576696365554944223a20224170706c65555342417564696f456e67696e653a59616d61686120436f72706f726174696f6e3a59616d61686120414730364d4b323a383334313030303a312c32222c202270616972223a20307d2c207b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303033222c20226e616d65223a2022e58ab9e69e9ce99fb3e382b9e38394e383bce382abe383bc222c2022646576696365554944223a20224275696c74496e537065616b6572446576696365222c202270616972223a20307d5d"; else A=$O/en.ccsc; B=$O/en-v.ccsc; P="en-"; HX="5b7b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303031222c20226e616d65223a20224d61696e222c202270616972223a20307d2c207b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303032222c20226e616d65223a20224d6f6e69746f72222c2022646576696365554944223a20224170706c65555342417564696f456e67696e653a59616d61686120436f72706f726174696f6e3a59616d61686120414730364d4b323a383334313030303a312c32222c202270616972223a20307d2c207b226964223a202236363636363636362d303030302d343030302d383030302d303030303030303030303033222c20226e616d65223a202253465820537065616b6572222c2022646576696365554944223a20224275696c74496e537065616b6572446576696365222c202270616972223a20307d5d"; fi
  MAIN=(-language $L -pro.showScript '<true/>' -pro.scriptFraction 0.36 -showKeyboard NO -showInspector YES -showList YES -pro.midi.output 'Lighting Console' -pro.outputs "<$HX>")
  $sh $O/${P}01-main.png $A 1740 1000 -debugSelectKey 18 ${MAIN[@]}
  $sh $O/${P}02-other.png $B 1740 1000 -debugSelectKey 20 ${MAIN[@]}
  $sh $O/${P}03-folded.png $A 1740 1000 -language $L -debugSelectStep 0 -pro.showScript '<false/>' -showKeyboard YES -showInspector YES -showList YES -pro.midi.output 'Lighting Console' -pro.outputs "<$HX>"
  $sh $O/${P}04-full.png $A 1740 1000 -debugSelectKey 18 ${MAIN[@]} -debugOutputs YES
  $sh $O/${P}05-full.png $A 1740 1000 -debugSelectKey 18 ${MAIN[@]} -debugSync YES -pro.sync.role main
  $sh $O/${P}06-full.png $A 1740 1000 -debugSelectKey 18 ${MAIN[@]} -debugSync YES -pro.sync.role backup
  $sh $O/${P}06b-full.png $A 1740 1000 -debugSelectKey 18 ${MAIN[@]} -pro.sync.role backup
  $sh $O/${P}08-full.png $A 1740 1000 -debugSelectKey 12 ${MAIN[@]} -debugMIDI YES
  SHOT_POS=200 $sh $O/${P}09-full.png $A 1740 1000 -debugSelectKey 12 ${MAIN[@]}
done
pkill -x CacaoSoundCuesPro
pkill -f "$S/vmidi"

# 切り抜き（シートはそのまま窓の番号で撮れているので位置は固定。09 は主ディスプレイの 2x）。
# ずれたら *-full.png を見て、crop の x y w h を直す
C=$S/crop; cd $O
$C 04-full.png 550 363 640 274 04-outputs.png;        $C en-04-full.png 550 362 640 276 en-04-outputs.png
$C 05-full.png 590 361 560 278 05-sync-main.png;      $C en-05-full.png 590 361 560 278 en-05-sync-main.png
$C 06-full.png 590 331 560 338 06-sync-backup.png;    $C en-06-full.png 590 331 560 338 en-06-sync-backup.png
$C 06b-full.png 0 76 1740 44 06-banner.png;           $C en-06b-full.png 0 76 1740 44 en-06-banner.png
$C 08-full.png 510 294 720 411 08-midi.png;           $C en-08-full.png 510 287 720 426 en-08-midi.png
$C 09-full.png 2566 450 906 214 09-midi-inspector.png; $C en-09-full.png 2540 450 932 214 en-09-midi-inspector.png
cp 02-other.png 02-horizontal.png; cp en-02-other.png en-02-vertical.png
for f in 01-main 02-horizontal 03-folded 04-outputs 05-sync-main 06-sync-backup 06-banner 08-midi 09-midi-inspector \
         en-01-main en-02-vertical en-03-folded en-04-outputs en-05-sync-main en-06-sync-backup en-06-banner en-08-midi en-09-midi-inspector; do
  cp "$f.png" "$S/../img/$f.png"
done
echo "manual/img を入れ替えた。次は ../build.sh で PDF"
