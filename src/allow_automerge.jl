using GitHub: GitHub

"""
    allow_automerge!(repos, enable::Bool = true; token=ENV["GITHUB_TOKEN"], api=GitHub.DEFAULT_API)

Enable or disable the repository-level "Allow auto-merge" setting for each "OWNER/REPO" in `repos`,
for example `allow_automerge!(["ITensor/SparseArraysBase.jl"], true)` to enable it
or `allow_automerge!(["ITensor/SparseArraysBase.jl"], false)` to disable it.

Returns: Dict("OWNER/REPO" => (ok::Bool, status::Int, message::String))
"""
function allow_automerge!(
        repos::AbstractVector{<:AbstractString}, enable::Bool = true;
        token::AbstractString = get(ENV, "GITHUB_TOKEN", ""),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API
    )
    isempty(token) && error("Set GITHUB_TOKEN or pass `token=`.")
    auth = GitHub.authenticate(api, token)
    results = Dict{String, Tuple{Bool, Int, String}}()
    for repo in repos
        results[repo] = allow_automerge!(repo, enable; api, auth)
    end
    return results
end

function allow_automerge!(
        repo::AbstractString, enable::Bool = true;
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API, auth
    )
    endpoint = "/repos/$repo"
    headers = Dict("Accept" => "application/vnd.github+json")
    resp = GitHub.gh_patch(
        api, endpoint;
        auth, headers,
        params = Dict("allow_auto_merge" => enable),
        handle_error = false
    )
    return if resp.status == 200
        (true, resp.status, "ok")
    else
        (false, resp.status, String(resp.body))
    end
end
