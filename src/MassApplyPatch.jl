module MassApplyPatch

if VERSION >= v"1.11.0-DEV.469"
    let str = "public main"
        eval(Meta.parse(str))
    end
end

function make_patch_pr(patch, repo; branch, title, body)
    @show repo branch title body
    @invokelatest patch()
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
    branch = "masspatch"
    title = "Apply mass patch"
    body = "This PR applies a mass patch."
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
