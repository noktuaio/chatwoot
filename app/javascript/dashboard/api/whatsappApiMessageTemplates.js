/* global axios */
import ApiClient from './ApiClient';

class WhatsappApiMessageTemplatesAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  templatesUrl(inboxId) {
    return `${this.url}/${inboxId}/whatsapp_api_message_templates`;
  }

  getTemplates(inboxId) {
    return axios.get(this.templatesUrl(inboxId));
  }

  get(inboxId) {
    return axios.get(this.templatesUrl(inboxId));
  }

  create(inboxId, template) {
    return axios.post(this.templatesUrl(inboxId), { template });
  }

  update(inboxId, id, template) {
    return axios.patch(`${this.templatesUrl(inboxId)}/${id}`, { template });
  }

  delete(inboxId, id) {
    return axios.delete(`${this.templatesUrl(inboxId)}/${id}`);
  }
}

export default new WhatsappApiMessageTemplatesAPI();
