using MassApplyPatch: MassApplyPatch
using Test: @test, @testset

@testset "MassApplyPatch" begin
    @test isdefined(MassApplyPatch, :close_issue!)
    @test hasmethod(MassApplyPatch.close_issue!, Tuple{AbstractString})
    @test isdefined(MassApplyPatch, :close_issues!)
    @test hasmethod(
        MassApplyPatch.close_issues!, Tuple{AbstractVector{<:AbstractString}}
    )
    @test isdefined(MassApplyPatch, :close_pr!)
    @test hasmethod(MassApplyPatch.close_pr!, Tuple{AbstractString})
    @test isdefined(MassApplyPatch, :close_prs!)
    @test hasmethod(
        MassApplyPatch.close_prs!, Tuple{AbstractVector{<:AbstractString}}
    )
    @test isdefined(MassApplyPatch, :reopen_issue!)
    @test hasmethod(MassApplyPatch.reopen_issue!, Tuple{AbstractString})
    @test isdefined(MassApplyPatch, :reopen_issues!)
    @test hasmethod(
        MassApplyPatch.reopen_issues!, Tuple{AbstractVector{<:AbstractString}}
    )
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
