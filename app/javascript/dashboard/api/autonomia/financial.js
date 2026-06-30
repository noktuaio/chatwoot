/* global axios */
import ApiClient from '../ApiClient';

class AutonomiaFinancialAPI extends ApiClient {
  constructor() {
    super('autonomia/financial', { accountScoped: true });
  }

  subscription() {
    return axios.get(`${this.url}/subscription`);
  }

  billingPreview() {
    return axios.get(`${this.url}/billing_preview`);
  }

  invoices() {
    return axios.get(`${this.url}/invoices`);
  }

  payments() {
    return axios.get(`${this.url}/payments`);
  }
}

export default new AutonomiaFinancialAPI();
