import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import WhatsappApiCampaignsAPI from '../../api/whatsappApiCampaigns';

export const state = {
  records: [],
  meta: {
    count: 0,
    currentPage: 1,
  },
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getCampaigns(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
};

const updateCampaign = (commit, response) => {
  commit(types.EDIT_WHATSAPP_API_CAMPAIGN, response.data.payload);
  return response.data.payload;
};

export const actions = {
  get: async ({ commit }, { page = 1, silent = false } = {}) => {
    if (!silent)
      commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isFetching: true });
    try {
      const response = await WhatsappApiCampaignsAPI.get(page);
      commit(types.SET_WHATSAPP_API_CAMPAIGNS, response.data.payload || []);
      commit(types.SET_WHATSAPP_API_CAMPAIGN_META, response.data.meta || {});
    } finally {
      if (!silent)
        commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, payload) => {
    commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isCreating: true });
    try {
      const response = await WhatsappApiCampaignsAPI.createCampaign(payload);
      commit(types.ADD_WHATSAPP_API_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isCreating: false });
    }
  },
  pause: async ({ commit }, id) => {
    commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      return updateCampaign(commit, await WhatsappApiCampaignsAPI.pause(id));
    } finally {
      commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  resume: async ({ commit }, id) => {
    commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      return updateCampaign(commit, await WhatsappApiCampaignsAPI.resume(id));
    } finally {
      commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  cancel: async ({ commit }, id) => {
    commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      return updateCampaign(commit, await WhatsappApiCampaignsAPI.cancel(id));
    } finally {
      commit(types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
};

export const mutations = {
  [types.SET_WHATSAPP_API_CAMPAIGN_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_WHATSAPP_API_CAMPAIGN_META](_state, data) {
    _state.meta = {
      ..._state.meta,
      ...data,
    };
  },
  [types.ADD_WHATSAPP_API_CAMPAIGN]: MutationHelpers.create,
  [types.SET_WHATSAPP_API_CAMPAIGNS]: MutationHelpers.set,
  [types.EDIT_WHATSAPP_API_CAMPAIGN]: MutationHelpers.update,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
