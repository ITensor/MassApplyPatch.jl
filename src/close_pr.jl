is_pr_ref(ref::AbstractString) = occursin(r"(?:/pull/|#[0-9]+$)", ref)

function close_item!(
        ref::AbstractString;
        delete_branch::Bool = false,
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    is_pr = is_pr_ref(ref)
    close_cmd = is_pr ? `gh pr close $ref` : `gh issue close $ref`
    if is_pr && delete_branch
        close_cmd = `$close_cmd --delete-branch`
    end

    ok = success_quiet(close_cmd)
    if !ok
        kind = is_pr ? "PR" : "issue"
        @warn "Failed to close $kind: $ref"
        ignore_errors || error("Failed to close $kind: $ref")
        return false
    end

    kind = is_pr ? "PR" : "issue"
    @info "Closed $kind: $ref"
    if comment !== nothing
        comment_cmd = if is_pr
            `gh pr comment $ref --body $comment`
        else
            `gh issue comment $ref --body $comment`
        end
        run_quiet(comment_cmd)
        @info "Commented on $kind: $ref with comment: $comment"
    end
    return true
end

function reopen_item!(
        ref::AbstractString;
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    is_pr = is_pr_ref(ref)
    reopen_cmd = is_pr ? `gh pr reopen $ref` : `gh issue reopen $ref`

    ok = success_quiet(reopen_cmd)
    if !ok
        kind = is_pr ? "PR" : "issue"
        @warn "Failed to reopen $kind: $ref"
        ignore_errors || error("Failed to reopen $kind: $ref")
        return false
    end

    kind = is_pr ? "PR" : "issue"
    @info "Reopened $kind: $ref"
    if comment !== nothing
        comment_cmd = if is_pr
            `gh pr comment $ref --body $comment`
        else
            `gh issue comment $ref --body $comment`
        end
        run_quiet(comment_cmd)
        @info "Commented on $kind: $ref with comment: $comment"
    end
    return true
end

"""
    close_issue!(issue; delete_branch=false, comment=nothing, ignore_errors=true)

Close a GitHub issue or pull request using the `gh` CLI.

`issue` may be an issue/PR URL like:

  - `https://github.com/ORG/REPO/issues/123`
  - `https://github.com/ORG/REPO/pull/123`
    or any identifier accepted by `gh issue close` / `gh pr close`.

If `issue` points to a PR and `delete_branch=true`, the PR branch is deleted after close.
If `comment` is provided, posts a comment after closing.
Returns `true` if the close command succeeded, `false` otherwise (unless `ignore_errors=false`).

Requires: `gh` installed and authenticated (`gh auth login`).
"""
function close_issue!(
        issue::AbstractString;
        delete_branch::Bool = false,
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return close_item!(issue; delete_branch, comment, ignore_errors)
end

"""
    close_issues!(issues; kwargs...)

Close multiple GitHub issues/PRs. Returns a `Vector{Bool}` of close results.
"""
function close_issues!(
        issues::AbstractVector{<:AbstractString};
        delete_branch::Bool = false,
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return [
        close_issue!(issue; delete_branch, comment, ignore_errors)
            for issue in issues
    ]
end

"""
    reopen_issue!(issue; comment=nothing, ignore_errors=true)

Reopen a GitHub issue or pull request using the `gh` CLI.

`issue` may be an issue/PR URL like:

  - `https://github.com/ORG/REPO/issues/123`
  - `https://github.com/ORG/REPO/pull/123`
    or any identifier accepted by `gh issue reopen` / `gh pr reopen`.

If `comment` is provided, posts a comment after reopening.
Returns `true` if the reopen command succeeded, `false` otherwise (unless `ignore_errors=false`).

Requires: `gh` installed and authenticated (`gh auth login`).
"""
function reopen_issue!(
        issue::AbstractString;
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return reopen_item!(issue; comment, ignore_errors)
end

"""
    reopen_issues!(issues; kwargs...)

Reopen multiple GitHub issues/PRs. Returns a `Vector{Bool}` of reopen results.
"""
function reopen_issues!(
        issues::AbstractVector{<:AbstractString};
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return [
        reopen_issue!(issue; comment, ignore_errors)
            for issue in issues
    ]
end

"""
    close_pr!(pr; delete_branch=false, comment=nothing, ignore_errors=true)

Backward-compatible wrapper for closing a pull request. Uses [`close_issue!`](@ref).
"""
function close_pr!(
        pr::AbstractString;
        delete_branch::Bool = false,
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return close_issue!(pr; delete_branch, comment, ignore_errors)
end

"""
    close_prs!(prs; kwargs...)

Backward-compatible wrapper for closing multiple pull requests. Uses [`close_issues!`](@ref).
"""
function close_prs!(
        prs::AbstractVector{<:AbstractString};
        delete_branch::Bool = false,
        comment::Union{Nothing, AbstractString} = nothing,
        ignore_errors::Bool = true
    )
    return close_issues!(prs; delete_branch, comment, ignore_errors)
end
