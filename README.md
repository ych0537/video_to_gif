# video-to-gif

ローカル動画や画面収録を、同僚に共有しやすい軽量な GIF に変換するための小さな Swift 製ツールです。macOS アプリとコマンドラインの両方を用意しています。

## 対応形式

```text
mp4, mov, webm, mkv, avi, flv, wmv, m4v, 3gp
```

入力ファイルは 50 MB 以下に制限しています。

すべての対応形式を安定して扱うには、`ffmpeg` をインストールして `PATH` から実行できる状態にしてください。`ffmpeg` が見つからない場合は macOS 標準の動画デコードにフォールバックします。この場合、主に `mp4`, `mov`, `m4v`, `3gp` などが対象になります。

## macOS アプリをビルド

```sh
bash scripts/package-app.sh
```

アプリは次の場所に作成されます。

```sh
dist/Video2GIF.app
```

Finder から開くか、次のコマンドで起動できます。

```sh
open "dist/Video2GIF.app"
```

## CLI をビルド

```sh
swift build -c release
```

実行ファイルは次の場所に作成されます。

```sh
.build/release/video-to-gif
```

## CLI の使い方

```sh
.build/release/video-to-gif input.mov output.gif --width 800 --fps 10 --start 0 --duration 0
```

調整できるパラメータ:

```sh
--width <pixels>      160, 240, 320, 360, 480, 640, 800 のいずれか。デフォルト: 800
--fps <value>         5, 10, 15, 20, 24, 30 のいずれか。デフォルト: 10
--start <seconds>     変換開始秒。0.5 秒単位で指定できます。デフォルト: 0
--duration <seconds>  切り出す長さ。0 は開始位置から最後まで。デフォルト: 0
```

画面収録では、まず次の設定から試すのがおすすめです。

```sh
.build/release/video-to-gif screen.mov demo.gif --width 800 --fps 10 --duration 8
```
