export const CRM_VIEW_PERMISSION = 'crm_view';
export const CRM_MANAGE_CARDS_PERMISSION = 'crm_manage_cards';
export const CRM_MOVE_CARDS_PERMISSION = 'crm_move_cards';
export const CRM_MANAGE_PIPELINES_PERMISSION = 'crm_manage_pipelines';
export const CRM_MANAGE_AI_PERMISSION = 'crm_manage_ai';
export const CRM_VIEW_REPORTS_PERMISSION = 'crm_view_reports';
export const CRM_ADMIN_PERMISSION = 'crm_admin';

export const CRM_PERMISSIONS = [
  CRM_VIEW_PERMISSION,
  CRM_MANAGE_CARDS_PERMISSION,
  CRM_MOVE_CARDS_PERMISSION,
  CRM_MANAGE_PIPELINES_PERMISSION,
  CRM_MANAGE_AI_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
  CRM_ADMIN_PERMISSION,
];

export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
  ...CRM_PERMISSIONS,
];

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};
