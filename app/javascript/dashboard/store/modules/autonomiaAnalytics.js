import AutonomiaAgentsAPI from '../../api/autonomia/agents';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Performance analytics are a per-agent + per-range sub-resource (no records-by-id
// list), so this module is hand-rolled rather than using the CRUD factory. State
// holds the last loaded analytics payload and the selected range.
export const state = {
  record: null,
  range: '7d',
  uiFlags: { fetching: false, error: false },
};

export const getters = {
  getAnalytics: $s => $s.record,
  getRange: $s => $s.range,
  getUIFlags: $s => $s.uiFlags,
};

export const actions = {
  fetch: async ({ commit }, { agentId, range = '7d' }) => {
    commit('SET_UI_FLAG', { fetching: true, error: false });
    commit('SET_RANGE', range);
    try {
      const { data } = await AutonomiaAgentsAPI.analytics(agentId, { range });
      // Stamp the record with the agentId it belongs to so the panel can reject a
      // stale payload after switching agents (the analytics endpoint doesn't echo it).
      commit('SET', { ...data, agentId });
      return data;
    } catch (error) {
      commit('SET_UI_FLAG', { error: true });
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { fetching: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG: ($s, f) => {
    $s.uiFlags = { ...$s.uiFlags, ...f };
  },
  SET: ($s, record) => {
    $s.record = record;
  },
  SET_RANGE: ($s, range) => {
    $s.range = range;
  },
};

export default { namespaced: true, state, getters, actions, mutations };
