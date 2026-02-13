using Aqua: Aqua
using MassApplyPatch: MassApplyPatch
using Test: @testset

@testset "Code quality (Aqua.jl)" begin
    Aqua.test_all(MassApplyPatch)
end
