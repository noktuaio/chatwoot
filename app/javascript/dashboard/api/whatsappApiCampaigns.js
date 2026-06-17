/* global axios */
import ApiClient from './ApiClient';

class WhatsappApiCampaignsAPI extends ApiClient {
  constructor() {
    super('whatsapp_api_campaigns', { accountScoped: true });
  }

  get(page = 1) {
    return axios.get(`${this.url}?page=${page}`);
  }

  createCampaign(payload) {
    const formData = new FormData();
    formData.append('title', payload.title);
    formData.append('inbox_id', payload.inboxId);
    formData.append('message_body', payload.messageBody || '');
    formData.append('scheduled_at', payload.scheduledAt);
    formData.append('audience', JSON.stringify(payload.audience || []));
    if (payload.templateId) formData.append('template_id', payload.templateId);
    if (payload.mediaFile) formData.append('media_file', payload.mediaFile);

    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }
}

export default new WhatsappApiCampaignsAPI();
