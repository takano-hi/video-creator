# video-creator

本の感想をミルクボーイ風に紹介する動画を自動生成する MCP サーバー。

VOICEVOX でずんだもん・四国めたんの音声を合成し、字幕付き MP4 を出力する。

## 事前準備

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

設定後、Claude Code を再起動すると `generate_audio` / `generate_subtitle_csv` / `generate_video` ツールが利用できるようになる。

### 3. Google Slides API を設定する（`import_json_from_google_slides` を使う場合）

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成し、**Google Slides API** を有効化する
2. 「IAM と管理」→「サービスアカウント」からサービスアカウントを作成し、JSON キーをダウンロードする
3. ダウンロードした JSON ファイルの内容を `env/api.env` に以下の形式で設定する

```
GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
```

> JSON 内の改行や特殊文字が問題になる場合は、一行に整形した上で設定する。

## 毎回の作業

### 1. cover.png を所定の場所に置く

紹介する本の表紙画像を以下のパスに配置する:

```
video-creator/tmp/cover.png
```

### 2. Claude に依頼する

Claude に以下を伝えるだけで動画が生成される:

- 本のタイトルと著者
- 本の感想・印象に残った点・伝えたい方向性

例:

```
プロジェクト・ヘイル・メアリーをミルクボーイ風に紹介するプロットを作ってください。
なお、下記が私の参考です。全て入れなくてもいいので参考にしてください。

・「プロジェクト・ヘル・マフィア」みたいなタイトル
・SF小説
・主人公のグレースは理科の教師
・最後の最後まで結末がどうなるか分からないハラハラドキドキ感がたまらない
・映画化もしてるらしい　大きな改変もなく、原作ファンも大満足な内容
・科学知識をもとに問題を解決していく痛快さがたまらない
・宇宙を舞台に人間同士が助け合って困難を乗り越えていく話ではない
・人間ドラマ的な側面も面白い　グレースの地球での決断と宇宙での決断の対比とか、グレースが宇宙船に乗ることになる衝撃的な経緯とか
```

Claudeがスクリプト作成 → 音声生成 → 字幕生成 → 動画生成まで自動で行い、
生成された `video.mp4` のパスを返す。

## MCP ツール一覧

| ツール名                          | 説明                                               |
| --------------------------------- | -------------------------------------------------- |
| `get_speakers`                    | 利用可能なスピーカー一覧を返す                     |
| `generate_audio`                  | テキストリストから WAV ファイルを生成する          |
| `generate_subtitle_csv`           | 字幕 CSV を生成する                                |
| `generate_video`                  | cover.png + subtitle.csv + WAV から MP4 を生成する |
| `import_json_from_google_slides`  | Google Slides の内容を JSON としてインポートする   |
