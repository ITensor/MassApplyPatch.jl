using GitHub: GitHub

"""
    enable_automerge!(repos; token=ENV["GITHUB_TOKEN"], api=GitHub.DEFAULT_API)

Enable the repository-level "Allow auto-merge" setting for each "OWNER/REPO" in `repos`.

Returns: Dict("OWNER/REPO" => (ok::Bool, status::Int, message::String))
"""
function enable_automerge!(
        repos::AbstractVector{<:AbstractString};
        token::AbstractString = get(ENV, "GITHUB_TOKEN", ""),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API
    )
    isempty(token) && error("Set GITHUB_TOKEN or pass `token=`.")
    auth = GitHub.authenticate(api, token)
    results = Dict{String, Tuple{Bool, Int, String}}()
    for repo in repos
        results[repo] = enable_automerge!(repo; api, auth)
    end
    return results
end

function enable_automerge!(
        repo::AbstractString; api::GitHub.GitHubAPI = GitHub.DEFAULT_API, auth
    )
    endpoint = "/repos/$repo"
    headers = Dict("Accept" => "application/vnd.github+json")
    resp = GitHub.gh_patch(
        api, endpoint;
        auth, headers,
        params = Dict("allow_auto_merge" => true),
        handle_error = false
    )
    return if resp.status == 200
        (true, resp.status, "ok")
    else
        (false, resp.status, String(resp.body))
    end
end
