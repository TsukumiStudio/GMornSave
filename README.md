# GMornSave

## 概要

書きかけで壊れない保存のGodotアドオン。

本体へ直接書くと、書いている途中で落ちた場合にそこで切れたファイルが残る。実測では、正常な保存を6割の位置で切っただけで、日数も所持金も強化もすべて消えて初期値に戻った。さらに**次の保存がその壊れたファイルを上書きするため、手で直す機会も無くなる**。

別名で書いて、読み直せることを確かめてから本体へ差し替える。差し替える前の本体は控えとして取っておく。

## 動作環境

- Godot 4.x（4.7で確認）

中身の形は JSON。`Dictionary` を渡して `Dictionary` が返る。

## 何ができるか

- **途中で落ちても本体が残る**。`.tmp` へ書く → 読み直して確かめる → 本体を `.bak` へ写す → `.tmp` を本体へ差し替える、の順で行う。どこで落ちても本体は前回の内容のまま残る。
- **書けたつもりを見抜く**。容量切れなどで、書けたのに中身が欠けていることがある。差し替える前に読み直し、駄目なら本体には触らない。
- **控えから戻す**。本体が壊れていても、丸ごと消えていても、控えから戻す。控えは前回きちんと読めた内容なので、失うのは直前の1回ぶんだけで済む。
- **壊れた本体で控えを潰さない**。控えは「読めた本体」だけから作る。壊れたもので上書きすると、戻す先が無くなる。
- **項目を増やしても古い保存が読める**。既定値の辞書を渡してもらい、その上に読んだ内容を重ねる。増えた項目は既定値のほうから埋まる。
- **無いのか読めないのかを区別する**。旧版からの引き継ぎは「無いとき」だけ試したい。読めないときに引き継ぐと、本体が消えただけの人の進行を古い内容で上書きしてしまう。

## 使い方

### 1. 取り込む

アドオン一式をリポジトリ直下へ置いてある。取り込む側の `addons/gmorn_save` へそのまま submodule として足せる。

```
git submodule add https://github.com/TsukumiStudio/GMornSave.git addons/gmorn_save
```

Godotのエディタで「プロジェクト設定 → プラグイン」から `GMornSave` を有効にする。自動読み込みへ `GMornSave` が登録される。

**リポジトリ直下に `project.godot` は置かない。** 置くとGodotがそこを別のプロジェクトと見なし、**そのフォルダを丸ごとスキャンから外す**。submoduleとして取り込んだ場合、エディタでは動くのに書き出した実行ファイルにだけアドオンが入らない。

### 2. 置き場を作る

置き場は複数あってよい。進行と設定を別のファイルに分ける、利用者ごとに分ける、といったときに1つずつ作る。

```gdscript
var store := GMornSave.open("user://progress.json")
```

### 3. 読む・書く

既定値の辞書を渡す。**毎回作り直したもの**を渡すこと。使い回すと、返した辞書へ書き込んだ内容が次回の既定値になる。

```gdscript
func default_data() -> Dictionary:
    return {"money": 0, "day": 1, "upgrades": [0, 0, 0]}

func load_all() -> void:
    data = store.load_data(default_data())
    match store.last_outcome:
        store.Outcome.RESTORED_FROM_BACKUP:
            # 控えから戻した。書き戻して本体を作り直しておく。
            store.save(data)
        store.Outcome.MISSING:
            # 何も無い。ここでだけ旧版からの引き継ぎを試す。
            if try_migrate_old_save():
                store.save(data)

func save_all() -> void:
    store.save(data)
```

### 4. どう終わったかを見る

| `last_outcome` | 意味 | 呼ぶ側ですること |
| --- | --- | --- |
| `LOADED` | 本体から読めた | いつもの経路。何も要らない |
| `RESTORED_FROM_BACKUP` | 控えから戻した | 書き戻して本体を作り直す |
| `MISSING` | 本体も控えも無い | 初回。旧版からの引き継ぎを試すならここ |
| `UNREADABLE` | あるのに読めない | 既定値で始める。**引き継ぎは試さない** |

### 5. 検証で本物を触らない

置き場を差し替えるか、書き出しだけ止める。

```gdscript
store.path = "user://test_probe/save.json"   # 置き場を移す
store.enabled = false                        # 書き出しだけ止める（読み取りは動く）
```

### その他の口

| 呼び出し | 何をするか |
| --- | --- |
| `load_data(defaults)` | 既定値の上に読んだ内容を重ねて返す |
| `save(data)` | 書き出す。成功したら `true` |
| `erase()` | 本体・控え・書きかけをまとめて消す |
| `is_readable(path)` | その置き場が読める形か |
| `backup_path()` / `temporary_path()` | 控え・書きかけの置き場 |
| `restored_from_backup(path)` | 控えから戻したときに流れる |
| `save_failed(path)` | 書き出しに失敗したときに流れる |
| `backup_suffix` / `temporary_suffix` | 後ろに付ける文字（既定 `.bak` / `.tmp`） |

