"""
    create_issues!(
        repos::AbstractVector{<:AbstractString};
        title::AbstractString,
        body::AbstractString = "",
        labels::AbstractVector{<:AbstractString} = String[]
    )

Create a new issue with the given `title` and `body` in each repository of `repos`
(format: `"OWNER/REPO"`). Returns a `Vector` of named tuples `(; url)` with the
URL of each created issue.
"""
function create_issues!(repos::AbstractVector{<:AbstractString}; kwargs...)
    return map(repo -> create_issues!(repo; kwargs...), repos)
end

function create_issues!(
        repo::AbstractString; title::AbstractString, body::AbstractString = "",
        labels::AbstractVector{<:AbstractString} = String[]
    )
    cmd = `gh issue create --repo $repo --title $title --body $body`
    for label in labels
        cmd = `$cmd --label $label`
    end
    url = readchomp(cmd)
    return (; url)
end
