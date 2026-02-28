"""
    create_issues!(
        repos::AbstractVector{<:AbstractString};
        title::AbstractString,
        body::AbstractString = "",
        labels::AbstractVector{<:AbstractString} = String[],
        pin::Bool = false
    )

Create a new issue with the given `title` and `body` in each repository of `repos`
(format: `"OWNER/REPO"`). Returns a `Vector` of named tuples `(; url)` with the
URL of each created issue. If `pin=true`, the issue is pinned after creation.
"""
function create_issues!(repos::AbstractVector{<:AbstractString}; kwargs...)
    return map(repo -> create_issues!(repo; kwargs...), repos)
end

function create_issues!(
        repo::AbstractString; title::AbstractString, body::AbstractString = "",
        labels::AbstractVector{<:AbstractString} = String[], pin::Bool = false
    )
    cmd = `gh issue create --repo $repo --title $title --body $body`
    for label in labels
        cmd = `$cmd --label $label`
    end
    url = readchomp(cmd)
    if pin
        number = last(split(url, "/"))
        node_id = readchomp(`gh api repos/$repo/issues/$number --jq '.node_id'`)
        run(
            `gh api graphql -f query="mutation { pinIssue(input: { issueId: \"$node_id\" }) { issue { id } } }"`
        )
    end
    return (; url)
end
