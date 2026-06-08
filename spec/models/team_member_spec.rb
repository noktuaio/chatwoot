require 'rails_helper'

RSpec.describe TeamMember do
  describe 'associations' do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'team cache invalidation' do
    let(:team) { create(:team) }
    let(:user) { create(:user) }

    it 'bumps the team cache key after create' do
      expect(team.account).to receive(:update_cache_key).with('team')
      create(:team_member, team: team, user: user)
    end

    it 'bumps the team cache key after destroy' do
      team_member = create(:team_member, team: team, user: user)
      expect(team.account).to receive(:update_cache_key).with('team')
      team_member.destroy
    end
  end
end
