module MassApplyPatch

include("main.jl")
include("patches.jl")
include("allow_automerge.jl")
include("branch_protection.jl")
include("merge_pr.jl")
include("close_pr.jl")
include("open_prs.jl")

end
