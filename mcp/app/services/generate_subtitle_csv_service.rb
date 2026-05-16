class GenerateSubtitleCsvService
  def initialize(dir, lines)
    @dir = dir
    @lines = lines
  end

  def call
    raise "Directory not found: #{@dir}" unless Dir.exist?(@dir)

    output_path = File.join(@dir, "subtitle.csv")
    content = @lines.map { |l| "#{l["speaker"]},#{l["text"]}" }.join("\n")
    File.write(output_path, content)

    output_path
  end
end
