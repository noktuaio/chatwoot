import AutonomiaAgentsAPI from '../../api/autonomia/agents';
import { createStore, generateMutationTypes } from '../storeFactory';

// Mirror the mutation names the factory generates for this store so a custom
// action can commit into the same records list (UPSERT) the CRUD actions use.
const mutationTypes = generateMutationTypes('AutonomiaAgents');

export default createStore({
  name: 'AutonomiaAgents',
  API: AutonomiaAgentsAPI,
  actions: () => ({
    // Sandbox test of a draft/live agent. Returns the full evaluation
    // ({ reply, confidence, handoff, used_knowledge }) for the Test tab to
    // render; it is transient (not persisted to the records list).
    async test(_, { agentId, message, history = [], images = [] }) {
      const { data } = await AutonomiaAgentsAPI.test(agentId, {
        message,
        history,
        images,
      });
      return data;
    },

    // Same shape as `test`, used to suggest a reply to a human agent.
    async suggest(_, { agentId, message, history = [] }) {
      const { data } = await AutonomiaAgentsAPI.suggest(agentId, {
        message,
        history,
      });
      return data;
    },

    // Commit an agent produced elsewhere (e.g. when a Builder thread becomes
    // `ready` and returns the generated agent) into the records list so the hub
    // and panel see it without a refetch.
    upsert({ commit }, agent) {
      if (agent?.id) commit(mutationTypes.UPSERT, agent);
    },
  }),
});
