# CacaoSoundCues Pro（非公開）

舞台のポン出しアプリ [CacaoSoundCues](https://github.com/ICTCacao/CacaoSoundCues)（公開・MIT）の Pro 版。Mac だけ。

## 作り

- となりに公開版を置いてビルドする（`~/CacaoApps/CacaoSoundCues` と `~/CacaoApps/CacaoSoundCuesPro`）。
  公開版のソース（`../CacaoSoundCues/CacaoSoundCues`）と Core パッケージに、`Pro/` を足して 1 つのアプリにする
- 公開版のソースの中の `#if PRO` が差し込み口（主画面の横の台本パネル、上の帯のボタン、インスペクタのきっかけ、← → キー、開く・保存）
- アプリ名は CacaoSoundCuesPro.app（bundle id `com.ictcacao.CacaoSoundCuesPro`）。設定は無料版と別に保存される

```sh
xcodegen generate
xcodebuild -scheme CacaoSoundCuesPro -configuration Release -derivedDataPath build/dd build
cp -R build/dd/Build/Products/Release/CacaoSoundCuesPro.app dist/
```

## Pro の機能

### 台本連動（ScenarioWriterSolo の .scwd）

- 台本を取り込み、主画面の左に出す。縦書き・横書き。1 行は台本の書式（人物名欄 ＋ 本文の文字数）で折り返し、
  紙の台本と同じ位置で折れる。入りきらないときは文字を小さくする
- 自分でページを送る（← →。縦書きは ← が次）。Standby のきっかけへ自動で送るのはオプション
- キー・リストの曲を、台本の **文字の位置** に結びつける（右クリック「ここのきっかけにする」）。止める位置も決められる
- ページの下（横書きは右）の **きっかけの帯** に、位置から色の線を引き、キーの札・名前・メモを横書きで出す（音響台本の書き方）。
  止める位置まで線を伸ばし F.O. / C.O. と書く。次のページにきっかけがあれば下に出す
- キューシート（.ccsc）の中の `pro.json`（結びつき・止める位置・メモ・表示の設定）と `Script/`（台本のコピー）に保存。
  無料版はこれらに触らないので、無料版で開いて保存しても消えない
- 台本の行は ScenarioWriterSolo が付ける `uid` で指す（直しても位置がずれにくい）。uid の無い古い台本は場面と行の番号で代用

### これから

- 複数の出力（スピーカーの系統分け）
- バックアップ機との同時運転
