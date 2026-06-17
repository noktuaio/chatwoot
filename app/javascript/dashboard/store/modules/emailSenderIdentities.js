import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import EmailSenderIdentitiesAPI from '../../api/emailSenderIdentities';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isChecking: false,
  },
};

export const getters = {
  getIdentities(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isFetching: true });
    try {
      const response = await EmailSenderIdentitiesAPI.get();
      commit(
        types.SET_EMAIL_SENDER_IDENTITIES,
        response.data.payload.sender_identities || []
      );
    } finally {
      commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, payload) => {
    commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isCreating: true });
    try {
      const response = await EmailSenderIdentitiesAPI.create({
        sender_identity: payload,
      });
      commit(types.ADD_EMAIL_SENDER_IDENTITY, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isCreating: false });
    }
  },
  verify: async ({ commit }, id) => {
    commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailSenderIdentitiesAPI.verify(id);
      commit(types.EDIT_EMAIL_SENDER_IDENTITY, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isDeleting: true });
    try {
      await EmailSenderIdentitiesAPI.delete(id);
      commit(types.DELETE_EMAIL_SENDER_IDENTITY, id);
    } finally {
      commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isDeleting: false });
    }
  },
  checkDns: async ({ commit }, id) => {
    commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isChecking: true });
    try {
      const response = await EmailSenderIdentitiesAPI.dnsCheck(id);
      return response.data;
    } finally {
      commit(types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG, { isChecking: false });
    }
  },
};

export const mutations = {
  [types.SET_EMAIL_SENDER_IDENTITY_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_EMAIL_SENDER_IDENTITIES]: MutationHelpers.set,
  [types.ADD_EMAIL_SENDER_IDENTITY]: MutationHelpers.create,
  [types.EDIT_EMAIL_SENDER_IDENTITY]: MutationHelpers.update,
  [types.DELETE_EMAIL_SENDER_IDENTITY]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
