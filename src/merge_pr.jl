using GitHub: GitHub

function _parse_pr_url(url::AbstractString)
    m = match(r"^https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)(?:/.*)?$", url)
    m === nothing && throw(ArgumentError("Not a GitHub PR URL: $url"))
    owner, repo, n = m.captures
    return owner, repo, parse(Int, n)
end

"""
Merge PRs (REST API).

- pr_urls: ["https://github.com/OWNER/REPO/pull/123", ...]
- merge_method: "merge" | "squash" | "rebase"
- sha: optional safety check (merge only if head SHA matches)
"""
function merge_prs!(pr_urls::AbstractVector{<:AbstractString};
                   merge_method::AbstractString = "squash",
                   sha::Union{Nothing,String} = nothing,
                   commit_title::Union{Nothing,String} = nothing,
                   commit_message::Union{Nothing,String} = nothing)

    auth = github_auth()
    results = Vector{Any}(undef, length(pr_urls))

    for (i, url) in pairs(pr_urls)
        owner, repo, prnum = _parse_pr_url(url)
        r = GitHub.Repo("$owner/$repo")

        params = Dict{Symbol,Any}(:merge_method => merge_method)
        sha !== nothing && (params[:sha] = sha)
        commit_title !== nothing && (params[:commit_title] = commit_title)
        commit_message !== nothing && (params[:commit_message] = commit_message)

        results[i] = GitHub.merge_pull_request(r, prnum; auth=auth, params=params)
    end

    return results
end
