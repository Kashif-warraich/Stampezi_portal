module AdminHelper
  # One tone per status word, shared by every table and panel.
  BADGE_TONES = {
    "active" => "ok", "installable" => "ok", "delivered" => "ok", "valid" => "ok",
    "grace" => "warn", "uploading" => "warn", "uploaded" => "warn", "pending" => "warn",
    "expired" => "bad", "pruned" => "bad", "inactive" => "bad"
  }.freeze

  def status_badge(text, tone = nil)
    tone ||= BADGE_TONES.fetch(text.to_s.downcase, "muted")
    tag.span(text, class: "badge badge-#{tone}")
  end

  # Running vs targeted agent version, as one badge.
  def agent_badge(shop)
    running = shop.license&.agent_version
    target  = shop.target_agent_version
    if target.blank?        then status_badge(running || "unknown", "warn")
    elsif running == target then status_badge(running, "ok")
    else                         status_badge("#{running || '?'} → #{target}", "warn")
    end
  end

  # Where one shop stands against its own target. The target version is worth printing only
  # while it differs from what the shop reports - once they match it is the same number in
  # two adjacent columns, and what the operator wants to see there is simply that this one
  # is done. The stored target is untouched: it is still what makes a reinstall from an old
  # setup.exe snap back, and what stops this release being deleted or pruned.
  def update_state_badge(shop)
    target = shop.target_agent_version
    return status_badge("frozen", "muted") if target.blank?

    shop.license&.agent_version == target ? status_badge("up to date", "ok")
                                          : status_badge("updating → #{target}", "warn")
  end

  def fmt_time(time)
    time ? tag.span(time.strftime("%Y-%m-%d %H:%M"), class: "mono dim") : tag.span("—", class: "dim")
  end

  def fmt_date(time)
    time ? tag.span(time.strftime("%Y-%m-%d"), class: "mono dim") : tag.span("—", class: "dim")
  end

  def release_size(release)
    release.size_bytes ? "#{(release.size_bytes / 1024.0 / 1024).round} MB" : "—"
  end

  def release_state_badge(release)
    if release.pruned?         then status_badge("pruned")
    elsif release.installable? then status_badge("installable")
    else                            status_badge("uploading")
    end
  end

  def nav_item(number, label, path, controllers)
    link_to path, class: "nav-item#{' active' if controllers.include?(controller_name)}" do
      tag.span(number, class: "nav-key") + tag.span(label)
    end
  end
end
