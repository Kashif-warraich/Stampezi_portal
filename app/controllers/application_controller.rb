class ApplicationController < ActionController::Base
  # Matches the 12-hour admin session the Next.js portal issued.
  SESSION_TTL = 12.hours

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = begin
      signed_in_at = session[:signed_in_at]
      if session[:user_id] && signed_in_at && Time.zone.at(signed_in_at) > SESSION_TTL.ago
        User.find_by(id: session[:user_id])
      end
    end
  end
  helper_method :current_user

  def signed_in? = current_user.present?
  helper_method :signed_in?

  def require_admin
    return if signed_in?

    redirect_to login_path(next: request.fullpath)
  end

  # Admin gate for the API: a browser session, or the ADMIN_TOKEN bearer used by scripts
  # and desktop tooling.
  def admin?
    return true if signed_in?

    expected = ENV["ADMIN_TOKEN"].presence
    provided = request.headers["Authorization"]&.delete_prefix("Bearer ")
    expected.present? && provided.present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end
end
