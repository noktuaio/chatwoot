# Serves the public, server-rendered HTML shell for the Calendly-style booking
# page at /book/:slug (mirrors Survey::ResponsesController). NO authentication —
# inherits ActionController::Base directly. The Vue app (entrypoint 'public_booking')
# resolves the profile + slots over the Public::Api::V1 JSON endpoints using only
# the opaque slug. We do NOT 404 here on an unknown/disabled slug: the Vue app shows
# a branded-neutral "not found" state via the JSON 404, keeping the HTML shell
# cacheable and leaking nothing.
class PublicBooking::PagesController < ActionController::Base
  before_action :set_global_config

  def show; end

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'INSTALLATION_NAME')
  end
end
