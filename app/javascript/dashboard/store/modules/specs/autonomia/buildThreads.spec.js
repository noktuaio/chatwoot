import { actions, mutations } from '../../autonomiaBuildThreads';
import AutonomiaBuildThreadsAPI from '../../../../api/autonomia/buildThreads';

vi.mock('../../../../api/autonomia/buildThreads', () => ({
  default: {
    create: vi.fn(),
    show: vi.fn(),
    sendMessage: vi.fn(),
  },
}));

describe('#autonomiaBuildThreads store', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    actions.stopPolling();
  });

  describe('actions', () => {
    it('start opens a thread and maps the enveloped payload into the tracked slices', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.create.mockResolvedValue({
        data: {
          payload: {
            id: 3,
            agent_id: null,
            status: 'processing',
            state: 'next_question',
            messages: [{ role: 'assistant', content: 'Qual o objetivo?' }],
          },
        },
      });

      const payload = await actions.start(
        { commit, dispatch },
        { message: 'quero um agente de suporte' }
      );

      expect(AutonomiaBuildThreadsAPI.create).toHaveBeenCalledWith({
        agentId: undefined,
        message: 'quero um agente de suporte',
      });
      expect(commit).toHaveBeenCalledWith('SET_UI_FLAG', { creating: true });
      expect(commit).toHaveBeenCalledWith('SET_THREAD', {
        id: 3,
        agent_id: null,
      });
      expect(commit).toHaveBeenCalledWith('SET_STATUS', 'processing');
      expect(commit).toHaveBeenCalledWith('SET_THREAD_STATE', 'next_question');
      expect(commit).toHaveBeenCalledWith('MERGE_MESSAGES', [
        { role: 'assistant', content: 'Qual o objetivo?' },
      ]);
      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'user',
        content: 'quero um agente de suporte',
      });
      expect(dispatch).toHaveBeenCalledWith('poll', { threadId: 3 });
      expect(commit).toHaveBeenLastCalledWith('SET_UI_FLAG', {
        creating: false,
      });
      expect(payload.id).toBe(3);
    });

    it('send posts the follow-up message, echoes the user turn and re-polls', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();
      AutonomiaBuildThreadsAPI.sendMessage.mockResolvedValue({
        data: { payload: { id: 3, status: 'processing' } },
      });

      await actions.send({ commit, dispatch }, { threadId: 3, content: 'b2b' });

      expect(AutonomiaBuildThreadsAPI.sendMessage).toHaveBeenCalledWith(
        3,
        'b2b',
        {}
      );
      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'user',
        content: 'b2b',
      });
      expect(dispatch).toHaveBeenCalledWith('poll', { threadId: 3 });
    });

    it('declareNoMaterials sends a silent gate signal with no_materials', () => {
      const dispatch = vi.fn();

      actions.declareNoMaterials(
        { dispatch },
        { threadId: 3, content: 'sem materiais' }
      );

      expect(dispatch).toHaveBeenCalledWith('send', {
        threadId: 3,
        content: 'sem materiais',
        extra: { no_materials: true },
        echo: false,
      });
    });

    it('completeMaterials sends a silent gate signal to close the instruction', () => {
      const dispatch = vi.fn();

      actions.completeMaterials(
        { dispatch },
        { threadId: 3, content: 'materiais prontos' }
      );

      expect(dispatch).toHaveBeenCalledWith('send', {
        threadId: 3,
        content: 'materiais prontos',
        echo: false,
        extra: { force_close: true },
      });
    });

    it('onSettled continues the interview when ready + needs_more_info', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();

      await actions.onSettled(
        { commit, dispatch },
        {
          status: 'ready',
          agent_id: null,
          state: { needs_more_info: true, next_question: 'Qual o tom de voz?' },
        }
      );

      expect(commit).toHaveBeenCalledWith('APPEND_MESSAGE', {
        role: 'assistant',
        content: 'Qual o tom de voz?',
      });
      expect(commit).toHaveBeenCalledWith('SET_PHASE', 'interviewing');
      expect(commit).toHaveBeenCalledWith('SET_STATUS', 'open');
      // No agent exists yet: never fetch one.
      expect(dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/show',
        expect.anything(),
        expect.anything()
      );
    });

    it('onSettled fetches and stores the generated agent when the build completes', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn().mockResolvedValue({ id: 9, name: 'Suporte' });

      await actions.onSettled(
        { commit, dispatch },
        { status: 'ready', agent_id: 9, state: { needs_more_info: false } }
      );

      expect(commit).toHaveBeenCalledWith('SET_PHASE', 'reviewing');
      expect(dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 9, {
        root: true,
      });
      expect(commit).toHaveBeenCalledWith('SET_AGENT', {
        id: 9,
        name: 'Suporte',
      });
    });

    it('onSettled surfaces a visible error when the build failed', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();

      await actions.onSettled({ commit, dispatch }, { status: 'failed' });

      expect(commit).toHaveBeenCalledWith('SET_ERROR', 'failed');
    });

    it('onSettled is a no-op while the build is still processing', async () => {
      const commit = vi.fn();
      const dispatch = vi.fn();

      await actions.onSettled({ commit, dispatch }, { status: 'processing' });

      expect(dispatch).not.toHaveBeenCalled();
      expect(commit).not.toHaveBeenCalled();
    });
  });

  describe('mutations', () => {
    it('RESET clears every tracked slice', () => {
      const state = {
        thread: { id: 3 },
        messages: [{ role: 'user' }],
        status: 'ready',
        threadState: 'turn',
        agent: { id: 9 },
        phase: 'reviewing',
        error: 'failed',
      };
      mutations.RESET(state);
      expect(state).toEqual({
        thread: null,
        messages: [],
        status: null,
        threadState: {},
        agent: null,
        phase: 'interviewing',
        error: null,
      });
    });

    it('MERGE_MESSAGES appends backend turns without dropping local ones', () => {
      const state = {
        messages: [
          { role: 'user', content: 'oi' },
          { role: 'assistant', content: 'Qual o objetivo?' },
        ],
      };
      mutations.MERGE_MESSAGES(state, [
        { role: 'user', content: 'oi' },
        { role: 'user', content: 'suporte' },
      ]);
      expect(state.messages).toEqual([
        { role: 'user', content: 'oi' },
        { role: 'assistant', content: 'Qual o objetivo?' },
        { role: 'user', content: 'suporte' },
      ]);
    });
  });
});
