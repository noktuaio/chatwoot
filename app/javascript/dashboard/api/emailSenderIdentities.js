/* global axios */
import ApiClient from './ApiClient';

class EmailSenderIdentitiesAPI extends ApiClient {
  constructor() {
    super('email_campaigns/sender_identities', { accountScoped: true });
  }

  verify(id) {
    return axios.post(`${this.url}/${id}/verify`);
  }

  dnsCheck(id) {
    return axios.post(`${this.url}/${id}/dns_check`);
  }
}

export default new EmailSenderIdentitiesAPI();
