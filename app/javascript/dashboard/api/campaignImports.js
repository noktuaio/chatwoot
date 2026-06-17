/* global axios */
import ApiClient from './ApiClient';

class CampaignImportsAPI extends ApiClient {
  constructor() {
    super('campaign_imports', { accountScoped: true });
  }

  get(page = 1) {
    return axios.get(`${this.url}?page=${page}`);
  }

  createImport({ file, campaignName, batchCount }) {
    const formData = new FormData();
    formData.append('import_file', file);
    formData.append('campaign_name', campaignName);
    formData.append('batch_count', batchCount);

    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  confirm(id) {
    return axios.post(`${this.url}/${id}/confirm`);
  }

  undoLabels(id) {
    return axios.post(`${this.url}/${id}/undo_labels`);
  }

  deleteImport(id) {
    return this.delete(id);
  }

  download(id, file) {
    return axios.get(`${this.url}/${id}/download?file=${file}`, {
      responseType: 'blob',
    });
  }
}

export default new CampaignImportsAPI();
