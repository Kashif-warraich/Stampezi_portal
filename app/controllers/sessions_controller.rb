class SessionsController < ApplicationController
  layout "admin"

  def new
    redirect_to admin_root_path if signed_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    # One message for both wrong-email and wrong-password.
    if user&.authenticate(params[:password].to_s)
      AppLog.info("admin_login.ok", email: user.email)
      reset_session # new session id on privilege change
      session[:user_id] = user.id
      session[:signed_in_at] = Time.current.to_i

      redirect_to safe_next_path, allow_other_host: false
    else
      # Failed admin logins are the thing you want a trail of; the password never gets logged.
      AppLog.warn("admin_login.failed", email: params[:email].to_s)
      flash.now[:alert] = "Invalid credentials"
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path
  end

  private

  # Only same-site admin paths, so ?next= cannot bounce an admin off to another host.
  def safe_next_path
    candidate = params[:next].to_s
    candidate.start_with?("/admin") ? candidate : admin_root_path
  end
end
