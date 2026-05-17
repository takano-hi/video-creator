# video-creator

本の感想をミルクボーイ風に紹介する動画を自動生成する MCP サーバー。

VOICEVOX でずんだもん・四国めたんの音声を合成し、字幕付き MP4 を出力する。

動画の素材には **カバー画像（cover.png）** または **Google スライド** の2通りが使える。

## セットアップ

### 1. サーバーを起動する

```bash
docker compose up -d
```

Rails + VOICEVOX エンジンが起動する。初回は VOICEVOX のイメージ取得に時間がかかる。

ヘルスチェック:

```bash
curl http://localhost:3000/up
```

### 2. Claude の MCP 設定に追加する

`~/.claude/settings.json` の `mcpServers` に以下を追加する:

```json
{
  "mcpServers": {
    "video-creator": {
      "type": "http",
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

設定後、Claude Code を再起動すると各種ツールが利用できるようになる。

### 3. Google Slides API を設定する（`import_google_slides` を使う場合）

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成し、**Google Slides API** を有効化する
2. 「IAM と管理」→「サービスアカウント」からサービスアカウントを作成し、JSON キーをダウンロードする
3. ダウンロードした JSON ファイルの内容を `env/api.env` に以下の形式で設定する

```
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
```

> JSON 内の改行や特殊文字が問題になる場合は、一行に整形した上で設定する。

4. Google Drive に作業用フォルダを作成し、そのフォルダの閲覧権限をサービスアカウントのメールアドレスに付与する

> フォルダごと共有しておくと、フォルダ内に追加したスライドにも権限が自動的に引き継がれるため、スライドを追加するたびに権限設定をやり直す手間がなくなる。

## 使い方

### パターン A：カバー画像から生成する

本の表紙画像（cover.png）と Claude が書いたスクリプトをもとに動画を生成する。

**必要なファイル:**

```
tmp/<作業ディレクトリ>/
  cover.png       # 本の表紙画像
```

**Claude への依頼例:**

```
プロジェクト・ヘイル・メアリーをミルクボーイ風に紹介するプロットを作ってください。
なお、下記が私の参考です。全て入れなくてもいいので参考にしてください。

・「プロジェクト・ヘル・マフィア」みたいなタイトル
・SF小説
・主人公のグレースは理科の教師
・最後の最後まで結末がどうなるか分からないハラハラドキドキ感がたまらない
・映画化もしてるらしい　大きな改変もなく、原作ファンも大満足な内容
・科学知識をもとに問題を解決していく痛快さがたまらない
```

Claude がスクリプト作成 → `generate_audio` で音声生成 → `generate_subtitle_csv` で字幕生成 → `generate_video_from_cover` で動画生成まで自動で行い、`video.mp4` のパスを返す。

### パターン B：Google スライドから生成する

Google スライドのスピーカーノートをセリフとして読み取り、動画を生成する。字幕 CSV はスピーカーノートから自動生成される。

**スライドの準備:**

スライドのスピーカーノートを以下の形式で記述する:

```
ずんだもん: 『失敗の科学』という本を知ってる？
四国めたん: 知らないわ。どんな本なの？
ずんだもん: 組織が失敗から学習して改善するために必要なことが書かれた本なんだ。
```

**Claude への依頼例:**

```
以下の Google スライドをインポートして、音声を生成し、動画を作ってください。
https://docs.google.com/presentation/d/xxxxxxxx
保存先: /rails/tmp/my-book
```

Claude が `import_google_slides` でスライドをインポート → `generate_audio` で音声生成 → `generate_video_from_slides` で字幕生成・動画生成まで自動で行い、`video.mp4` のパスを返す。

## MCP ツール一覧

| ツール名 | 説明 |
| --- | --- |
| `get_speakers` | VOICEVOX で利用可能なスピーカー（声優）の一覧をスタイル ID とともに返す |
| `generate_audio` | テキストとスピーカー ID のリストから WAV ファイルを生成する。`directory` を省略するとタイムスタンプ付きの一時ディレクトリに保存される |
| `generate_subtitle_csv` | スピーカー名とテキストの行リストから `subtitle.csv` を生成する |
| `generate_video_from_cover` | `cover.png` / `subtitle.csv` / `*.wav` をもとに `video.mp4` を生成する。`ending_image` を指定するとディレクトリ内の対応するファイルを動画末尾に3秒間表示する |
| `generate_video_from_slides` | `google-slides.json` / `*.wav` をもとに字幕 CSV を自動生成して `video.mp4` を生成する。`ending_image` を指定するとディレクトリ内の対応するファイルを動画末尾に3秒間表示する |
| `import_google_slides` | Google Slides の URL からスライド内容と各スライドのサムネイル画像をインポートし、`google-slides.json` と `slides/` ディレクトリに保存する |
