# GitHub OAuth for identity only (login). Repo access + webhooks come from the
# GitHub App installation token, NOT this OAuth token — so the scope here is
# minimal: who you are and your email. (Build plan §5 / A.5.)
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
           Rails.application.credentials.dig(:github, :oauth_client_id),
           Rails.application.credentials.dig(:github, :oauth_client_secret),
           scope: "read:user user:email"
end

# Fail closed on OAuth errors; show our own page rather than a raw exception.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:failure).call(env)
end
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
