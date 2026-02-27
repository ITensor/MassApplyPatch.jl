using MassApplyPatch: MassApplyPatch
using Test: @test, @testset

@testset "MassApplyPatch" begin
    @test hasmethod(MassApplyPatch.delete_branches!, Tuple{Function, Vector{String}})
end
