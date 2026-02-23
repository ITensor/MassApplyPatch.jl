function _gh_run_capture(cmd::Cmd)
    out = IOBuffer()
    err = IOBuffer()
    ok = success(pipeline(cmd; stdout = out, stderr = err))
    return (; ok, stdout = String(take!(out)), stderr = String(take!(err)))
end

function merge_pr!(
        pr_url::AbstractString;
        force::Bool = false,
        merge_method::AbstractString = "squash",
        sha::Union{Nothing, String} = nothing,
        commit_title::Union{Nothing, String} = nothing,
        commit_message::Union{Nothing, String} = nothing
    )
    isnothing(Sys.which("gh")) && error("`gh` not found in PATH")

    args = String["gh", "pr", "merge", pr_url]

    # merge strategy
    if merge_method == "squash"
        push!(args, "--squash")
    elseif merge_method == "merge"
        push!(args, "--merge")
    elseif merge_method == "rebase"
        push!(args, "--rebase")
    else
        error("Invalid merge_method=$merge_method (expected: merge|squash|rebase)")
    end

    push!(args, force ? "--admin" : "--auto")
    !isnothing(sha) && append!(args, ["--match-head-commit", sha])
    !isnothing(commit_title) && append!(args, ["--subject", commit_title])
    !isnothing(commit_message) && append!(args, ["--body", commit_message])
    return _gh_run_capture(Cmd(args))
end

"""
    merge_prs!(pr_urls::AbstractVector{<:AbstractString}; kwargs...)

Merge PRs via `gh pr merge`.

Keyword arguments:

  - `force::Bool=false`: bypass requirements and merge immediately (`false` is equivalent to
    `--auto`, `true` is equivalent to `--admin`).
  - `merge_method::AbstractString="squash"`: merge strategy, one of "merge", "squash", or "rebase".
  - `commit_title::Union{Nothing, String}=nothing`: custom commit title (equivalent to `--subject`).
  - `commit_message::Union{Nothing, String}=nothing`: custom commit message (equivalent to `--body`).
"""
function merge_prs!(pr_urls::AbstractVector{<:AbstractString}; kwargs...)
    return [merge_pr!(url; kwargs...) for url in pr_urls]
end

"""
    disable_automerges!(pr_urls::AbstractVector{<:AbstractString})

Disable auto-merge for the given PR URLs via `gh pr merge --disable-auto`.
"""
function disable_automerges!(pr_urls::AbstractVector{<:AbstractString})
    return [disable_automerge!(url) for url in pr_urls]
end
function disable_automerge!(pr_url::AbstractString)
    isnothing(Sys.which("gh")) &&
        return (ok = false, changed = false, stdout = "", stderr = "`gh` not found in PATH")

    # 1) state must be OPEN
    st = _gh_run_capture(`gh pr view $pr_url --json state --jq .state`)
    st.ok || return (ok = false, changed = false, stdout = st.stdout, stderr = st.stderr)
    state = strip(st.stdout)
    if state != "OPEN"
        return (
            ok = true, changed = false, stdout = "",
            stderr = "PR state is $state; nothing to disable",
        )
    end

    # 2) autoMergeRequest must be non-null
    am = _gh_run_capture(
        `gh pr view $pr_url --json autoMergeRequest --jq '.autoMergeRequest != null'`
    )
    am.ok || return (ok = false, changed = false, stdout = am.stdout, stderr = am.stderr)
    enabled = strip(am.stdout) == "true"
    if !enabled
        return (
            ok = true, changed = false, stdout = "",
            stderr = "Auto-merge not enabled; nothing to disable",
        )
    end

    # 3) disable auto-merge
    res = _gh_run_capture(`gh pr merge $pr_url --disable-auto`)
    return (ok = res.ok, changed = res.ok, stdout = res.stdout, stderr = res.stderr)
end
