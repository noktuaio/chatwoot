import crmAiUsage from '../crmAiUsage';
import ApiClient from '../ApiClient';

describe('#CrmAiUsageAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/crm/ai-usage');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('creates correct instance', () => {
    expect(crmAiUsage).toBeInstanceOf(ApiClient);
    expect(crmAiUsage).toHaveProperty('get');
    expect(crmAiUsage).toHaveProperty('export');
  });

  it('fetches AI usage with account scope and params', () => {
    const params = {
      since: '2026-06-21T00:00:00.000Z',
      until: '2026-06-28T12:00:00.000Z',
      group_by: 'day',
    };

    crmAiUsage.get(params);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/ai_usage',
      { params }
    );
  });

  it('exports AI usage as a blob', () => {
    const params = { export_format: 'csv' };

    crmAiUsage.export(params);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/ai_usage/export',
      { params, responseType: 'blob' }
    );
  });
});
