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

const git = Git.git()

function clone_repo(repo::AbstractString, destdir::AbstractString)
    url = "https://github.com/$repo.git"
    run(`$git clone $url $destdir`)
    return nothing
end

function github_auth()
    # Try gh CLI first, then fall back to ENV
    token = get(ENV, "GITHUB_AUTH", "")
    if isempty(token)
        try
            token = readchomp(`gh auth token`)
        catch
        end
    end
    isempty(token) &&
        error("Install and authenticate the `gh` CLI, or set ENV[\"GITHUB_AUTH\"].")
    return GitHub.authenticate(token)
end

function get_default_branch(repo, auth)
    return getproperty(GitHub.repo(repo; auth), :default_branch)
end

function unique_branch_name(base, git)
    name = base
    i = 1
    while true
        # Check if branch exists locally
        local_exists = success(`$git rev-parse --verify $name`)
        # Check if branch exists remotely by checking output, not just exit code
        remote_output = read(`$git ls-remote --heads origin $name`, String)
        remote_exists = !isempty(strip(remote_output))
        if !local_exists && !remote_exists
            return name
        end
        name = "$(base)-$i"
        i += 1
    end
    return
end

function open_pr(repo, branchname; title, body, auth)
    base = get_default_branch(repo, auth)
    gh_repo = GitHub.Repo(repo)
    org = split(repo, "/")[1]
    head = "$(org):$(branchname)"
    prs, _ = GitHub.pull_requests(
        gh_repo; auth, params = Dict("state" => "open", "head" => head), page_limit = 1
    )
    if !isempty(prs)
        @info "pushed; PR already exists"
        return "pushed (PR already exists)"
    end
    params = Dict(:title => title, :body => body, :base => base, :head => branchname)
    pr = GitHub.create_pull_request(gh_repo; auth, params)
    @info "Created PR: $(pr.html_url)"
    return pr
end

function make_patch_pr(
        patchname, repo::AbstractString;
        branch::AbstractString = default_branch(),
        title::AbstractString = default_title(),
        body::AbstractString = default_body()
    )
    tmpdir = mktempdir()
    repodir = joinpath(tmpdir, split(repo, "/"; limit = 2)[2])
    clone_repo(repo, repodir)
    cd(repodir) do
        branchname = unique_branch_name(branch, git)
        if branchname != branch
            @info "Branch $branch exists, using $branchname instead."
        end
        run(`$git checkout -b $branchname`)
        patch!(patchname, repodir)
        run(`$git add .`)
        run(`$git commit -m $title`)
        run(`$git push origin $branchname`)
        auth = github_auth()
        return open_pr(repo, branchname; title, body, auth)
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
    patchname = nothing
    branch = default_branch()
    title = default_title()
    body = default_body()
    for arg in argv
        if startswith(arg, "--patch=")
            patchname = split(arg, "="; limit = 2)[2]
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
    if isnothing(patchname)
        error("--patch=<patchname> argument required (e.g. --patch=bump_patch_version)")
    end
    for repo in repos
        make_patch_pr(patchname, repo; branch = branch, title = title, body = body)
    end
    return nothing
end

# Patch dispatch system
to_patchname(patchname::AbstractString) = Val(Symbol(patchname))
to_patchname(patchname::Symbol) = Val(patchname)
patch!(patchname, path) = patch!(to_patchname(patchname), path)
patch!(patchname::Val, path) = error("Patch $patchname not implemented.")

# Built-in patches
using TOML: TOML
function patch!(::Val{:bump_patch_version}, path)
    project_toml = joinpath(path, "Project.toml")
    if !isfile(project_toml)
        error("No Project.toml found in $path")
    end
    data = TOML.parsefile(project_toml)
    haskey(data, "version") || error("No version field in $project_toml")
    v = VersionNumber(data["version"])
    new_v = VersionNumber(v.major, v.minor, v.patch + 1)
    data["version"] = string(new_v)
    open(project_toml, "w") do io
        return TOML.print(io, data)
    end
    return nothing
end

@static if isdefined(Base, Symbol("@main"))
    @main
end

end
