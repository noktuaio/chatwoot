# == Schema Information
#
# Table name: team_members
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_team_members_on_team_id              (team_id)
#  index_team_members_on_team_id_and_user_id  (team_id,user_id) UNIQUE
#  index_team_members_on_user_id              (user_id)
#
class TeamMember < ApplicationRecord
  belongs_to :user
  belongs_to :team
  validates :user_id, uniqueness: { scope: :team_id }

  # is_member is embedded into the cached team payload (per current user) via
  # api/v1/models/_team.json.jbuilder, so membership changes must bump the team
  # cache key. team is safe-navigated because destroying a team cascades here
  # via destroy_async, by which point the team row is already gone.
  after_commit -> { team&.account&.update_cache_key('team') }, on: [:create, :destroy]
end

TeamMember.include_mod_with('Audit::TeamMember')
