using GitHub: GitHub

"""
    open_issues(repos::AbstractVector{<:AbstractString}; sort="updated", direction="desc")

Return a `Vector` of named tuples `(url, title, body)` (all `String`) for all open issues
in each repository of `repos` (format: `"OWNER/REPO"`), sorted by most recently updated first.
Pull requests are excluded.
"""
function open_issues(repos::AbstractVector{<:AbstractString}; kwargs...)
    return map(repo -> open_issues(repo; kwargs...), repos)
end

function open_issues(
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
    issues, _ = GitHub.issues(String(fullrepo); auth, params)
    issues = filter(issue -> isnothing(issue.pull_request), issues)
    return map(issues) do issue
        url = string(something(issue.html_url, ""))
        title = string(something(issue.title, ""))
        body = string(something(issue.body, ""))
        return (; url, title, body)
    end
end

"""
    filter_open_issues(
        repos::AbstractVector{<:AbstractString}, predicate::Function;
        sort="updated", direction="desc"
    )

Return a flattened `Vector` of open issues from all `repos` that satisfy `predicate`.
`predicate` should accept a named tuple `(url, title, body)`.
"""
function filter_open_issues(
        repos::AbstractVector{<:AbstractString}, predicate::Function;
        kwargs...
    )
    issues = reduce(vcat, open_issues(repos; kwargs...); init = NamedTuple[])
    return filter(predicate, issues)
end
