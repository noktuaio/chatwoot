/* global axios */
import ApiClient from '../ApiClient';

class AutonomiaAgentsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  // CRUD (get/show/create/update/delete) inherited from ApiClient.

  // `images` (optional) are base64 data-urls read inline by the model in this
  // turn only (multimodal). Empty/absent → identical to the text-only request.
  test(agentId, { message, history, images = [] }) {
    return axios.post(`${this.url}/${agentId}/test`, {
      message,
      history,
      images,
    });
  }

  updateAvatar(agentId, avatar) {
    const formData = new FormData();
    formData.append('avatar', avatar);
    return axios.patch(`${this.url}/${agentId}/avatar`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteAvatar(agentId) {
    return axios.delete(`${this.url}/${agentId}/avatar`);
  }

  suggest(agentId, { message, history }) {
    return axios.post(`${this.url}/${agentId}/suggest`, { message, history });
  }

  analytics(agentId, { range = '7d' } = {}) {
    return axios.get(`${this.url}/${agentId}/analytics`, { params: { range } });
  }
}

export default new AutonomiaAgentsAPI();
