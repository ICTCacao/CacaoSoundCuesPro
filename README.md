# CacaoSoundCues Pro

舞台のポン出しアプリ [CacaoSoundCues](https://github.com/ICTCacao/CacaoSoundCues) の Pro 版（Mac 用・無料・オープンソース）。
Simple 版の機能に、**台本連動**（ScenarioWriterSolo の台本・PDF の台本を横に出し、きっかけを台本の位置に結びつける）、
**台本進行**（Enter で台本の順に鳴らす）、**出力の系統**（複数の出力）、**バックアップ機との同時運転**、**MIDI コントロール**を足したもの。

- ダウンロード: [Releases](https://github.com/ICTCacao/CacaoSoundCuesPro/releases) の `CacaoSoundCuesPro-<版>.dmg` と、マニュアル（日本語・英語の PDF）
- 対応: macOS 14 以降。画面は日本語／English
- ライセンス: MIT（[LICENSE](LICENSE)）

## 作り

- となりに Simple 版を置いてビルドする（`~/CacaoApps/CacaoSoundCues` と `~/CacaoApps/CacaoSoundCuesPro`）。
  Simple 版のソース（`../CacaoSoundCues/CacaoSoundCues`）と Core パッケージに、`Pro/` を足して 1 つのアプリにする
- Simple 版のソースの中の `#if PRO` が差し込み口（主画面の横の台本パネル、上の帯のボタン、インスペクタのきっかけ、← → キー、開く・保存）
- アプリ名は CacaoSoundCuesPro.app（bundle id `com.ictcacao.CacaoSoundCuesPro`）。設定は Simple 版と別に保存される

```sh
git clone https://github.com/ICTCacao/CacaoSoundCues.git
git clone https://github.com/ICTCacao/CacaoSoundCuesPro.git
cd CacaoSoundCuesPro
xcodegen generate
xcodebuild -scheme CacaoSoundCuesPro -configuration Release -derivedDataPath build/dd build
rm -rf dist/CacaoSoundCuesPro.app && cp -R build/dd/Build/Products/Release/CacaoSoundCuesPro.app dist/
./make-dmg.sh   # dist/CacaoSoundCuesPro-<版>.dmg（古い版の dmg は消す）
```

版は `./bump-version.sh` で 0.0.1 ずつ上げる（`project.yml`・`Pro/Resources/Info.plist`・マニュアルの表紙と dmg の名前（`manual/*.md`）を書き換える。引数で番号を指定もできる）。dist に置くビルドの前に毎回実行する。

## マニュアル

`manual/CacaoSoundCuesPro-マニュアル.md`（日本語）と `manual/CacaoSoundCuesPro-Manual-en.md`（英語）。Marp、Simple 版のマニュアルと
同じ見た目。`manual/build.sh` で両方の PDF を作り `dist/` にも置く（要 `brew install marp-cli` と Google Chrome）。基本の操作は Simple 版のマニュアルにまかせ、Pro の機能だけを書く。

画面写真（`manual/img/`）は開発版（Debug）を起動引数で撮る。本物の公演データを写さないよう、作った音と
ScenarioWriterSolo の `samples/sample.scwd` で作ったサンプル公演を使う。撮るときは出力の系統と同時運転を始めない
（このMacの出力や役の設定に触らない）。英語版の画面写真（`img/en-*.png`）は、英語の名前のサンプル（音のファイル名も英語）を `-language en` で撮る
（台本は日本語のサンプルのまま。台本パネルは日本語の台本を紙と同じ字数で折り返す作りのため）。

Pro の機能の言葉の英訳は `Pro/Resources/Languages/en-pro.json`（Simple 版の `en.json` に重ねて読む）。言葉を足したら、ここにも訳を足す。

撮り直すときは `manual/shots/batch.sh`（2026-10-16 に作った）。Debug をビルドしてから実行すると、
`make_samples.py` が `sample/夕暮れの谷.ccsc` から撮影用のキューシート（日本語・英語 × 縦・横。4 曲のリスト〈作った音〉・
メモ・書き込み・MIDI の割り当て入り）を `manual/shots/shots/` に作り、`shot.sh` が開発版をライトの見た目
（`-NSRequiresAquaSystemAppearance YES`）で起動して左のディスプレイ（1x）に窓を置き、`winid` で窓の番号を取って
`screencapture -l` で撮る。出力の系統は `-pro.outputs '<JSON の16進>'`、MIDI の画面は `vmidi`（CoreMIDI の仮想の機器
「MIDI Controller」「Lighting Console」）を上げて撮る。シート・帯・インスペクタの行は `crop` で切り抜く（09 だけ主ディスプレイ 2x）。
07（PDF の台本）は撮り直していない（2026-10-12 のまま）。

```sh
<Debug の app>/Contents/MacOS/CacaoSoundCuesPro -NSRequiresAquaSystemAppearance YES -debugOpen <サンプル.ccsc> \
  -debugSelectKey 18 -pro.sync.role off -pro.showScript '<true/>' -showKeyboard NO -showInspector YES -showList YES \
  [-debugOutputs YES] [-debugSync YES -pro.sync.role main|backup] [-pro.outputs '<系統の JSON を16進>'] \
  [-debugMIDI YES -pro.midi.output '<送る機器の名前>']
screencapture -x -o -l <窓の番号> 01-main.png
```

## Pro の機能

### 台本連動（ScenarioWriterSolo の .scwd）

- 台本を取り込み、主画面の左に出す。縦書き・横書き。1 行は台本の書式（人物名欄 ＋ 本文の文字数）で折り返し、
  紙の台本と同じ位置で折れる。入りきらないときは文字を小さくする
- 自分でページを送る（← →。縦書きは ← が次）。ページは一列に並び（縦書きは右から左）、マウスの横スクロール・ホイール、トラックパッドで巻物のように流せる（止めたところで止まる）。Standby のきっかけへ自動で送るのはオプション
- キー・リストの曲を、台本の **文字の位置** に結びつける（右クリック「ここのきっかけにする」）。止める位置も決められる
- 同じキー・曲のきっかけを何か所にも足せる（右クリック「ここにも足す」・インスペクタ「選んだ位置にも足す」）。`pro.json` の
  `links` は きっかけの ID → 位置で、1 か所目の ID はキー・曲の ID そのもの、2 か所目からは新しい ID を `extraLinks`（きっかけ → キー・曲）でたどる。
  `ends`・`memos` もきっかけごと。台本進行ではそれぞれ別の Standby になり、Playing は鳴らしたきっかけの線に出す。
  音量などを変えたいときは、キーを option＋ドラッグでコピーして別のキーにする（出力の系統も引き継ぐ。きっかけと MIDI を送る設定は引き継がない）
- ページの下（横書きは右）の **きっかけの帯** に、位置から色の線を引き、キーの札・名前・メモを横書きで出す（音響台本の書き方）。
  止める位置まで線を伸ばし F.O. / C.O. と書く。次のページにきっかけがあれば下に出す
- きっかけの帯の印を ⌘＋クリック・control＋クリックすると、そのキー・曲を鳴らす
- きっかけの帯（書き込みエリア）を右クリックして、選んだキー・曲を「ここのきっかけにする」「ここで止める」。
  クリックした位置に線が始まる（行間でもよい）。印を右クリックで、メモ・止める位置を外す・結びつきを外す
- 帯の印をドラッグして線の位置をずらす（ダブルクリックで文字の位置に戻す）
- 帯に、きっかけに属さないメモも書ける（右クリック「ここにメモを書く…」。紙の台本の余白の鉛筆書きのように）
- 台本のパネルは左に畳める。右へ広げると、主画面を隠して窓いっぱいにできる
- キューシート（.ccsc）の中の `pro.json`（結びつき・止める位置・メモ・表示の設定）と `Script/`（台本のコピー）に保存。
  Simple 版はこれらに触らないので、Simple 版で開いて保存しても消えない
- 台本の行は ScenarioWriterSolo が付ける `uid` で指す（直しても位置がずれにくい）。uid の無い古い台本は場面と行の番号で代用

### 台本進行（台本の順に Enter で鳴らす）

- 台本のパネルの見出しの「台本進行」で入・切。この Mac に保存（`pro.scriptRun`。本番モードと同じく起動し直しても続く）。台本が無いときは効かない
- 台本に結びついたきっかけ（キー・リストの曲）を、台本の順（場面 → 行 → 文字の位置 ＋ ずらした量。PDF はページ → ページの中の位置）に並べ、
  1 つを Standby にする。入れたときは台本の最初のきっかけ（そのページを出す）。入れている間、ボタンは「進行解除」になり、押すと台本から Standby を消す
- **Enter（Return）** で Standby を鳴らし、Standby を次のきっかけへ。**Space** は、鳴っている音をその音のフェードアウト設定で 1 つ止める。どれを止めるかはキューラインどおり:
  止める位置（F.O./C.O.）のある音は台本でいちばん先に終わる音から。それが鳴っていなければ、いちばん後に鳴らし始めた音。次に止まる音の札は「Playing」の後ろに「space」のキー、下の帯にも「space ▸ 曲」と出す。止めている音は「Fading」（灰）。**↑↓** で Standby を前・次のきっかけへ
- 下の帯（ページ送りの行）に Standby（札・名前・メモ・操作の案内。台本の広さを変えて組み直さないよう、台本の上には出さない）。キューラインのラベルの下（線・名前・Standby の 3 段）に「Standby」（オレンジ）・「Playing」（緑）の札。
  帯のラベルのダブルクリック・右クリック「Standby にする」、リストの曲のダブルクリックでも Standby を決められる（台本に結びついた曲だけ）
- 「Standby のきっかけへ自動でページを送る」が ON のとき、Enter で鳴らしたら、鳴らしたきっかけ（Playing）が鳴り終わってから Standby のページへ送る
  （鳴らしたキューラインを見ていられるように）。↑↓ などで Standby を動かしたときはすぐ送る
- Esc（全停止）で、音を止めるのといっしょに台本進行も解除し、台本から Standby を消す。バックアップ機で手で押した Esc は音を止めるだけ
  （メイン機とずれないように。メイン機の Esc なら届いて一緒に解除）
- ⌘＋クリック・control＋クリックで鳴らすと、Standby はその次のきっかけへ（そこから進める）
- リストは曲（音源設定）の置き場所だけになる: 曲は 1 曲ずつ鳴らし（「Return を押してから n 秒」の待ちは効く）、続けて鳴らさない。
  リストの開始／停止キー・開始ボタンは効かない。入れたとき鳴っているリストの曲は最後まで鳴り、次の曲へは進まない。キーマップ（キーを押して鳴らす）はそのまま
- Simple 版の `#if PRO` の差し込み口: `advanceActiveSequence`（Enter）・`endCurrentSequenceSong`（Space）・`moveCue`（↑↓）・`cueStep`・
  `toggleSequence`・`startSequence` で台本進行に回す。同時運転の操作の入口の後で回すので、MIDI の割り当て（Return・スペース・↑↓）と
  バックアップ機にもそのまま乗る。入・切・Standby・印から鳴らすは `SyncOp` の `scriptRun` / `scriptStandby` / `scriptPlay`

### PDF の台本（ScenarioWriterSolo 以外）

- 「台本を取り込む…」で PDF も選べる。PDF の 1 ページを 1 ページとして、帯のぶんを空けた残りに縦横の比のまま出す
  （文字の大きさ・字数・行間・文字間は変えられないので、⋯ メニューに出さない）
- 縦・横は「台本の向き」: 縦なら帯は下・← が次のページ、横なら帯は右。ページ送り・スクロール・自動でページを送る・同時運転は文字の台本と同じ
- きっかけの位置は `line: "pdf-<ページ（0 から）>"`、`offset` はページの中の位置の 1 万分率（縦は右の端から、横は上の端から）。
  `nudge` も同じ 1 万分率。ページの上にも、きっかけの位置にうすい線を引く（止める位置は点線）
- キューシートには `Script/<名前>.pdf` として入る。PDF は中身を読み込んでから開く（元のファイルを動かしても困らない）

### 出力の系統（複数の出力）

- 上の帯の「出力」で、系統（名前 ＋ 機器 ＋ 左右のチャンネル 1-2 / 3-4 …）を決める。最初の系統がメイン
- キー・リストの曲ごとに、インスペクタの「出力」で系統を選ぶ（選ばなければメイン）。キューシートには系統の名前で保存
- ミキサーは 1 つのまま、系統ごとに左右を書き分ける（`CueVoiceSpec.bus`）。リストの曲のつなぎは系統が違ってもずれない
- 別々の機器を選ぶと、それらをまとめた機器セット（アグリゲートデバイス。このアプリの中だけ、アプリを終えると消える）を作り、
  1 台の多チャンネルの機器として鳴らす。時計はメインの機器に合わせ、ほかはずれを macOS が補正する。サンプルレートはメインにそろえる
- 系統の設定（機器）はこの Mac に保存（`pro.outputs`）。決めた機器で始められなければ、システムの出力に戻して知らせる
- メインだけでシステムの出力の 1-2 なら、Simple 版と同じ出し方

### バックアップ機との同時運転

- 上の帯の「同時運転」で、このMacを「メイン機」か「バックアップ機」にする。同じネットワーク（有線 LAN をおすすめ）でつなぐ
- メイン機の操作（鳴らす・止める・Standby・リストの開始停止・Esc・全体の音量・台本のページとスクロール）を、
  「何をしたか」としてバックアップ機へ送る。音は送らない。2 台とも自分の機器から鳴らし、ミキサーで人が切り替える
- メイン機はポート 52710 で待ち受け、Bonjour（`_cacaosc._tcp`）で名乗る。初めての相手とは 4 桁の番号で組にする
- 0.5 秒ごとに合図。2 秒届かなければ切れたとみなし、バックアップ機に大きく出す。バックアップ機はつなぎ直す
- バックアップ機の手の操作は効かない（全体の音量と Esc は効く）。「引き継ぐ」でメイン機になる（世代が上がり、
  元のメイン機が戻ってくるとバックアップ機になる）
- キューシートが同じか照らし合わせ、違えばメイン機から送れる（音ファイル・台本ごと）
- 2 台は同じ機種（同じ画面の大きさ）をおすすめ。画面の狭い Mac では、上の帯のボタンを絵だけにし、パネルを縮める
- まだ: 途中からつないだとき、鳴っている音（再生位置まで）と Standby をメイン機に合わせる

### MIDI コントロール

- 上の帯の「MIDI」で設定する。受ける機器（ふだんはすべての MIDI 入力）と送る機器はこの Mac に保存（`pro.midi.input` / `pro.midi.output`）。
  割り当ては キューシートの `pro.json` の `midi` に保存
- **受ける**: ノート・CC・プログラムチェンジ・MSC（MIDI Show Control）の合図に、操作を割り当てる。「覚えさせる」を押してから合図を送ると覚える。
  操作は、キー（KeyCue の id）・リストの開始／停止・Return・スペース・Esc・↑↓（Standby）・台本のページ・全体の音量（CC の値 0〜127 → -40〜+6 dB）
- CC はボタンとして使うとき、値が 64 をまたいで上がったときに「押した」とみなす。ノートはベロシティ 0 を無視
- MSC は「機器の番号」が合うもの（自分の番号か 127）だけ受ける。GO などの命令とキューの番号で割り当て、キューの番号つきの割り当てが無ければ
  「番号を問わない」割り当てを使う。「MSC のよく使う割り当てを足す」で GO → Return、STOP → スペース、ALL OFF → Esc
- インスペクタの「MIDI で鳴らす」で、そのキーの合図を覚えさせられる
- **送る**: キー・リストの曲が鳴り始めたときに、ノート（0.1 秒後にノートオフ）・CC・プログラムチェンジ・MSC GO（命令の形式 7F）を送る。
  インスペクタの「MIDI を送る」で決める。鳴っている間に押して止める・何もしないときは送らない。Return を押してから待つ曲は、鳴るときに送る
- 受けた操作は AppModel の操作の入口を通るので、同時運転でもバックアップ機へ同じ操作が届く。バックアップ機では手の操作と同じく効かず、
  MIDI も送らない（照明卓などに 2 回届かないように。引き継いだら送る）
- CoreMIDI は MIDI 1.0 の UMP（`MIDIInputPortCreateWithProtocol` / `MIDISendEventList`）で扱う。システムエクスクルーシブは 6 バイトずつ

### これから

- 同時運転: 途中からつないだとき、鳴っている音と Standby をメイン機に合わせる
