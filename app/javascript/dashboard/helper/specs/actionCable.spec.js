import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

global.chatwootConfig = {
  websocketURL: 'wss://test.chatwoot.com',
};

describe('ActionCableConnector - Copilot Tests', () => {
  let store;
  let actionCable;
  let mockDispatch;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    store = {
      $store: {
        dispatch: mockDispatch,
        getters: {
          getCurrentAccountId: 1,
          'accounts/isFeatureEnabledonAccount': vi.fn(() => true),
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });

  afterEach(() => {
    vi.useRealTimers();
  });
  describe('copilot event handlers', () => {
    it('should register the copilot.message.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'copilot.message.created'
      );
      expect(actionCable.events['copilot.message.created']).toBe(
        actionCable.onCopilotMessageCreated
      );
    });

    it('should handle the copilot.message.created event through the ActionCable system', () => {
      const copilotData = {
        id: 2,
        content: 'This is a copilot message from ActionCable',
        conversation_id: 456,
        created_at: '2025-05-27T15:58:04-06:00',
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'copilot.message.created',
        data: copilotData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'copilotMessages/upsert',
        copilotData
      );
    });
  });

  describe('conversation unread count event handlers', () => {
    it('should register the conversation.unread_count_changed event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'conversation.unread_count_changed'
      );
      expect(actionCable.events['conversation.unread_count_changed']).toBe(
        actionCable.onConversationUnreadCountChanged
      );
    });

    it('should refetch unread counts when unread count changes', () => {
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledWith('conversationUnreadCounts/get');
    });

    it('does not refetch unread counts when unread count feature is disabled', () => {
      store.$store.getters[
        'accounts/isFeatureEnabledonAccount'
      ].mockReturnValue(false);

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).not.toHaveBeenCalledWith(
        'conversationUnreadCounts/get'
      );
    });

    it('should throttle unread count refetches for repeated events', () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledTimes(1);

      vi.advanceTimersByTime(4999);
      expect(mockDispatch).toHaveBeenCalledTimes(1);

      vi.advanceTimersByTime(1);
      expect(mockDispatch).toHaveBeenCalledTimes(2);
      expect(mockDispatch).toHaveBeenLastCalledWith(
        'conversationUnreadCounts/get'
      );
    });

    it('clears pending unread count refetch before immediate refetch', () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      vi.advanceTimersByTime(1000);
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      vi.setSystemTime(new Date('2026-01-01T00:00:06Z'));
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledTimes(2);

      vi.advanceTimersByTime(4000);
      expect(mockDispatch).toHaveBeenCalledTimes(2);
    });
  });

  describe('crm kanban event handlers', () => {
    it('registers CRM card realtime events', () => {
      expect(Object.keys(actionCable.events)).toEqual(
        expect.arrayContaining([
          'crm.card.created',
          'crm.card.updated',
          'crm.card.moved',
          'crm.card.archived',
        ])
      );
    });

    it('dispatches valid CRM card events to the CRM Kanban store', () => {
      const card = {
        id: 77,
        account_id: 1,
        pipeline_id: 3,
        stage_id: 9,
        title: 'Lead realtime',
      };

      actionCable.onReceived({ event: 'crm.card.moved', data: card });

      expect(mockDispatch).toHaveBeenCalledWith(
        'crmKanban/handleRealtimeCardEvent',
        {
          event: 'crm.card.moved',
          card,
        }
      );
    });

    it('ignores CRM card events from another account', () => {
      actionCable.onReceived({
        event: 'crm.card.updated',
        data: { id: 77, account_id: 2 },
      });

      expect(mockDispatch).not.toHaveBeenCalledWith(
        'crmKanban/handleRealtimeCardEvent',
        expect.anything()
      );
    });
  });

  describe('crm ai usage event handlers', () => {
    it('registers and emits CRM AI usage realtime events', () => {
      const usage = {
        id: 9,
        account_id: 1,
        resource: 'Assistente de respostas',
        created_at: '2026-06-28T12:01:00Z',
        total_tokens: 90,
        cost_usd: 0.01,
      };

      expect(Object.keys(actionCable.events)).toContain('crm.ai_usage.created');

      actionCable.onReceived({
        event: 'crm.ai_usage.created',
        data: usage,
      });

      expect(emitter.emit).toHaveBeenCalledWith(
        BUS_EVENTS.CRM_AI_USAGE_CREATED,
        usage
      );
    });
  });
});
