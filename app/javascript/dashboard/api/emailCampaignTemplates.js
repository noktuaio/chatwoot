/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignTemplatesAPI extends ApiClient {
  constructor() {
    super('email_campaigns/templates', { accountScoped: true });
  }

  index() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    return axios.post(this.url, { email_template: payload });
  }
}

export default new EmailCampaignTemplatesAPI();
