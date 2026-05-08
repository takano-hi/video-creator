require "net/http"
require "json"
require "uri"

VOICEVOX_BASE = "http://localhost:50021"

def post_json(path, params: {}, body: nil)
  uri = URI("#{VOICEVOX_BASE}#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri)

  if body
    request["Content-Type"] = "application/json"
    request.body = body.to_json
  end

  http.request(request)
end

def generate_audio_files(items)
  output_dir = "./tmp/#{Time.now.strftime("%Y%m%d_%H%M%S")}"
  Dir.mkdir(output_dir)

  items.each_with_index do |item, i|
    speaker = item[:speaker]
    text = item[:text]
    output_path = "#{output_dir}/audio#{(i + 1).to_s.rjust(3, "0")}.wav"

    puts "  [#{i + 1}/#{items.size}] speaker=#{speaker} text=#{text}"

    response = post_json("/audio_query", params: { text: text, speaker: speaker })
    raise "audio_query failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    audio_query = JSON.parse(response.body)

    response = post_json("/synthesis", params: { speaker: speaker }, body: audio_query)
    raise "synthesis failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    File.binwrite(output_path, response.body)
    puts "    saved to #{output_path} (#{response.body.bytesize} bytes)"
  end
end

puts "generating audio files..."

generate_audio_files([
  { speaker: 3, text: "ずんだもんなのだ" },
  { speaker: 1, text: "四国めたんよ" },
  { speaker: 2, text: "春日部つむぎなのだ" },
])
