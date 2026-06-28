/* global axios */
import ApiClient from './ApiClient';

class CrmAiUsageAPI extends ApiClient {
  constructor() {
    super('crm/ai_usage', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  export(params = {}) {
    return axios.get(`${this.url}/export`, {
      params,
      responseType: 'blob',
    });
  }
}

export default new CrmAiUsageAPI();
