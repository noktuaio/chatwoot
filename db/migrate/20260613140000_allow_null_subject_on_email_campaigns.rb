class AllowNullSubjectOnEmailCampaigns < ActiveRecord::Migration[7.1]
  # Subject is optional for DRAFT campaigns (the create dialog no longer asks for it;
  # the AI / builder fills it before sending). The model already validates presence
  # only when not draft, but the DB column was still NOT NULL, so creating a draft
  # without a subject raised PG::NotNullViolation. Relax the column to allow NULL.
  def up
    change_column_null :email_campaigns, :subject, true
  end

  def down
    execute("UPDATE email_campaigns SET subject = '' WHERE subject IS NULL")
    change_column_null :email_campaigns, :subject, false
  end
end
