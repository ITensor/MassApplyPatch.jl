using Git: Git
using GitHub: GitHub
using Suppressor: @suppress

read_quiet(args...; kwargs...) = @suppress read(args...; kwargs...)
run_quiet(args...; kwargs...) = @suppress run(args...; kwargs...)
success_quiet(args...; kwargs...) = @suppress success(args...; kwargs...)

if VERSION >= v"1.11.0-DEV.469"
    let str = "public main"
        eval(Meta.parse(str))
    end
end

# String representation of a patch name, for use in default PR branch
# names, titles, and bodies.
patchname_string(patchname) = patchname_string(to_patchname(patchname))
patchname_string(::Val{patchname}) where {patchname} = "$(patchname)"

default_kwarg(patchname, arg::Symbol) = default_kwarg(patchname, Val(arg))
default_kwarg(patchname, arg::Val) = error("Not defined.")

function default_kwarg(patchname, key::Val{:branch})
    return "$(patchname_string(patchname))-patch"
end
function default_kwarg(patchname, key::Val{:title})
    return "Apply $(patchname_string(patchname)) patch"
end
function default_kwarg(patchname, key::Val{:body})
    return "This PR applies the $(patchname_string(patchname)) patch."
end

const git = Git.git()

function clone_repo(repo::AbstractString, destdir::AbstractString)
    url = "https://github.com/$repo.git"
    run_quiet(`$git clone $url $destdir`)
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
        local_exists = success_quiet(`$git rev-parse --verify $name`)
        # Check if branch exists remotely by checking output, not just exit code
        remote_output = read_quiet(`$git ls-remote --heads origin $name`, String)
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
        return nothing
    end
    params = Dict(:title => title, :body => body, :base => base, :head => branchname)
    pr = GitHub.create_pull_request(gh_repo; auth, params)
    @info "Created PR: $(pr.html_url)"
    return string(pr.html_url)
end

function make_patch_pr(
        patchname, repo::AbstractString;
        branch::AbstractString = default_kwarg(patchname, :branch),
        title::AbstractString = default_kwarg(patchname, :title),
        body::AbstractString = default_kwarg(patchname, :body)
    )
    tmpdir = mktempdir()
    repodir = joinpath(tmpdir, split(repo, "/"; limit = 2)[2])
    clone_repo(repo, repodir)
    url = cd(repodir) do
        branchname = unique_branch_name(branch, git)
        if branchname != branch
            @info "Branch $branch exists, using $branchname instead."
        end
        run_quiet(`$git checkout -b $branchname`)
        patch!(patchname, repodir)
        run_quiet(`$git add .`)
        run_quiet(`$git commit -m $title`)
        run_quiet(`$git push origin $branchname`)
        auth = github_auth()
        return open_pr(repo, branchname; title, body, auth)
    end
    return url
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
    # Get the patch names to determine which patches to apply.
    patchargs = filter(arg -> startswith(arg, "--patch="), argv)
    patchnames = map(arg -> split(arg, "="; limit = 2)[2], patchargs)
    if isempty(patchnames)
        error("--patch=<patchname> argument required (e.g. --patch=bump_patch_version)")
    end
    argv = setdiff(argv, patchargs)
    # Get the repositories to apply the patch to and the rest of the options.
    repos = String[]
    branch = default_kwarg(patchnames, :branch)
    title = default_kwarg(patchnames, :title)
    body = default_kwarg(patchnames, :body)
    for arg in argv
        if startswith(arg, "--branch=")
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
    urls = String[]
    for repo in repos
        url = make_patch_pr(patchnames, repo; branch, title, body)
        push!(urls, url)
    end
    return urls
end

# Patch dispatch system
to_patchname(patchname::AbstractString) = Val(Symbol(patchname))
to_patchname(patchname::Symbol) = Val(patchname)
patch!(patchname, path) = patch!(to_patchname(patchname), path)
patch!(patchname::Val, path) = error("Patch $patchname not implemented.")

struct CompositePatch{Patches}
    patches::Patches
end
to_patchname(patchnames::AbstractArray) = CompositePatch(patchnames)
function patchname_string(patchname::CompositePatch)
    return join(patchname_string.(patchname.patches), "+")
end
function patch!(patchname::CompositePatch, path)
    for patch in patchname.patches
        patch!(patch, path)
    end
    return nothing
end

@static if isdefined(Base, Symbol("@main"))
    @main
end
