using GitHub: GitHub

"""
    open_prs(repos::AbstractVector{<:AbstractString}; sort="updated", direction="desc")

Return a `Vector` of named tuples `(url, branch, title, body)` (all `String`) for all open PRs
in `repo` (format: `"OWNER/REPO"`), sorted by most recently updated first.
"""
function open_prs(repos::AbstractVector{<:AbstractString}; kwargs...)
    return map(repo -> open_prs(repo; kwargs...), repos)
end

function open_prs(
        fullrepo::AbstractString;
        sort::AbstractString = "updated",
        direction::AbstractString = "desc"
    )
    auth = github_auth()
    params = Dict(
        "state" => "open",
        "sort" => String(sort),
        "direction" => String(direction),
        "per_page" => 100,  # GitHub API max page size
        "page" => 1
    )
    # GitHub.jl paginates automatically; `page_limit` defaults to Inf (all pages).
    prs, _ = GitHub.pull_requests(String(fullrepo); auth, params)
    return map(prs) do pr
        url = string(something(pr.html_url, ""))
        title = string(something(pr.title, ""))
        body = string(something(pr.body, ""))
        head = pr.head
        branch = isnothing(head) ? "" : String(something(head.ref, ""))
        return (; url, branch, title, body)
    end
end
