/* global axios */
import ApiClient from '../ApiClient';

class EnterpriseAccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true, enterprise: true });
  }

  checkout() {
    return axios.post(`${this.url}checkout`);
  }

  subscription() {
    return axios.post(`${this.url}subscription`);
  }

  getLimits() {
    return axios.get(`${this.url}limits`);
  }

  toggleDeletion(action) {
    return axios.post(`${this.url}toggle_deletion`, {
      action_type: action,
    });
  }

  createTopupCheckout(credits) {
    return axios.post(`${this.url}topup_checkout`, { credits });
  }

  // Returns { currency, options: [{ credits, amount, currency }] } for the
  // account's billing currency, sourced from CHATWOOT_CLOUD_TOPUP_OPTIONS.
  getTopupOptions() {
    return axios.get(`${this.url}topup_options`);
  }
}

export default new EnterpriseAccountAPI();
