module Github
  # Installation-scoped repo operations the platform needs: list open issues for
  # the funding picker, post/update the bounty comment, and resolve which issues
  # a PR closes (GraphQL closingIssuesReferences — we trust GitHub's own linkage,
  # not a regex, per docs/merge-correctness.md).
  class RepoClient
    def initialize(installation_id)
      @client = Github::App.installation_client(installation_id)
    end

    # Open issues (excluding PRs, which the issues API also returns).
    def open_issues(full_name, per_page: 50)
      @client.list_issues(full_name, state: "open", per_page: per_page)
             .reject { |i| i.key?(:pull_request) }
    end

    def issue(full_name, number) = @client.issue(full_name, number)

    def post_comment(full_name, issue_number, body)
      @client.add_comment(full_name, issue_number, body)
    end

    def update_comment(full_name, comment_id, body)
      @client.update_comment(full_name, comment_id, body)
    end

    def repository(full_name) = @client.repository(full_name)

    # Issue numbers a PR will close via GitHub's closing-keyword linkage.
    # Returns [{ number:, repo_full_name:, id: }]. Empty if none.
    def closing_issue_refs(pr_node_id)
      query = <<~GQL
        query($id: ID!) {
          node(id: $id) {
            ... on PullRequest {
              closingIssuesReferences(first: 20) {
                nodes { number, id, repository { nameWithOwner } }
              }
            }
          }
        }
      GQL
      resp = @client.post("/graphql", { query: query, variables: { id: pr_node_id } }.to_json)
      nodes = resp.dig(:data, :node, :closingIssuesReferences, :nodes) || []
      nodes.map { |n| { number: n[:number], id: n[:id], repo_full_name: n.dig(:repository, :nameWithOwner) } }
    end
  end
end
