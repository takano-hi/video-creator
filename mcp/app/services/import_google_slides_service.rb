class ImportGoogleSlidesService
  GOOGLE_SLIDES_PREFIX = "https://docs.google.com/presentation/d/"
  SCOPES = ["https://www.googleapis.com/auth/presentations.readonly"].freeze

  def initialize(url, directory)
    @url = url
    @directory = directory
  end

  def call
    raise ArgumentError, "URL must start with #{GOOGLE_SLIDES_PREFIX}" unless @url.start_with?(GOOGLE_SLIDES_PREFIX)
    raise ArgumentError, "Directory not found: #{@directory}" unless Dir.exist?(@directory)

    slides_dir = File.join(@directory, "slides")
    Dir.mkdir(slides_dir) unless Dir.exist?(slides_dir)

    presentation = slides_service.get_presentation(presentation_id)

    slides = presentation.slides.each_with_index.map do |slide, i|
      page_id = slide.object_id_prop
      thumbnail_url = fetch_thumbnail_url(page_id)
      thumbnail = download_thumbnail(thumbnail_url, i + 1, slides_dir)
      {
        object_id:     page_id,
        speaker_notes: extract_speaker_notes(slide),
        thumbnail:     thumbnail
      }
    end

    output_path = File.join(@directory, "google-slides.json")
    File.write(output_path, JSON.pretty_generate(slides))
    output_path
  end

  private

  def presentation_id
    @presentation_id ||= @url.delete_prefix(GOOGLE_SLIDES_PREFIX).split("/").first
  end

  def slides_service
    @slides_service ||= begin
      json = ENV.fetch("GOOGLE_SERVICE_ACCOUNT_JSON")
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(json),
        scope: SCOPES
      )
      service = Google::Apis::SlidesV1::SlidesService.new
      service.authorization = credentials
      service
    end
  end

  def extract_speaker_notes(slide)
    notes_page = slide.slide_properties&.notes_page
    return nil unless notes_page

    notes_body = notes_page.page_elements&.find do |el|
      el.shape&.placeholder&.type == "BODY"
    end
    return nil unless notes_body&.shape&.text

    lines = notes_body.shape.text.text_elements
      .filter_map { |te| te.text_run&.content }
      .join
      .split("\n")
      .map(&:strip)
      .reject(&:empty?)

    return nil if lines.empty?

    lines.map do |line|
      if (m = line.match(/\A\{(.+?)\}(.*)\z/))
        { speaker: m[1], statement: m[2].strip }
      else
        { speaker: nil, statement: line }
      end
    end
  end

  def fetch_thumbnail_url(page_object_id)
    thumbnail = slides_service.get_presentation_page_thumbnail(presentation_id, page_object_id)
    thumbnail.content_url
  end

  def download_thumbnail(url, index, slides_dir)
    uri = URI.parse(url)
    response = http_get_with_redirect(uri)

    content_type = response["Content-Type"].to_s.split(";").first.strip
    ext = File.extname(uri.path).presence || ".#{content_type.split('/').last}"
    filename = "#{index.to_s.rjust(3, '0')}#{ext}"

    File.binwrite(File.join(slides_dir, filename), response.body)
    File.join("slides", filename)
  end

  def http_get_with_redirect(uri, limit = 5)
    raise "Too many redirects" if limit == 0

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.get(uri.request_uri)
    end

    if response.is_a?(Net::HTTPRedirection)
      location = URI.parse(response["Location"])
      location = uri + location if location.relative?
      http_get_with_redirect(location, limit - 1)
    else
      response
    end
  end
end
