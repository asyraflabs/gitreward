module Github
  # Upserts an Installation and its Repositories from GitHub, so the funding UI
  # can list repos/issues and the webhook handler can map events to an install
  # (C.3). Used by both the install callback and the installation webhook.
  module InstallationSync
    module_function

    # @param installation_id [Integer] GitHub installation id
    # @param installed_by [User, nil] the user who clicked install, if known
    def call(installation_id, installed_by: nil)
      meta = Github::App.app_client.installation(installation_id)
      account = meta[:account]

      install = Installation.find_or_initialize_by(github_installation_id: installation_id)
      install.account_type = (meta[:target_type] || account[:type]).to_s.downcase
      install.account_github_id = account[:id]
      # Link the installer only if not already linked, so a later re-sync (e.g.
      # repos added by a different org member) never clobbers the original.
      install.installed_by_user ||= installed_by
      install.suspended_at = meta[:suspended_at]
      install.save!

      sync_repositories(install)
      install
    end

    def sync_repositories(install)
      client = Github::App.installation_client(install.github_installation_id)
      repos = client.get("/installation/repositories")[:repositories] || []
      seen_ids = []

      repos.each do |r|
        repo = Repository.find_or_initialize_by(github_repo_id: r[:id])
        repo.installation = install
        repo.full_name = r[:full_name]
        repo.default_branch = r[:default_branch]
        repo.save!
        seen_ids << r[:id]
      end

      # Drop repos no longer covered by this installation (revoked access).
      install.repositories.where.not(github_repo_id: seen_ids).destroy_all if seen_ids.any?
    end
  end
end
