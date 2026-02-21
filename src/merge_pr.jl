using GitHub: GitHub

function _parse_pr_url(url::AbstractString)
    m = match(r"^https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)(?:/.*)?$", url)
    m === nothing && throw(ArgumentError("Not a GitHub PR URL: $url"))
    owner, repo, n = m.captures
    return owner, repo, parse(Int, n)
end

function _gh_merge_pr(
        pr_url::AbstractString;
        merge_method::AbstractString,
        sha::Union{Nothing, String},
        commit_title::Union{Nothing, String},
        commit_message::Union{Nothing, String},
        admin::Bool = false
    )
    isnothing(Sys.which("gh")) && return (false, "", "`gh` not found in PATH")
    args = String["gh", "pr", "merge", pr_url]
    if merge_method == "squash"
        push!(args, "--squash")
    elseif merge_method == "merge"
        push!(args, "--merge")
    elseif merge_method == "rebase"
        push!(args, "--rebase")
    else
        return (
            false,
            "",
            "Invalid merge_method=$merge_method (expected: merge|squash|rebase)",
        )
    end
    admin && push!(args, "--admin")
    sha !== nothing && append!(args, ["--match-head-commit", sha])
    commit_title !== nothing && append!(args, ["--subject", commit_title])
    commit_message !== nothing && append!(args, ["--body", commit_message])
    out = IOBuffer()
    err = IOBuffer()
    try
        run(pipeline(Cmd(args); stdout = out, stderr = err))
        return (true, String(take!(out)), String(take!(err)))
    catch
        return (false, String(take!(out)), String(take!(err)))
    end
end

"""
Merge PRs (REST API).

  - pr_urls: ["https://github.com/OWNER/REPO/pull/123", ...]
  - merge_method: "merge" | "squash" | "rebase"
  - sha: optional safety check (merge only if head SHA matches)
  - force: if true and the REST merge fails, retry via `gh pr merge --admin`
"""
function merge_prs!(
        pr_urls::AbstractVector{<:AbstractString};
        merge_method::AbstractString = "squash",
        sha::Union{Nothing, String} = nothing,
        commit_title::Union{Nothing, String} = nothing,
        commit_message::Union{Nothing, String} = nothing,
        force::Bool = false
    )
    auth = github_auth()
    results = Vector{Any}(undef, length(pr_urls))
    for (i, url) in pairs(pr_urls)
        @info "Merging PR: $url"
        owner, repo, prnum = _parse_pr_url(url)
        r = GitHub.Repo("$owner/$repo")
        params = Dict{Symbol, Any}(:merge_method => merge_method)
        sha !== nothing && (params[:sha] = sha)
        commit_title !== nothing && (params[:commit_title] = commit_title)
        commit_message !== nothing && (params[:commit_message] = commit_message)
        res = GitHub.merge_pull_request(r, prnum; auth, params)
        if force && !(get(res, "merged", false) === true)
            @info "REST merge did not succeed; retrying with `gh pr merge --admin`"
            ok, gh_out, gh_err = _gh_merge_pr(
                url;
                merge_method,
                sha,
                commit_title,
                commit_message,
                admin = true
            )
            if ok
                res = Dict(
                    "merged" => true,
                    "message" => "Merged via `gh pr merge --admin`",
                    "gh_stdout" => gh_out,
                    "gh_stderr" => gh_err
                )
            else
                res["gh_stdout"] = gh_out
                res["gh_stderr"] = gh_err
                res["message"] = string(
                    get(res, "message", ""), " (and `gh --admin` failed)"
                )
            end
        end
        results[i] = res
        @info "Result: merged=$(results[i]["merged"]), message=$(results[i]["message"])"
    end
    return results
end
