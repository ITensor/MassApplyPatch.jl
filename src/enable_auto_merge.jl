using GitHub: GitHub

"""
    enable_automerge!(repos; token=ENV["GITHUB_TOKEN"], api=GitHub.DEFAULT_API)

Enable the repository-level "Allow auto-merge" setting for each "OWNER/REPO" in `repos`.

Returns: Dict("OWNER/REPO" => (ok::Bool, status::Int, message::String))
"""
function enable_automerge!(repos::AbstractVector{<:AbstractString}; kwargs...)
    results = Dict{String, Tuple{Bool, Int, String}}()
    for repo in repos
        result = enable_automerge!(repo; kwargs...)
        results[repo] = result
    end
    return results
end

function enable_automerge!(
        repo::AbstractString;
        token::AbstractString = get(ENV, "GITHUB_TOKEN", ""),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API
    )
    isempty(token) && error("Set GITHUB_TOKEN or pass `token=`.")
    # README shows token auth usage. :contentReference[oaicite:1]{index=1}
    auth = GitHub.authenticate(api, token)
    results = Dict{String, Tuple{Bool, Int, String}}()
    occursin("/", repo) || error("Bad repo '$repo' (expected \"OWNER/REPO\")")
    endpoint = "/repos/$r"
    headers = Dict("Accept" => "application/vnd.github+json")
    # PATCH /repos/{owner}/{repo} with {"allow_auto_merge": true}. :contentReference[oaicite:2]{index=2}
    resp = GitHub.gh_patch(
        api, endpoint; auth, headers, params = Dict("allow_auto_merge" => true),
        handle_error = false
    )
    return if resp.status == 200
        (true, resp.status, "ok")
    else
        (false, resp.status, String(resp.body))
    end
end
