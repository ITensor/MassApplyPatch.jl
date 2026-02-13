module MassApplyPatch

if VERSION >= v"1.11.0-DEV.469"
    let str = "public main"
        eval(Meta.parse(str))
    end
end

"""
    MassApplyPatch.main(argv)

Command line interface for MassApplyPatch.

Arguments:

  - `argv`: Command line arguments. Expected format:
    massapplypatch <org/repo>... --patch <patchfile> [--branch <branchname>] [--title <prtitle>] [--body <prbody>]

The patch function should be provided as a Julia file, which is included and must define a function `patch(repo_path)`.
"""
function main(argv)
    repos = String[]
    patchfile = nothing
    branchname = "masspatch"
    prtitle = "Apply mass patch"
    prbody = "This PR applies a mass patch."
    for arg in argv
        if arg == "--patch"
            patchfile = arg
        elseif arg == "--branch"
            branchname = arg
        elseif arg == "--title"
            prtitle = arg
        elseif arg == "--body"
            prbody = arg
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(repos, arg)
        end
    end
    if isnothing(patchfile)
        error("--patch <patchfile> argument required")
    end
    # Load patch function
    patchfn = nothing
    Base.include(Main, patchfile)
    if isdefined(Main, :patch)
        patchfn = getfield(Main, :patch)
    else
        error("Patch file must define a function 'patch(repo_path)'.")
    end
    # TODO: Clone each repo, apply patchfn, create PR
    return nothing
end

@static if isdefined(Base, Symbol("@main"))
    @main
end

end
