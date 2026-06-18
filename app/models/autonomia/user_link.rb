# frozen_string_literal: true

class Autonomia::UserLink < ApplicationRecord
  self.table_name = 'autonomia_user_links'

  belongs_to :user

  validates :identity_user_id, presence: true, uniqueness: true
end
