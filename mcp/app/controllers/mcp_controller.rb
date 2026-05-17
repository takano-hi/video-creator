class McpController < ApplicationController
  VOICEVOX_BASE = ENV.fetch("VOICEVOX_BASE_URL", "http://localhost:50021")

  TOOLS = [
    {
      name: "get_speakers",
      description: "VOICEVOX で利用可能なスピーカー（声優）の一覧をスタイルIDとともに返す",
      inputSchema: { type: "object", properties: {}, required: [] }
    },
    {
      name: "generate_audio",
      description: "テキストとスピーカーIDのリストを受け取り、VOICEVOX で音声ファイル（WAV）を生成して保存パスを返す",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "音声ファイルを保存するディレクトリの絶対パス（省略時はタイムスタンプ付きの一時ディレクトリを自動生成）"
          },
          items: {
            type: "array",
            description: "生成する音声のリスト",
            items: {
              type: "object",
              properties: {
                speaker: { type: "integer", description: "スピーカーID" },
                text:    { type: "string",  description: "読み上げるテキスト" }
              },
              required: ["speaker", "text"]
            }
          }
        },
        required: ["items"]
      }
    },
    {
      name: "generate_subtitle_csv",
      description: "スピーカー名とテキストの行リストを受け取り、指定ディレクトリに subtitle.csv を生成する",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "subtitle.csv を保存するディレクトリの絶対パス"
          },
          lines: {
            type: "array",
            description: "字幕の行リスト（音声ファイルと同順）",
            items: {
              type: "object",
              properties: {
                speaker: { type: "string", description: "スピーカー名（例: ずんだもん）" },
                text:    { type: "string", description: "字幕テキスト" }
              },
              required: ["speaker", "text"]
            }
          }
        },
        required: ["directory", "lines"]
      }
    },
    {
      name: "generate_video_from_cover",
      description: "cover.png / subtitle.csv / *.wav をもとに video.mp4 を生成する",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "cover.png・subtitle.csv・*.wav が格納されたディレクトリの絶対パス（出力先も同じ）"
          }
        },
        required: ["directory"]
      }
    },
    {
      name: "generate_video_from_slides",
      description: "google-slides.json / *.wav をもとに字幕CSVを自動生成して video.mp4 を生成する",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "google-slides.json・slides/（サムネイル画像）・*.wav が格納されたディレクトリの絶対パス（出力先も同じ）"
          }
        },
        required: ["directory"]
      }
    },
    {
      name: "import_google_slides",
      description: "Google Slides の URL を受け取り、スライドの内容と各スライドのサムネイル画像をインポートし、指定ディレクトリに google-slides.json および slides/ ディレクトリ内の画像ファイルとして保存する",
      inputSchema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "Google Slides の URL"
          },
          directory: {
            type: "string",
            description: "google-slides.json と slides/ ディレクトリを保存するディレクトリの絶対パス"
          }
        },
        required: ["url", "directory"]
      }
    }
  ].freeze

  def handle
    body = JSON.parse(request.body.read)
    id = body["id"]

    return head :accepted if id.nil?

    result = route_rpc(body["method"], body["params"] || {})
    render json: { jsonrpc: "2.0", id: id, result: result }
  rescue => e
    render json: { jsonrpc: "2.0", id: body&.dig("id"), error: { code: -32603, message: e.message } }
  end

  private

  def route_rpc(method, params)
    case method
    when "initialize"
      {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "voicevox-mcp", version: "1.0" }
      }
    when "tools/list"
      { tools: TOOLS }
    when "tools/call"
      call_tool(params["name"], params["arguments"] || {})
    else
      raise "Method not found: #{method}"
    end
  end

  def call_tool(name, _args)
    case name
    when "get_speakers"
      speakers = voicevox_get("/speakers")
      { content: [ { type: "text", text: JSON.pretty_generate(speakers) } ] }
    when "generate_audio"
      items = (_args["items"] || []).map { |i| { speaker: i["speaker"], text: i["text"] } }
      paths = generate_audio(items, _args["directory"])
      { content: [ { type: "text", text: JSON.pretty_generate(paths) } ] }
    when "generate_subtitle_csv"
      output_path = write_subtitle_csv(_args["directory"], _args["lines"] || [])
      { content: [ { type: "text", text: output_path } ] }
    when "generate_video_from_cover"
      output_path = GenerateVideoFromCoverService.new(_args["directory"]).call
      { content: [ { type: "text", text: output_path } ] }
    when "generate_video_from_slides"
      output_path = GenerateVideoFromSlidesService.new(_args["directory"]).call
      { content: [ { type: "text", text: output_path } ] }
    when "import_google_slides"
      output_path = ImportGoogleSlidesService.new(_args["url"], _args["directory"]).call
      { content: [ { type: "text", text: output_path } ] }
    else
      raise "Unknown tool: #{name}"
    end
  end

  # --- generate_audio ---

  def generate_audio(items, directory = nil)
    output_dir = directory || Rails.root.join("tmp", Time.now.strftime("%Y%m%d_%H%M%S")).to_s
    Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

    items.each_with_index.map do |item, i|
      output_path = File.join(output_dir, "audio#{(i + 1).to_s.rjust(3, "0")}.wav")

      query_res = voicevox_post("/audio_query", params: { text: item[:text], speaker: item[:speaker] })
      raise "audio_query failed: #{query_res.code}" unless query_res.is_a?(Net::HTTPSuccess)

      audio_query = JSON.parse(query_res.body)

      synth_res = voicevox_post("/synthesis", params: { speaker: item[:speaker] }, body: audio_query)
      raise "synthesis failed: #{synth_res.code}" unless synth_res.is_a?(Net::HTTPSuccess)

      File.binwrite(output_path, synth_res.body)
      output_path
    end
  end

  # --- generate_subtitle_csv ---

  def write_subtitle_csv(dir, lines)
    GenerateSubtitleCsvService.new(dir, lines).call
  end

  # --- VOICEVOX HTTP helpers ---

  def voicevox_get(path)
    uri = URI("#{VOICEVOX_BASE}#{path}")
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  end

  def voicevox_post(path, params: {}, body: nil)
    uri = URI("#{VOICEVOX_BASE}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    request = Net::HTTP::Post.new(uri)
    if body
      request["Content-Type"] = "application/json"
      request.body = body.to_json
    end

    Net::HTTP.new(uri.host, uri.port).request(request)
  end
end
