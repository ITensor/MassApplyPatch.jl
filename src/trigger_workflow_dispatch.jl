using GitHub: GitHub

"""
    trigger_workflow_dispatch!(
      repos::AbstractVector{<:AbstractString},
      workflow::AbstractString;
      ref::Union{Nothing, AbstractString}=nothing,
      inputs::AbstractDict=Dict{String, String}(),
      api::GitHub.GitHubAPI=GitHub.DEFAULT_API,
    )

Trigger a GitHub Actions workflow dispatch for each repository in `repos`.

  - `repos` should contain entries like `"OWNER/REPO"`.
  - `workflow` can be a workflow file name (for example `"TagBot.yml"`), workflow name, or workflow ID.
  - If `ref` is `nothing`, each repository's default branch is used.
  - `inputs` are optional `workflow_dispatch` inputs.

Returns:

`Dict("OWNER/REPO" => (ok::Bool, status::Int, message::String, ref::String))`
"""
function trigger_workflow_dispatch!(
        repos::AbstractVector{<:AbstractString}, workflow::AbstractString;
        ref::Union{Nothing, AbstractString} = nothing,
        inputs::AbstractDict = Dict{String, String}(),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API
    )
    @info "Dispatching workflow across repositories" workflow num_repos = length(repos)
    auth = github_auth()
    return map(repos) do repo
        @info "Dispatching workflow" repo workflow
        return trigger_workflow_dispatch!(repo, workflow; ref, inputs, api, auth)
    end
end

function trigger_workflow_dispatch!(
        repo::AbstractString, workflow::AbstractString;
        ref::Union{Nothing, AbstractString} = nothing,
        inputs::AbstractDict = Dict{String, String}(),
        api::GitHub.GitHubAPI = GitHub.DEFAULT_API, auth
    )
    repo_ref = isnothing(ref) ? get_default_branch(repo, auth) : String(ref)
    @info "Preparing workflow dispatch" repo workflow ref = repo_ref
    endpoint = "/repos/$repo/actions/workflows/$workflow/dispatches"
    headers = Dict("Accept" => "application/vnd.github+json")
    params = Dict{String, Any}("ref" => repo_ref)
    normalized_inputs = Dict(string(k) => string(v) for (k, v) in pairs(inputs))
    if !isempty(normalized_inputs)
        params["inputs"] = normalized_inputs
        @info "Including workflow inputs" repo workflow num_inputs =
            length(normalized_inputs)
    end
    resp = GitHub.gh_post(api, endpoint; auth, headers, params, handle_error = false)
    return if resp.status == 204
        @info "Workflow dispatch succeeded" repo workflow status = resp.status ref =
            repo_ref
        (true, resp.status, "ok", repo_ref)
    else
        @info "Workflow dispatch failed" repo workflow status = resp.status ref = repo_ref
        (false, resp.status, String(resp.body), repo_ref)
    end
end
