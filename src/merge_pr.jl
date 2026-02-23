function merge_pr!(
        pr_url::AbstractString;
        force::Bool = false,
        merge_method::AbstractString = "squash",
        sha::Union{Nothing, String} = nothing,
        commit_title::Union{Nothing, String} = nothing,
        commit_message::Union{Nothing, String} = nothing
    )
    Sys.which("gh") === nothing && error("`gh` not found in PATH")

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

    sha !== nothing && append!(args, ["--match-head-commit", sha])
    commit_title !== nothing && append!(args, ["--subject", commit_title])
    commit_message !== nothing && append!(args, ["--body", commit_message])

    out = IOBuffer()
    err = IOBuffer()
    ok = success(pipeline(Cmd(args); stdout = out, stderr = err))

    return (; ok, stdout = String(take!(out)), stderr = String(take!(err)))
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
