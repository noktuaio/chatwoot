/* global axios */
import ApiClient from './ApiClient';

// Guia da Plataforma — onboarding/suporte read-only, global (gated server-side by the account's
// Autonomia eligibility = ENV master + the Kanban AI key).
class AutonomiaGuideAPI extends ApiClient {
  constructor() {
    super('autonomia/guide', { accountScoped: true });
  }

  // history: [{ role: 'user' | 'assistant', content }]
  // routeContext: the current route name (so the guide knows where the user is).
  chat({ message, history, routeContext } = {}) {
    return axios.post(`${this.url}/chat`, {
      message,
      history,
      route_context: routeContext,
    });
  }
}

export default new AutonomiaGuideAPI();