`erase()` が控えと書きかけも消すのは、本体だけ消すと次に読んだときに控えから戻ってくるためである。消したはずの進行が戻ってくるのは、消せていないのと同じである。

### 手を入れる

`verify.sh` で、壊れ方ごとにどこまで守れるかを確かめられる。書きかけで落ちた・中身が切れた・本体だけ消えた、の3つを実際に作って通す。通る道だけを見ても意味がない。

```
./verify.sh
```

## クラウド保存（GMornSaveCloud）

GMornSaveで保存したJSONを [MornSaveServer](https://github.com/TsukumiStudio/MornSaveServer) へバックアップし、EditorからSave IDで別のセーブをプレビュー起動できる。通常の保存データは置き換えない。以前は別アドオン GMornSaveSaver だったものを、2026-10-07 にこのアドオンへ統合した。サイドカー `*.cloud.json` の形は変えていないので、統合前に登録した利用者もそのまま送れる。設定の名前は `gmorn_save_saver/*` から `gmorn_save_cloud/*` へ、環境変数は `GMORN_SAVE_SAVER_*` から `GMORN_SAVE_CLOUD_*` へ変わった。保存先の `user://gmorn_save_saver_*`（取り寄せたプレビュー）も `user://gmorn_save_cloud_*` へ変わった。旧アドオンは無効にして取り除くこと（残すと同じ `.cloud.json` を二重に書く）。endpoint・project_id は新しい設定名で設定し直す。

管理セーブの取得には [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) が必要（`PATH`、`/opt/homebrew/bin`、または`/usr/local/bin`から検出）。単体検証は `./verify_cloud.sh`。

### 機能

- ローカル保存と独立した `.cloud.json` サイドカーへ資格情報と最新の保留データを保存
- 起動後の `resume()` で中断した送信を再開
- HTTP失敗時は保留データを保持して再試行
- 通常のゲーム実行では画面をJPEG（幅640px以内・100KiB以下）でMornDropへ送り、URLと撮影時刻をセーブに添付
- EditorドックからSave IDで取得し、次のEditor実行だけ別ファイルを読み込む
- エディタープラグイン処理・headlessからの送信は明示的な環境変数opt-inがない限り停止（Editorのゲーム実行は通常送信）

### 使い方

1. GMornSave のプラグインを有効にすると、自動読み込み `GMornSaveCloud` とEditorドックが入ります。送り先（endpoint）を設定しない限り何も送りません。
2. プロジェクト設定に `gmorn_save_cloud/endpoint` と `gmorn_save_cloud/project_id` を設定します。サーバーURLやproject_idは環境変数 `GMORN_SAVE_CLOUD_ENDPOINT` / `GMORN_SAVE_CLOUD_PROJECT_ID` でも指定できます。秘密値は設定へ置かないでください。
3. 保存が成功した後、現在のDictionaryと通常保存パスを渡します。通常保存処理を待たせません。

```gdscript
GMornSaveCloud.submit(game_data, save_path)
GMornSaveCloud.resume(save_path) # 起動時、通常保存をロードした後に呼ぶ
```

4. Editorから別ユーザーのセーブを試すには、Editorを停止した状態でGMornSaveCloudドックへSave IDを入れて、「Cloudflare Access認証して取得」を押します。`cloudflared access login` が非同期で起動し、初回はブラウザーでCloudflare Accessへログインします。JWTはHTTPヘッダーへ渡すだけで、アドオン内には表示・保存しません。認証キャッシュはcloudflaredが管理します。project_idが一致する辞書データだけを `gmorn_save_cloud/preview_path` （既定 `user://gmorn_save_cloud_preview.json`）へ保存します。
5. ゲーム起動時、保存を読む前に `var preview_path = GMornSaveCloud.consume_preview()` を呼び、空でなければゲーム側の保存パスをその値に切り替えます。プレビュー中は送信を止めます。マーカーはEditorからの通常実行に限って一度だけ消費されます。

セーブの送信は、保存が続く間は2秒の静かな間を待ってから最新1件を送ります。プロジェクト設定の `gmorn_save_cloud/min_interval_seconds`（秒、既定0）を置くと、前の送信からその秒数が経つまで待ち、間の保存は最新1件にまとめて送ります。保存のたびに送ると、サーバーの履歴が操作ごとに細かく積もるためです。待っている間に終了した分は `.cloud.json` に残り、次の起動の `resume()` で送ります。

通常のゲーム実行でスクリーンショットを撮り、JPEGをMornDrop（`https://drop.tsukumistudio.com`）へアップロードします。新しい画像は最短120秒ごとにし、その間の保存には直近の画像URLを再利用します。取得失敗・上限超過・タイムアウト時もJSONのセーブは続きます。画像のURLとUTC撮影時刻はクラウドセーブAPIの`screenshot`項目に保存し、ゲームデータDictionaryには混ぜません。Editorプラグイン画面、headless、プレビュー実行では撮影しません。Editorから実行した通常のゲームは対象です。

MornDropの画像URLは公開URLです。URLを知る人は閲覧でき、最後に参照されてから30日後に削除されます。画面に個人情報を出した状態で保存しないでください。

送信のopt-in環境変数はEditorプラグイン中に限り `GMORN_SAVE_CLOUD_EDITOR_OPT_IN=1`、headless中に限り `GMORN_SAVE_CLOUD_TEST_OPT_IN=1` です。headlessでプレビュー消費テストを行う場合だけ `GMORN_SAVE_CLOUD_TEST_PREVIEW=1` を指定します。`GMORN_SAVE_CLOUD_LIVE_TEST=1` を付けて `verify_cloud.sh` を実行すると、設定済みのendpoint・project_idへ実際の登録、二段階アップロード、取得を行います。Live検証の管理取得では、事前に同じendpointへcloudflaredで認証しキャッシュを作成してください。

## ライセンス

Unlicense（パブリックドメイン）。

## Editorから削除する（GMornDebugMenu連携）

`gmorn_save_section.gd` を付けた `.tres` をプロジェクトのセクション置き場へ登録する。
このEditor連携には `../gmorn_debug_menu` が必要。`save_path` に削除する1ファイルの `user://` パスを指定し、旧版移行防止の印が必要なら `migration_marker_path` も設定する。
ゲーム停止中のみ二度押しで本体・バックアップ・書きかけを削除する。ディレクトリ全体は削除しない。
印の作成や削除に失敗した場合は成功表示にしない。アドオンの検証では利用者の本物のセーブを削除しない。

欄の中は1行で「今のセーブ（最終更新時刻）［削除］［開く］」。ファイルの場所はカーソルを置くと出る。時刻は手元の時刻で毎秒見直す。［開く］は同じ `save_path` のファイルを、OSのファイル管理（macOSはFinder、WindowsはExplorer）で選んだ状態で開く（`OS.shell_show_in_file_manager`）。未保存なら置き場のフォルダを開き、フォルダも無ければ案内だけを表示する。［削除］は3秒以内の二度押しで消す。再生中はどちらも操作できない。

## 名前付きJSONセーブ

見出し「セーブデータ一覧［一覧を更新］」の下で、「セーブ名」に入力して右隣の［保存］を押す。一覧の各行は「セーブ名［削除］［使う］」で、［使う］を押すとそのJSONを現在の通常保存へロードする。保存先は `<save_path>.snapshots/<名前>.json` で、ファイルの中身はゲームの辞書そのもの。通常のオートセーブで名前付きJSONは更新されない。同名は上書きせず、別名の入力を求める。空名・パス・先頭末尾の空白・80文字超などは拒否する。

停止中はセクションResourceの `save_path` を読み書きする。実行中もGMornSaveセクションを表示するには `hide_when_playing=false` にする。「開く」「削除」は従来どおり停止中のみ。実行中の保存・ロードはEditorDebugger経由でゲームへ送り、次の接続先から現在の保存先・未保存の最新値を取得する。ゲームが1つだけ接続されているときに操作可能で、未接続・複数実行・未設定・5秒間応答なしは成功扱いしない。「一覧を更新」で再同期できる。

```gdscript
GMornSave.configure_snapshots(
    func() -> String: return current_save_path(),
    func() -> Dictionary: return current_data.duplicate(true),
    func() -> String:
        load_game_data()
        var error := get_tree().reload_current_scene()
        return "" if error == OK else error_string(error)
)
```

第三引数は通常保存の置換成功後に呼ぶ。タイトルからの再開など、ゲーム固有の初期化を担当し、成功なら空文字、失敗なら説明文を返す。実行中のゲームは起動ごとに登録する。`GMornSave.snapshot_request("save" / "load" / "delete" / "list", 名前)` でも同じ処理を呼べる。

壊れたJSON・辞書以外・存在しない名前はロードしない。通常保存は既存Storeで退避・原子的に差し替える。書込み、バックアップ、renameの失敗はエラーを返し、前の通常保存を保つ。ロード前の通常保存は `.bak` に残る。各行の右にある「削除」で、その名前付きJSON・控え・書きかけだけを削除する。通常保存や別名のJSONは変更しない。実行中も同じ操作が使える。

この更新を開いているEditorへ取り込む際は、GMornSaveおよびセクションを表示するGMornDebugMenuを一度OFF→ONするか、Editorを開き直す。シーン再読込だけではEditorDebuggerPluginを再登録できない。

`sh verify.sh` は保存・復元・同名拒否・不正パス・破損JSONを検査する。`python3 verify_remote.py` は一時プロジェクトのヘッドレスEditorとゲームを実接続し、名前入力→保存→一覧のボタンからロード→停止→再実行を検査する。実際のプレイヤーの保存は使用しない。
