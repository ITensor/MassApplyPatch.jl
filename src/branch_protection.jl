using GitHub: GitHub

"""
    protect_branch!(repos;
        checks::Vector{String},
        branch::Union{Nothing,String}=nothing,
        token::AbstractString=get(ENV,"GITHUB_TOKEN",""),
        api::GitHub.GitHubAPI=GitHub.DEFAULT_API,
        strict::Bool=true,
        enforce_admins::Bool=false,
        require_pr::Bool=true,
        required_approvals::Int=1,
        require_code_owner_reviews::Bool=false,
        dismiss_stale_reviews::Bool=true,
        require_linear_history::Bool=true,
        allow_force_pushes::Bool=false,
        allow_deletions::Bool=false,
    ) -> Dict{String,Tuple{Bool,Int,String}}

Apply branch protection to each repo in `repos`.

  - `checks` are the required status check contexts (exact names).
  - `branch=nothing` means “use each repo's default branch”.
"""
function protect_branch!(
        repos::AbstractVector{<:AbstractString};
        checks::Vector{String},
        branch::Union{Nothing, String} = nothing,
        token::AbstractString = get(ENV, "GITHUB_TOKEN", ""),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API,
        strict::Bool = true,
        enforce_admins::Bool = false,
        require_pr::Bool = true,
        required_approvals::Int = 1,
        require_code_owner_reviews::Bool = false,
        dismiss_stale_reviews::Bool = true,
        require_linear_history::Bool = true,
        allow_force_pushes::Bool = false,
        allow_deletions::Bool = false
    )
    isempty(token) && error("Set GITHUB_TOKEN or pass `token=`.")
    auth = GitHub.authenticate(api, token)
    results = Dict{String, Tuple{Bool, Int, String}}()
    for repo in repos
        repo = strip(repo)
        # Determine target branch
        target_branch = branch
        if target_branch === nothing
            target_branch = getproperty(GitHub.repo(repo; auth), :default_branch)
        end
        endpoint = "/repos/$repo/branches/$target_branch/protection"
        # Update branch protection payload per GitHub REST API.
        # Note: restrictions must be null unless you are restricting who can push. :contentReference[oaicite:1]{index=1}
        params = Dict(
            "required_status_checks" => Dict(
                "strict" => strict,
                "contexts" => checks
            ),
            "enforce_admins" => enforce_admins,
            "required_pull_request_reviews" => (
                if require_pr
                    Dict(
                        "dismiss_stale_reviews" => dismiss_stale_reviews,
                        "require_code_owner_reviews" => require_code_owner_reviews,
                        "required_approving_review_count" => required_approvals
                    )
                else
                    nothing
                end
            ),
            "restrictions" => nothing,
            "required_linear_history" => Dict("enabled" => require_linear_history),
            "allow_force_pushes" => Dict("enabled" => allow_force_pushes),
            "allow_deletions" => Dict("enabled" => allow_deletions)
        )
        headers = Dict("Accept" => "application/vnd.github+json")
        resp = GitHub.gh_put(api, endpoint; auth, headers, params, handle_error = false)
        if resp.status in (200, 201)
            results[repo] = (true, resp.status, "ok (protected $target_branch)")
        else
            results[repo] = (false, resp.status, String(resp.body))
        end
    end
    return results
end
