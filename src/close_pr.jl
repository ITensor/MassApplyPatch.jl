"""
    close_pr!(pr; delete_branch=false, comment=nothing, ignore_errors=true)

Close a GitHub pull request using the `gh` CLI.

`pr` may be a PR URL like `https://github.com/ORG/REPO/pull/123` (recommended), a PR number,
or any identifier accepted by `gh pr close`.

If `comment` is provided, posts a PR comment after closing.
Returns `true` if the close command succeeded, `false` otherwise (unless `ignore_errors=false`).

Requires: `gh` installed and authenticated (`gh auth login`).
"""
function close_pr!(
    pr::AbstractString;
    delete_branch::Bool = false,
    comment::Union{Nothing,AbstractString} = nothing,
    ignore_errors::Bool = true,
)
    cmd = `gh pr close $pr`
    delete_branch && (cmd = `$cmd --delete-branch`)
    ok = success_quiet(cmd)
    if !ok
        ignore_errors || error("Failed to close PR: $pr")
        return false
    end
    if comment !== nothing
        # Use a separate command for compatibility across gh versions.
        run_quiet(`gh pr comment $pr --body $comment`)
    end
    return true
end

"""
    close_prs!(prs; kwargs...)

Close multiple PRs. Returns a `Vector{Bool}` of close results.
"""
function close_prs!(
    prs::AbstractVector{<:AbstractString};
    delete_branch::Bool = false,
    comment::Union{Nothing,AbstractString} = nothing,
    ignore_errors::Bool = true,
)
    return [
        close_pr!(pr; delete_branch, comment, ignore_errors)
        for pr in prs
    ]
end
