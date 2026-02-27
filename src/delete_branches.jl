using GitHub: GitHub

"""
    delete_branches!(f, repos; ignore_errors=true, api=GitHub.DEFAULT_API)

Delete branches in each repository from `repos` when `f(branch_name)` is `true`.

`repos` should contain entries like `"OWNER/REPO"`.

Returns a vector of named tuples:
`(repo, branch, ok, status, message)`.
"""
function delete_branches!(
        f::Function, repos::AbstractVector{<:AbstractString};
        ignore_errors::Bool = true,
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API
    )
    auth = github_auth()
    results = NamedTuple{
        (:repo, :branch, :ok, :status, :message),
        Tuple{String, String, Bool, Int, String},
    }[]
    for repo in repos
        fullrepo = String(repo)
        branches, _ = GitHub.branches(
            fullrepo;
            auth,
            params = Dict("per_page" => 100)
        )
        for branch in branches
            branch_name = String(something(branch.name, ""))
            isempty(branch_name) && continue
            f(branch_name) || continue

            ok = false
            status = 0
            message = ""
            try
                resp = GitHub.delete_reference(
                    api,
                    fullrepo,
                    "heads/$branch_name";
                    auth,
                    handle_error = false
                )
                status = resp.status
                ok = status in (200, 204)
                message = ok ? "deleted" : String(resp.body)
            catch err
                ok = false
                status = 0
                message = sprint(showerror, err)
            end

            push!(results, (; repo = fullrepo, branch = branch_name, ok, status, message))
            if ok
                @info "Deleted branch $fullrepo:$branch_name"
            else
                @warn "Failed to delete branch $fullrepo:$branch_name ($status): $message"
                ignore_errors || error("Failed to delete branch $fullrepo:$branch_name")
            end
        end
    end
    return results
end
