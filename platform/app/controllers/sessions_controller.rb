class SessionsController < ApplicationController
  # OmniAuth intercepts POST /auth/github before this runs; this is only a
  # fallback target for the route.
  def passthru
    redirect_to root_path, alert: "GitHub login is not configured."
  end

  # GET /auth/github/callback — OmniAuth has populated request.env["omniauth.auth"].
  def create
    auth = request.env["omniauth.auth"]
    user = User.from_github_auth(auth)
    reset_session
    session[:user_id] = user.id
    redirect_to dashboard_path, notice: "Signed in as #{user.github_login}."
  rescue StandardError => e
    Rails.logger.error("OAuth create failed: #{e.class}: #{e.message}")
    redirect_to root_path, alert: "Sign-in failed. Please try again."
  end

  def failure
    redirect_to root_path, alert: "GitHub sign-in was cancelled or failed."
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
  end
end
