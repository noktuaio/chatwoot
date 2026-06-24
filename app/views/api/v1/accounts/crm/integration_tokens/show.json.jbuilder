json.partial! 'integration_token', integration_token: @integration_token
# Reveal-once: @reveal_token is set only on create/rotate. It is the single moment
# the plaintext secret is exposed; index/show-of-existing never include it.
json.token @reveal_token if @reveal_token.present?
