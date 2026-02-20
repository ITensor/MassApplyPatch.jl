using GitHub: GitHub

function latest_prs(repos::AbstractVector{<:AbstractString}; kwargs...)
    return map(repo -> latest_pr(repo; kwargs...), repos)
end

"""
    latest_pr(repo::AbstractString; state::AbstractString="open")

Return a named tuple `(url, branch, title)` (all `String`) for the most recently-updated PR in
`repo` (format: `"OWNER/REPO"`), or `nothing` if none exist.
"""
function latest_pr(fullrepo::AbstractString; state::AbstractString = "open")
    auth = github_auth()
    params = Dict(
        "state" => String(state),
        "sort" => "updated",
        "direction" => "desc",
        "per_page" => 1,
        "page" => 1
    )
    prs, _ = GitHub.pull_requests(String(fullrepo); auth, params, page_limit = 1)
    isempty(prs) && return nothing
    pr = prs[1]
    url = string(something(pr.html_url, ""))
    title = string(something(pr.title, ""))
    head = pr.head
    branch = isnothing(head) ? "" : String(something(head.ref, ""))
    return (; url, branch, title)
end
