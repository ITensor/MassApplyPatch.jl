using MassApplyPatch: MassApplyPatch
using Test: @test, @testset

@testset "MassApplyPatch" begin
    @test isdefined(MassApplyPatch, :open_issues)
    @test hasmethod(MassApplyPatch.open_issues, Tuple{AbstractString})
    @test hasmethod(
        MassApplyPatch.open_issues, Tuple{AbstractVector{<:AbstractString}}
    )
    @test isdefined(MassApplyPatch, :filter_open_issues)
    @test hasmethod(
        MassApplyPatch.filter_open_issues,
        Tuple{AbstractVector{<:AbstractString}, Function}
    )
end
