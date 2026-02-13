module MassApplyPatch

using Git: Git
using GitHub: GitHub

if VERSION >= v"1.11.0-DEV.469"
    let str = "public main"
        eval(Meta.parse(str))
    end
end

default_branch() = "masspatch"
default_title() = "Apply mass patch"
default_body() = "This PR applies a mass patch."

function clone_repo(repo::AbstractString, destdir::AbstractString)
    url = "https://github.com/$repo.git"
    Git.clone(url, destdir)
    return nothing
end

function make_patch_pr(
        patch, repo::AbstractString;
        branch::AbstractString = default_branch(),
        title::AbstractString = default_title(),
        body::AbstractString = default_body()
    )
    tmpdir = mktempdir()
    repodir = joinpath(tmpdir, split(repo, "/"; limit = 2)[2])
    clone_repo(repo, repodir)
    cd(repodir) do
        Git.branch_create(branch)
        Git.checkout(branch)
        @invokelatest patch()
        Git.add(".")
        Git.commit(title)
        Git.push("origin", branch)
        # Create PR using GitHub.jl
        user, repo_name = split(repo, "/")
        auth = GitHub.authenticate(ENV["GITHUB_TOKEN"])
        base = "main"  # or detect default branch
        pr = GitHub.create_pull_request(user, repo_name, title, body, branch, base; auth)
        @info "Created PR: $(pr.html_url)"
    end
    return nothing
end

"""
    MassApplyPatch.main(argv)

Command line interface for MassApplyPatch.

Arguments:

  - `argv`: Command line arguments. Expected format:
    massapplypatch <org/repo>... --patch=patch.jl [--branch=branchname] [--title=prtitle] [--body=prbody]

The patch function should be provided as a Julia file, which is included and must define a function `patch(repo_path)`.
"""
function main(argv)
    repos = String[]
    patchfile = nothing
    branch = default_branch()
    title = default_title()
    body = default_body()
    for arg in argv
        if startswith(arg, "--patch=")
            patchfile = split(arg, "="; limit = 2)[2]
        elseif startswith(arg, "--branch=")
            branch = split(arg, "="; limit = 2)[2]
        elseif startswith(arg, "--title=")
            title = split(arg, "="; limit = 2)[2]
        elseif startswith(arg, "--body=")
            body = split(arg, "="; limit = 2)[2]
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(repos, arg)
        end
    end
    if isnothing(patchfile)
        error("--patch=<patchfile> argument required")
    end
    # Load patch function
    include(patchfile)
    if !isdefined(@__MODULE__, :patch)
        error("Patch file must define a function 'patch(repo_path)'.")
    end
    for repo in repos
        make_patch_pr(patch, repo; branch, title, body)
    end
    # TODO: Clone each repo, apply patchfn, create PR
    return nothing
end

@static if isdefined(Base, Symbol("@main"))
    @main
end

end
