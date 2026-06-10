// Single source of truth for IDB-cached workspace config.
//
// Each entry must keep `name` equal to the Rails `Model.name.underscore` value
// so the server's `cache_keys` payload (and the IDB object store name) lines up
// with what the client looks up.
//
// `setMutation` is the full commit path used to seed Vuex from IDB (boot
// paint) and to swap in refetched rows (event-driven revalidation). Every
// SET_* mutation must REPLACE its records (not merge) so rows deleted
// server-side never survive as phantoms.
export const cacheableModels = [
  { name: 'inbox', setMutation: 'inboxes/SET_INBOXES' },
  { name: 'label', setMutation: 'labels/SET_LABELS' },
  { name: 'team', setMutation: 'teams/SET_TEAMS' },
  { name: 'canned_response', setMutation: 'SET_CANNED' },
  { name: 'account_user', setMutation: 'agents/SET_AGENTS' },
  {
    name: 'custom_attribute_definition',
    setMutation: 'attributes/SET_CUSTOM_ATTRIBUTE',
  },
];

export const cacheableModelNames = cacheableModels.map(model => model.name);
