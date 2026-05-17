Google SlidesのURLを受け取り、動画ファイルを生成します。

## 引数

`$ARGUMENTS` にGoogle SlidesのURLを指定してください。

## 概要

MCPサーバー (`voicevox-mcp`) はHTTP JSON-RPCとして `http://localhost:3000/mcp` で稼働しています。
このスキルでは**curl経由でMCPサーバーのツールを直接呼び出します**（Claude CodeのMCPクライアント接続には依存しません）。

## 共通: ツール呼び出しの形式

各ツールは以下のJSON-RPCリクエストで呼び出します。

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d @/path/to/request.json
```

リクエスト本体のテンプレート:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "<tool_name>",
    "arguments": { ... }
  }
}
```

レスポンスは `.result.content[0].text` に結果文字列が入っています。エラー時は `.error.message` を確認してください。

`jq` で結果を取り出す例:

```bash
curl -s ... | jq -r '.result.content[0].text'
```

呼び出しが失敗した場合は **必ず処理を中断**し、エラー内容をユーザーに報告してください。

## 手順

### 1. MCPサーバーの疎通確認

```bash
curl -s --max-time 3 -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

`serverInfo.name` が `voicevox-mcp` を返せばOK。失敗した場合は「`docker compose up -d` でMCPサーバーを起動してください」とユーザーへ伝えて中断してください。

### 2. 保存先ディレクトリの作成

現在の日時から `YYYYMMDD_HHMMSS` 形式のディレクトリ名を生成し、作成してください。

- **ホストパス**（ファイル操作用）: `<プロジェクトルート>/mcp/tmp/YYYYMMDD_HHMMSS`
- **コンテナパス**（MCPツール引数用）: `/rails/tmp/YYYYMMDD_HHMMSS`

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
DIRNAME=$(date +%Y%m%d_%H%M%S)
HOST_DIR="$PROJECT_ROOT/mcp/tmp/$DIRNAME"
CONTAINER_DIR="/rails/tmp/$DIRNAME"
mkdir -p "$HOST_DIR"
```

以降の手順では `HOST_DIR` / `CONTAINER_DIR` の値を保持して利用してください。

### 3. スライド情報のインポート

`import_google_slides` ツールをcurlで呼び出します。リクエストJSONを一時ファイルに書き出してからPOSTしてください。

```bash
cat > "$HOST_DIR/_req_import.json" <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "import_google_slides",
    "arguments": {
      "url": "$ARGUMENTS",
      "directory": "$CONTAINER_DIR"
    }
  }
}
EOF

curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d @"$HOST_DIR/_req_import.json" | tee "$HOST_DIR/_res_import.json" | jq .
```

レスポンスに `error` フィールドが含まれている場合は処理を中断してください。
成功後、ホストパスの `google-slides.json` をReadツールで読み込み、`slides` 配列のスピーカー名・statement・各スライドのスライド画像情報を確認してください。

### 4. スピーカーID確認

`get_speakers` ツールをcurlで呼び出します。

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_speakers","arguments":{}}}' \
  | jq -r '.result.content[0].text' > "$HOST_DIR/_speakers.json"
```

`_speakers.json` をReadツールで読み込み、`google-slides.json` に登場する各スピーカー名について「ノーマル」スタイルのIDを特定してください（例: ずんだもん=3、四国めたん=2）。

### 5. 音声データ生成

`google-slides.json` の各statementを順番通りに、スピーカー名をIDへ変換した `items` 配列を組み立てます。**順番と行数は字幕生成と一致している必要があるため変えないでください。**

Writeツールで `$HOST_DIR/_req_audio.json` を作成してください（中身の例）:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "generate_audio",
    "arguments": {
      "directory": "/rails/tmp/YYYYMMDD_HHMMSS",
      "items": [
        { "speaker": 3, "text": "1行目のテキスト" },
        { "speaker": 2, "text": "2行目のテキスト" }
      ]
    }
  }
}
```

`directory` には**コンテナパス**（`$CONTAINER_DIR` の値）をそのまま埋め込んでください。

リクエスト送信:

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d @"$HOST_DIR/_req_audio.json" | tee "$HOST_DIR/_res_audio.json" | jq .
```

`error` が返ったら中断。成功時は `audio001.wav`, `audio002.wav`, ... が `$HOST_DIR` に生成されます。

### 6. 動画ファイル生成

`generate_video_from_slides` ツールをcurlで呼び出します。

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "generate_video_from_slides",
    "arguments": {
      "directory": "$CONTAINER_DIR"
    }
  }
}
EOF
)" | tee "$HOST_DIR/_res_video.json" | jq .
```

成功後、ホストパスでファイルを確認しユーザーに完了を報告してください。

```bash
ls -lh "$HOST_DIR/video.mp4"
```
