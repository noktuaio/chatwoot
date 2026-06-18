# frozen_string_literal: true

class Autonomia::AccountLink < ApplicationRecord
  self.table_name = 'autonomia_account_links'

  belongs_to :account

  validates :identity_organization_id, presence: true, uniqueness: true
end
