class GenerateVideoFromSlidesService
  MAX_LINE_WIDTH = GenerateVideoBaseService::PLAY_RES_X * 0.8

  def initialize(dir, ending_image: nil)
    @dir          = dir
    @ending_image = ending_image
    @base         = GenerateVideoBaseService.new(dir)
  end

  def call
    validate_inputs!

    wav_files = Dir.glob(File.join(@dir, "*.wav")).sort

    clear_outputs
    generate_subtitle_csv
    @base.merge_audio_files(wav_files)

    subtitles = @base.parse_subtitles(wav_files) { |text| wrap_text(text) }
    @base.write_ass_subtitle(subtitles)
    @base.write_srt_subtitle(subtitles)

    assemble_video(wav_files)

    if @ending_image
      ending_path = File.join(@dir, @ending_image)
      @base.append_ending_image(ending_path) if File.exist?(ending_path)
    end

    File.join(@dir, "video.mp4")
  end

  private

  def validate_inputs!
    raise "Directory not found: #{@dir}" unless Dir.exist?(@dir)

    slides_path = File.join(@dir, "google-slides.json")
    raise "google-slides.json not found in #{@dir}" unless File.exist?(slides_path)

    JSON.parse(File.read(slides_path)).each do |slide|
      path = File.expand_path(slide["thumbnail"].to_s, @dir)
      raise "thumbnail not found: #{path}" unless File.exist?(path)
    end

    raise "No .wav files found in #{@dir}" if Dir.glob(File.join(@dir, "*.wav")).empty?
  end

  def clear_outputs
    %w[merged.mp3 subtitle.ass subtitle.srt subtitle.csv video.mp4 video_main.mp4].each do |f|
      path = File.join(@dir, f)
      File.delete(path) if File.exist?(path)
    end
  end

  def generate_subtitle_csv
    slides = JSON.parse(File.read(File.join(@dir, "google-slides.json")))
    lines  = slides.flat_map do |slide|
      (slide["speaker_notes"] || []).map { |n| { "speaker" => n["speaker"], "text" => n["statement"] } }
    end
    GenerateSubtitleCsvService.new(@dir, lines).call
  end

  def assemble_video(wav_files)
    slides = JSON.parse(File.read(File.join(@dir, "google-slides.json")))

    offset = 0
    slide_clips = slides.filter_map do |slide|
      count = (slide["speaker_notes"] || []).length
      wavs  = wav_files[offset, count] || []
      offset += count
      next if wavs.empty?

      duration  = wavs.sum { |f| `ffprobe -i #{Shellwords.escape(f)} -show_entries format=duration -v quiet -of csv="p=0"`.to_f }
      duration += count * GenerateVideoBaseService::CONVERSATION_INTERVAL
      { image: File.expand_path(slide["thumbnail"].to_s, @dir), duration: duration }
    end

    n        = slide_clips.length
    inputs   = slide_clips.map { |c| "-loop 1 -t #{c[:duration]} -i #{Shellwords.escape(c[:image])}" }.join(" ")
    concat   = n.times.map { |i| "[#{i}:v]" }.join("")
    subtitle = File.join(@dir, "subtitle.ass")
    audio    = Shellwords.escape(File.join(@dir, "merged.mp3"))
    output   = Shellwords.escape(File.join(@dir, "video.mp4"))

    cmd = "ffmpeg #{inputs} -i #{audio} " \
          "-filter_complex \"#{concat}concat=n=#{n}:v=1:a=0[v];[v]ass=#{subtitle}[vout]\" " \
          "-map \"[vout]\" -map \"#{n}:a\" " \
          "-c:v libx264 -bf 0 -c:a aac -b:a 128k -shortest -pix_fmt yuv420p #{output}"
    system(cmd)
  end

  def wrap_text(text)
    return text if text_width(text) <= MAX_LINE_WIDTH

    morphemes = []
    Natto::MeCab.new.parse(text) { |node| morphemes << node.surface unless node.surface.empty? }

    lines         = []
    current       = ""
    current_width = 0.0

    morphemes.each do |m|
      w = text_width(m)
      if current_width + w > MAX_LINE_WIDTH && !current.empty?
        lines << current
        current       = m
        current_width = w
      else
        current       += m
        current_width += w
      end
    end
    lines << current unless current.empty?
    lines.join(GenerateVideoBaseService::CUSTOM_BR_CODE)
  end

  def text_width(str)
    str.chars.sum { |c| c.ord < 256 ? GenerateVideoBaseService::FONT_SIZE * 0.5 : GenerateVideoBaseService::FONT_SIZE.to_f }
  end
end
