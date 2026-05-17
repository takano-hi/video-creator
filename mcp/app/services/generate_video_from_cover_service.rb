class GenerateVideoFromCoverService
  def initialize(dir)
    @dir  = dir
    @base = GenerateVideoBaseService.new(dir)
  end

  def call
    validate_inputs!

    wav_files = Dir.glob(File.join(@dir, "*.wav")).sort

    clear_outputs
    @base.merge_audio_files(wav_files)

    subtitles = @base.parse_subtitles(wav_files)
    @base.write_ass_subtitle(subtitles)
    @base.write_srt_subtitle(subtitles)

    assemble_video

    File.join(@dir, "video.mp4")
  end

  private

  def validate_inputs!
    raise "Directory not found: #{@dir}" unless Dir.exist?(@dir)
    raise "cover.png not found in #{@dir}" unless File.exist?(File.join(@dir, "cover.png"))
    raise "subtitle.csv not found in #{@dir}" unless File.exist?(File.join(@dir, "subtitle.csv"))
    raise "No .wav files found in #{@dir}" if Dir.glob(File.join(@dir, "*.wav")).empty?
  end

  def clear_outputs
    %w[merged.mp3 subtitle.ass subtitle.srt video.mp4].each do |f|
      path = File.join(@dir, f)
      File.delete(path) if File.exist?(path)
    end
  end

  def assemble_video
    cover    = Shellwords.escape(File.join(@dir, "cover.png"))
    audio    = Shellwords.escape(File.join(@dir, "merged.mp3"))
    subtitle = File.join(@dir, "subtitle.ass")
    output   = Shellwords.escape(File.join(@dir, "video.mp4"))

    system("ffmpeg -loop 1 -i #{cover} -i #{audio} -vf \"ass=#{subtitle}\" " \
           "-c:v libx264 -tune stillimage -c:a aac -b:a 192k -shortest -pix_fmt yuv420p #{output}")
  end
end
