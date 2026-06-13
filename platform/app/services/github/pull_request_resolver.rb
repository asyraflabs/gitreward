module Github
  # Maps a pull_request webhook payload to the funded Bounty it would close, using
  # GitHub's own closing-keyword linkage (closingIssuesReferences), per A.1 #3 and
  # docs/merge-correctness.md. Returns nil if the PR closes no funded bounty.
  class PullRequestResolver
    Result = Struct.new(:bounty, :repository, :installation, :closing_issues, keyword_init: true)

    def initialize(payload)
      @payload = payload
    end

    def installation_id = @payload.dig("installation", "id")
    def pr              = @payload["pull_request"]
    def pr_node_id      = pr["node_id"]
    def base_ref        = pr.dig("base", "ref")
    def author_github_id = pr.dig("user", "id")
    def repo_full_name  = @payload.dig("repository", "full_name")
    def repo_github_id  = @payload.dig("repository", "id")

    def resolve
      installation = Installation.active.find_by(github_installation_id: installation_id)
      return nil unless installation

      repository = installation.repositories.find_by(github_repo_id: repo_github_id)
      return nil unless repository

      closing = Github::RepoClient.new(installation_id).closing_issue_refs(pr_node_id)
      issue_numbers = closing.select { |c| c[:repo_full_name] == repo_full_name }.map { |c| c[:number] }
      return Result.new(bounty: nil, repository: repository, installation: installation, closing_issues: closing) if issue_numbers.empty?

      bounty = repository.bounties.funded.find_by(github_issue_number: issue_numbers)
      Result.new(bounty: bounty, repository: repository, installation: installation, closing_issues: closing)
    rescue StandardError => e
      Rails.logger.error("PullRequestResolver failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
