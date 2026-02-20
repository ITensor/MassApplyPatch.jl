module MassApplyPatch

include("main.jl")
include("patches.jl")
include("allow_automerge.jl")
include("branch_protection.jl")
include("merge_pr.jl")

end
