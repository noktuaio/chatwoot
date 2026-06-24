class Crm::FollowUpReminderMailer < ApplicationMailer
  def reminder(follow_up, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @follow_up = follow_up
    @account = follow_up.account
    @card = follow_up.card
    @due_at = follow_up.due_at
    @action_url = "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{follow_up.account_id}/crm"
    @meeting = meeting

    return meeting_reminder if meeting_reminder?

    subject = I18n.t('crm.follow_up_reminder.subject', title: follow_up.title)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  private

  def meeting_reminder
    @meeting_starts_at = @meeting.starts_at.in_time_zone(@meeting.timezone)
    @meeting_starts_at_text = "#{localized_meeting_time(:long)} (#{@meeting.timezone})"
    @join_url = @meeting.online_meeting_url

    mail(
      to: @agent.email,
      subject: I18n.t(
        'crm.meetings.reminder.email_subject',
        title: @meeting.title,
        time: localized_meeting_time(:short),
        default: 'Lembrete: %{title} às %{time}'
      )
    ) do |format|
      format.html { render 'crm/follow_up_reminder_mailer/meeting_reminder' }
    end
  end

  def meeting_reminder?
    @follow_up.follow_up_type.to_sym == :meeting && @meeting.present?
  end

  def meeting
    return @meeting if defined?(@meeting)

    @meeting = follow_up_meeting || reminder_meeting
  end

  def follow_up_meeting
    return unless @follow_up.respond_to?(:meeting)

    @follow_up.meeting
  end

  def reminder_meeting
    return unless defined?(Crm::Meeting)
    return unless Crm::Meeting.table_exists? && Crm::Meeting.column_names.include?('reminder_id')

    Crm::Meeting.find_by(
      account_id: @follow_up.account_id,
      card_id: @follow_up.card_id,
      reminder_id: @follow_up.id
    )
  end

  def localized_meeting_time(format)
    I18n.l(@meeting_starts_at, format: format)
  rescue I18n::MissingTranslationData
    I18n.l(@meeting_starts_at, format: :long)
  end

  def liquid_droppables
    super.merge(user: @agent)
  end
end
