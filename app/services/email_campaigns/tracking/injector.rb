module EmailCampaigns
  module Tracking
    # Rewrites http/https hrefs to the signed click-redirect URL and appends a 1x1 open pixel.
    # Skips mailto:/tel:/#anchor/relative and already-tracked links. Idempotent (a second pass
    # is a no-op: rewritten hrefs already point at the tracking base_url; the pixel is appended
    # once, guarded by PIXEL_MARKER).
    class Injector
      PIXEL_MARKER = 'data-ec-pixel'.freeze

      def initialize(recipient, html)
        @recipient = recipient
        @html = html.to_s
      end

      def perform
        return @html if @html.blank?

        body = rewrite_hrefs(@html)
        append_pixel(body)
      end

      private

      def rewrite_hrefs(html)
        html.gsub(/href\s*=\s*("|')(.*?)\1/i) do
          quote = Regexp.last_match(1)
          url = Regexp.last_match(2)
          "href=#{quote}#{rewritten(url)}#{quote}"
        end
      end

      def rewritten(url)
        return url unless trackable?(url)

        EmailCampaigns::Tracking::Token.click_url(@recipient, url)
      end

      def trackable?(url)
        return false if url.blank?
        return false unless url =~ %r{\Ahttps?://}i
        return false if url.start_with?(EmailCampaigns::Tracking::Token.base_url) # already tracked

        true
      end

      def append_pixel(html)
        return html if html.include?(PIXEL_MARKER)

        pixel = %(<img #{PIXEL_MARKER}="1" src="#{EmailCampaigns::Tracking::Token.open_url(@recipient)}" ) +
                %(width="1" height="1" alt="" style="display:none" />)
        if html =~ %r{</body>}i
          html.sub(%r{</body>}i, "#{pixel}</body>")
        else
          html + pixel
        end
      end
    end
  end
end
