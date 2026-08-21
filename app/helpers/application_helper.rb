module ApplicationHelper
  # Matches the admin UI the Next.js portal rendered: local time, or "never".
  def format_time(value)
    return "never" if value.nil?

    value.in_time_zone.strftime("%d/%m/%Y, %H:%M:%S")
  end
end
