require 'net/http'

module EmailCampaigns
  # Resolves a video reference (YouTube/Vimeo URL or an uploaded video blob) into the data the
  # email builder needs: provider, canonical watch/video URL, a poster image URL and a ready-to-use
  # email-safe MJML block (mj-image poster + href, no <video>/iframe).
  #
  # SSRF: external URLs are only accepted for YouTube/Vimeo hosts. Uploaded videos come exclusively
  # from a signed_id of a blob attached to the campaign (the caller resolves/authorizes the blob).
  #
  # gem-free: uses Net::HTTP for the Vimeo oEmbed lookup.
  class VideoAsset
    class Error < StandardError; end

    # Covers watch / youtu.be / embed / shorts / live / v. YouTube ids are always 11 chars.
    YOUTUBE_ID = %r{
      (?:youtube\.com/(?:watch\?(?:.*&)?v=|embed/|shorts/|live/|v/)|youtu\.be/)
      ([A-Za-z0-9_-]{11})
    }x
    VIMEO_ID = %r{vimeo\.com/(?:video/)?(\d+)}
    YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com youtu.be].freeze
    VIMEO_HOSTS = %w[vimeo.com www.vimeo.com player.vimeo.com].freeze
    VIMEO_OEMBED = 'https://vimeo.com/api/oembed.json'.freeze
    USER_AGENT = 'Mozilla/5.0'.freeze
    # oEmbed lookup is synchronous and runs inside the request/worker; keep it short and cache by id.
    VIMEO_HTTP_TIMEOUT = 4
    VIMEO_CACHE_TTL = 12.hours
    # Only clean http(s) URLs (no quotes/whitespace) are allowed inside MJML attributes.
    SAFE_URL = %r{\Ahttps?://[^\s"'<>]+\z}

    # Generic 16:9 dark poster with a play glyph; used when an upload has no user poster and we
    # cannot extract a frame (no ffmpeg in prod). The FE shows a "needs_poster" warning.
    PLACEHOLDER_POSTER =
      'data:image/svg+xml;utf8,' + ERB::Util.url_encode(<<~SVG.squish)
        <svg xmlns="http://www.w3.org/2000/svg" width="600" height="338" viewBox="0 0 600 338">
          <rect width="600" height="338" fill="#111111"/>
          <circle cx="300" cy="169" r="48" fill="rgba(255,255,255,0.15)"/>
          <polygon points="285,145 285,193 325,169" fill="#ffffff"/>
        </svg>
      SVG

    # result = { provider:, video_url:, poster_url:, mjml_block:, needs_poster: }
    def self.from_url(url)
      new.resolve_url(url)
    end

    # poster_url is optional and must already be a server-resolved asset URL. When an upload has no
    # poster we fall back to the server-owned placeholder.
    def self.from_upload(video_url:, poster_url: nil)
      new.resolve_upload(video_url: video_url, poster_url: poster_url)
    end

    def resolve_url(url)
      url = url.to_s.strip
      raise Error, 'video_url_blank' if url.empty?

      host = uri_host(url)
      if youtube_host?(host)
        resolve_youtube(url)
      elsif vimeo_host?(host)
        resolve_vimeo(url)
      else
        raise Error, 'video_host_not_allowed'
      end
    end

    def resolve_upload(video_url:, poster_url: nil)
      raise Error, 'video_url_blank' if video_url.to_s.strip.empty?
      raise Error, 'video_poster_unsafe' if poster_url.to_s.strip.start_with?('data:')

      needs_poster = poster_url.blank?
      poster = poster_url.presence || PLACEHOLDER_POSTER
      build(provider: 'upload', video_url: video_url, poster_url: poster, needs_poster: needs_poster)
    end

    private

    def resolve_youtube(url)
      id = url[YOUTUBE_ID, 1]
      raise Error, 'video_id_not_found' if id.nil?

      watch_url = "https://www.youtube.com/watch?v=#{id}"
      poster = "https://img.youtube.com/vi/#{id}/hqdefault.jpg"
      build(provider: 'youtube', video_url: watch_url, poster_url: poster, needs_poster: false)
    end

    def resolve_vimeo(url)
      id = url[VIMEO_ID, 1]
      raise Error, 'video_id_not_found' if id.nil?

      data = vimeo_oembed(id, url)
      poster = data['thumbnail_url_with_play_button'].presence || data['thumbnail_url']
      raise Error, 'video_poster_unavailable' if poster.blank?

      build(provider: 'vimeo', video_url: "https://vimeo.com/#{id}", poster_url: poster, needs_poster: false)
    end

    # Cached by video id (poster URLs are stable) so we hit Vimeo at most once per id per TTL,
    # keeping the worker fast even on repeat resolves.
    def vimeo_oembed(id, url)
      Rails.cache.fetch("email_campaigns/vimeo_oembed/#{id}", expires_in: VIMEO_CACHE_TTL) do
        fetch_vimeo_oembed(url)
      end
    end

    def fetch_vimeo_oembed(url)
      endpoint = URI("#{VIMEO_OEMBED}?url=#{ERB::Util.url_encode(url)}")
      request = Net::HTTP::Get.new(endpoint)
      request['User-Agent'] = USER_AGENT
      response = Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: true,
                                 open_timeout: VIMEO_HTTP_TIMEOUT, read_timeout: VIMEO_HTTP_TIMEOUT) do |http|
        http.request(request)
      end
      raise Error, 'video_oembed_failed' unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, Net::OpenTimeout, Net::ReadTimeout
      raise Error, 'video_oembed_failed'
    end

    # Canonical email-safe block: poster image linked to the video (no <video>/iframe).
    def build(provider:, video_url:, poster_url:, needs_poster:)
      {
        provider: provider,
        video_url: video_url,
        poster_url: poster_url,
        needs_poster: needs_poster,
        mjml_block: mjml_block(video_url: video_url, poster_url: poster_url)
      }
    end

    def mjml_block(video_url:, poster_url:)
      src = safe_attr_url(poster_url, allow_data: poster_url == PLACEHOLDER_POSTER)
      href = safe_attr_url(video_url)
      <<~MJML.strip
        <mj-section background-color="#000000" padding="0" css-class="video-block">
          <mj-column>
            <mj-image src="#{src}" href="#{href}" alt="Assistir ao vídeo" padding="0" />
          </mj-column>
        </mj-section>
      MJML
    end

    # Accepts only clean http(s) URLs; the only data: URI allowed is the server-owned placeholder.
    def safe_attr_url(url, allow_data: false)
      url = url.to_s
      raise Error, 'video_url_unsafe' unless (allow_data && url.start_with?('data:')) || url.match?(SAFE_URL)

      ERB::Util.html_escape(url)
    end

    def uri_host(url)
      URI.parse(url).host.to_s.downcase
    rescue URI::InvalidURIError
      ''
    end

    def youtube_host?(host)
      YOUTUBE_HOSTS.include?(host)
    end

    def vimeo_host?(host)
      VIMEO_HOSTS.include?(host)
    end
  end
end
