class ImportJsonFromGoogleSlidesService
  GOOGLE_SLIDES_PREFIX = "https://docs.google.com/presentation/d/"
  SCOPES = ["https://www.googleapis.com/auth/presentations.readonly"].freeze

  def initialize(url, directory)
    @url = url
    @directory = directory
  end

  def call
    raise ArgumentError, "URL must start with #{GOOGLE_SLIDES_PREFIX}" unless @url.start_with?(GOOGLE_SLIDES_PREFIX)
    raise ArgumentError, "Directory not found: #{@directory}" unless Dir.exist?(@directory)

    presentation = slides_service.get_presentation(presentation_id)

    slides = presentation.slides.map do |slide|
      page_id = slide.object_id_prop
      {
        object_id:     page_id,
        speaker_notes: extract_speaker_notes(slide),
        thumbnail_url: fetch_thumbnail_url(page_id)
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
end
