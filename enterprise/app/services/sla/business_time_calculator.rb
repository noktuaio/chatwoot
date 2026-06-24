class Sla::BusinessTimeCalculator
  MAX_DAYS = 800

  def initialize(schedule:)
    @schedule = schedule
    @timezone = ActiveSupport::TimeZone[schedule.timezone] || ActiveSupport::TimeZone['UTC']
  end

  # Seconds of business time between +from+ and +to+, counting only seconds inside
  # the schedule blocks, walking day by day in the schedule timezone. DST-safe:
  # each day is re-anchored with beginning_of_day in the zone. Short-circuits once
  # the accumulated total reaches +limit+ (the SLA threshold).
  def elapsed_seconds(from, to, limit: nil)
    return 0 if from.blank? || to.blank? || from >= to

    from = from.in_time_zone(@timezone)
    to = to.in_time_zone(@timezone)
    total = 0
    day_start = from.beginning_of_day

    MAX_DAYS.times do
      break if day_start > to

      @schedule.blocks_for(day_start.wday).each do |start_minute, end_minute|
        overlap = [to, day_start + end_minute.minutes].min - [from, day_start + start_minute.minutes].max
        total += overlap if overlap.positive?
      end
      return total.round if limit.present? && total >= limit

      day_start = (day_start + 1.day).beginning_of_day
    end

    total.round
  end
end
