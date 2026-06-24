/* global axios */
import ApiClient from './ApiClient';

class CrmIntegrationTokensAPI extends ApiClient {
  constructor() {
    super('crm/integration_tokens', { accountScoped: true });
  }

  // Lists token metadata only — the secret is never returned by index.
  get() {
    return axios.get(this.url);
  }

  // Reveal-once: the response includes `token` exactly once, on create.
  create({ name, scopes }) {
    return axios.post(this.url, { integration_token: { name, scopes } });
  }

  revoke(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Reveal-once: the response includes the new `token` exactly once, on rotate.
  rotate(id) {
    return axios.post(`${this.url}/${id}/rotate`);
  }
}

export default new CrmIntegrationTokensAPI();
