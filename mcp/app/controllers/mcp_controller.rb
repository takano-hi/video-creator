class McpController < ApplicationController
  VOICEVOX_BASE        = ENV.fetch("VOICEVOX_BASE_URL", "http://localhost:50021")
  CONVERSATION_INTERVAL = 0.2
  CUSTOM_BR_CODE       = "{br}"

  VideoSubtitle = Struct.new(:start_time_sec, :end_time_sec, :speaker, :text, :style)

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
      name: "generate_video",
      description: "指定ディレクトリ内の cover.png / subtitle.csv / *.wav から video.mp4 を生成する",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "cover.png・subtitle.csv・*.wav が格納されたディレクトリの絶対パス"
          }
        },
        required: ["directory"]
      }
    },
    {
      name: "import_json_from_google_slides",
      description: "Google Slides の URL を受け取り、スライドの内容を JSON としてインポートし、指定ディレクトリに google-slides.json として保存する",
      inputSchema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "Google Slides の URL"
          },
          directory: {
            type: "string",
            description: "google-slides.json を保存するディレクトリの絶対パス"
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
      paths = generate_audio(items)
      { content: [ { type: "text", text: JSON.pretty_generate(paths) } ] }
    when "generate_subtitle_csv"
      output_path = write_subtitle_csv(_args["directory"], _args["lines"] || [])
      { content: [ { type: "text", text: output_path } ] }
    when "generate_video"
      output_path = run_generate_video(_args["directory"])
      { content: [ { type: "text", text: output_path } ] }
    when "import_json_from_google_slides"
      output_path = ImportJsonFromGoogleSlidesService.new(_args["url"], _args["directory"]).call
      { content: [ { type: "text", text: output_path } ] }
    else
      raise "Unknown tool: #{name}"
    end
  end

  # --- generate_audio ---

  def generate_audio(items)
    output_dir = Rails.root.join("tmp", Time.now.strftime("%Y%m%d_%H%M%S")).to_s
    Dir.mkdir(output_dir)

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
    raise "Directory not found: #{dir}" unless Dir.exist?(dir)

    output_path = File.join(dir, "subtitle.csv")
    content = lines.map { |l| "#{l["speaker"]},#{l["text"]}" }.join("\n")
    File.write(output_path, content)

    output_path
  end

  # --- generate_video ---

  def run_generate_video(dir)
    validate_video_inputs!(dir)

    wav_files = Dir.glob(File.join(dir, "*.wav")).sort

    clear_video_outputs(dir)
    merge_audio_files(dir, wav_files)

    subtitles = parse_subtitles(dir, wav_files)
    write_ass_subtitle(dir, subtitles)
    write_srt_subtitle(dir, subtitles)

    assemble_video(dir)

    File.join(dir, "video.mp4")
  end

  def validate_video_inputs!(dir)
    raise "Directory not found: #{dir}" unless Dir.exist?(dir)
    raise "cover.png not found in #{dir}" unless File.exist?(File.join(dir, "cover.png"))
    raise "subtitle.csv not found in #{dir}" unless File.exist?(File.join(dir, "subtitle.csv"))
    raise "No .wav files found in #{dir}" if Dir.glob(File.join(dir, "*.wav")).empty?
  end

  def clear_video_outputs(dir)
    %w[merged.mp3 subtitle.ass subtitle.srt video.mp4].each do |f|
      path = File.join(dir, f)
      File.delete(path) if File.exist?(path)
    end
  end

  def merge_audio_files(dir, wav_files)
    audio_inputs  = wav_files.map { |f| "-i #{Shellwords.escape(f)}" }.join(" ")
    silence_parts = wav_files.length.times.map { |i| "[s#{i}]" }.join("")
    merge_parts   = wav_files.each_with_index.map { |_, i| "[#{i}:a][s#{i}]" }.join("")
    output_path   = Shellwords.escape(File.join(dir, "merged.mp3"))

    cmd = "ffmpeg #{audio_inputs} " \
          "-filter_complex \"anullsrc=r=44100:cl=stereo:d=#{CONVERSATION_INTERVAL}," \
          "asplit=#{wav_files.length}#{silence_parts}; " \
          "#{merge_parts}concat=n=#{wav_files.length * 2}:v=0:a=1[out]\" " \
          "-map \"[out]\" #{output_path}"
    system(cmd)
  end

  def assemble_video(dir)
    cover    = Shellwords.escape(File.join(dir, "cover.png"))
    audio    = Shellwords.escape(File.join(dir, "merged.mp3"))
    subtitle = File.join(dir, "subtitle.ass")
    output   = Shellwords.escape(File.join(dir, "video.mp4"))

    system("ffmpeg -loop 1 -i #{cover} -i #{audio} -vf \"ass=#{subtitle}\" " \
           "-c:v libx264 -tune stillimage -c:a aac -b:a 192k -shortest -pix_fmt yuv420p #{output}")
  end

  def parse_subtitles(dir, wav_files)
    csv_rows = File.read(File.join(dir, "subtitle.csv")).split("\n")

    prev_end_time = CONVERSATION_INTERVAL
    wav_files.each_with_index.map do |filepath, i|
      length = `ffprobe -i #{Shellwords.escape(filepath)} -show_entries format=duration -v quiet -of csv="p=0"`.to_f

      speaker, text = csv_rows[i].split(",")
      start_time    = i > 0 ? prev_end_time + CONVERSATION_INTERVAL : prev_end_time
      end_time      = start_time + length
      prev_end_time = end_time

      style = if speaker.include?("四国めたん") then "Pink"
              elsif speaker.include?("ずんだもん") then "Green"
              else "Default"
              end

      VideoSubtitle.new(start_time, end_time, speaker, text, style)
    end
  end

  def write_ass_subtitle(dir, subtitles)
    script_info = <<~ASS.chomp
      [Script Info]
      ; Script generated by FFmpeg/Lavc61.19.101
      ScriptType: v4.00+
      PlayResX: 384
      PlayResY: 288
      ScaledBorderAndShadow: yes
      YCbCr Matrix: None
    ASS

    style_section = <<~ASS.chomp
      [V4+ Styles]
      Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
      Style: Default,Arial,12,&Hffffff,&Hffffff,&H0,&H0,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1
      Style: Green,Arial,12,&H00E676,&H00E676,&H0,&H0,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1
      Style: Pink,Arial,12,&HFF80AB,&HFF80AB,&H0,&H0,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1
    ASS

    dialogues = subtitles.map do |sub|
      "Dialogue: " + [
        "0",
        format_ass_time(sub.start_time_sec),
        format_ass_time(sub.end_time_sec),
        sub.style,
        "", "0", "0", "0", "",
        sub.text.gsub(CUSTOM_BR_CODE, "\\n"),
      ].join(",")
    end

    event_section = ([
      "[Events]",
      "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ] + dialogues).join("\n")

    File.write(File.join(dir, "subtitle.ass"), [script_info, style_section, event_section].join("\n\n"))
  end

  def write_srt_subtitle(dir, subtitles)
    content = subtitles.each_with_index.map do |sub, i|
      [
        i.to_s,
        "#{format_srt_time(sub.start_time_sec)} --> #{format_srt_time(sub.end_time_sec)}",
        sub.text.gsub(CUSTOM_BR_CODE, "\n"),
      ].join("\n")
    end.join("\n\n")

    File.write(File.join(dir, "subtitle.srt"), content)
  end

  def format_ass_time(seconds)
    h  = (seconds / 3600).to_i
    m  = ((seconds % 3600) / 60).to_i
    s  = (seconds % 60).to_i
    cs = ((seconds - seconds.to_i) * 100).to_i
    format("%01d:%02d:%02d.%02d", h, m, s, cs)
  end

  def format_srt_time(seconds)
    h  = (seconds / 3600).to_i
    m  = ((seconds % 3600) / 60).to_i
    s  = (seconds % 60).to_i
    ms = ((seconds - seconds.to_i) * 1000).to_i
    format("%01d:%02d:%02d,%03d", h, m, s, ms)
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
