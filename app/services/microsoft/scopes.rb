module Microsoft
  # No Azure v2 cada TOKEN é de UM recurso só. O consentimento (authorize) pode ser
  # misto, mas ao redimir/atualizar token é preciso pedir o escopo de um recurso.
  # - IMAP: recurso outlook.office.com (entrada) — inclui openid/profile/email p/ id_token.
  # - GRAPH: recurso graph.microsoft.com (envio /sendMail).
  module Scopes
    IMAP = 'openid profile email offline_access https://outlook.office.com/IMAP.AccessAsUser.All'.freeze
    GRAPH = 'https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/Mail.ReadWrite offline_access'.freeze
    GRAPH_WITH_CALENDAR = "#{GRAPH} https://graph.microsoft.com/Calendars.ReadWrite".freeze
  end
end
