/* global axios */
import ApiClient from './ApiClient';

// Conector WhatsApp API: provisiona a caixa + a conexão do número em uma chamada,
// e expõe a saúde + QR para a tela de Conexão.
class WahaInboxAPI extends ApiClient {
  constructor() {
    super('waha_inboxes', { accountScoped: true });
  }

  create({ phone, name, aiAgent }) {
    return axios.post(this.url, { phone, name, ai_agent: aiAgent });
  }

  connection(inboxId) {
    return axios.get(`${this.url}/${inboxId}/connection`);
  }

  reconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reconnect`);
  }
}

export default new WahaInboxAPI();
