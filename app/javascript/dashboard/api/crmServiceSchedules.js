import ApiClient from './ApiClient';

// CRUD for /api/v1/accounts/:accountId/crm/service_schedules.
// Inherited: get(), create(data), update(id, data), delete(id).
// Payload wrapper: { service_schedule: { owner_type, owner_id, timezone, enabled, blocks } }
// where blocks = [{ day_of_week: 0..6, start_minute, end_minute }].
class CrmServiceSchedulesAPI extends ApiClient {
  constructor() {
    super('crm/service_schedules', { accountScoped: true });
  }
}

export default new CrmServiceSchedulesAPI();
