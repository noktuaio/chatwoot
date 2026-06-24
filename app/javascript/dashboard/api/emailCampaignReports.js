/* global axios */
import ApiClient from './ApiClient';

class EmailCampaignReportsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/reports', { accountScoped: true });
  }

  getReports(campaignId) {
    const query = campaignId ? `?campaign_id=${campaignId}` : '';
    return axios.get(`${this.url}${query}`);
  }

  getCampaignDetail(id) {
    return axios.get(`${this.url}/${id}`);
  }

  getClicks(id) {
    return axios.get(`${this.url}/${id}/clicks`);
  }

  getTimeline(id, interval = 'day') {
    return axios.get(`${this.url}/${id}/timeline`, { params: { interval } });
  }

  getRecipients(id, { page = 1, search = '' } = {}) {
    return axios.get(`${this.url}/${id}/recipients`, {
      params: { page, q: search },
    });
  }

  export(id) {
    return axios.get(`${this.url}/${id}/export`, { responseType: 'blob' });
  }
}

export default new EmailCampaignReportsAPI();
