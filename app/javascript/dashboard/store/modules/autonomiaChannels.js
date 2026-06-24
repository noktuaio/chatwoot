import AutonomiaChannelsAPI from '../../api/autonomia/channels';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Per-agent channel connections. `fetch` returns both the connected inboxes and
// the eligible ones (each inbox can host only one agent), kept as two lists so
// the Channels tab can render connect/disconnect affordances directly.
export const state = {
  connected: [],
  eligible: [],
  uiFlags: {
    fetching: false,
    connecting: false,
    disconnecting: false,
  },
};

export const getters = {
  getConnected($state) {
    return $state.connected;
  },
  getEligible($state) {
    return $state.eligible;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  fetch: async ({ commit }, { agentId }) => {
    commit('SET_UI_FLAG', { fetching: true });
    try {
      const { data } = await AutonomiaChannelsAPI.get(agentId);
      // Backend shape: `payload` is the array of connected agent-inboxes, and
      // `eligible_inboxes` is a sibling key with the connectable inboxes.
      commit('SET_CHANNELS', {
        connected: data.payload || [],
        eligible: data.eligible_inboxes || [],
      });
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { fetching: false });
    }
  },

  connect: async ({ commit, dispatch }, { agentId, inboxId }) => {
    commit('SET_UI_FLAG', { connecting: true });
    try {
      const { data } = await AutonomiaChannelsAPI.connect(agentId, inboxId);
      // Re-sync from server truth: a connect moves the inbox between the
      // eligible and connected lists and may free/occupy others.
      await dispatch('fetch', { agentId });
      return data.payload || data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { connecting: false });
    }
  },

  disconnect: async ({ commit, dispatch }, { agentId, inboxId }) => {
    commit('SET_UI_FLAG', { disconnecting: true });
    try {
      await AutonomiaChannelsAPI.disconnect(agentId, inboxId);
      await dispatch('fetch', { agentId });
      return inboxId;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { disconnecting: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  SET_CHANNELS($state, { connected, eligible }) {
    $state.connected = connected || [];
    $state.eligible = eligible || [];
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
