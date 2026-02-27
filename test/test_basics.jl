using MassApplyPatch: MassApplyPatch
using TOML: TOML
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
    @test hasmethod(MassApplyPatch.delete_branches!, Tuple{Function, Vector{String}})
end

@testset "add_compat_entries!" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            name = "ExamplePkg"
            uuid = "11111111-1111-1111-1111-111111111111"
            version = "0.1.0"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml,
            Dict("julia" => "1.10", "ITensors" => "0.7")
        )
        data = TOML.parsefile(project_toml)
        @test data["compat"]["julia"] == "1.10"
        @test data["compat"]["ITensors"] == "0.7"
    end
end

@testset "add_compat_entries! julia auto" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            name = "ExamplePkg"
            uuid = "11111111-1111-1111-1111-111111111111"
            version = "0.1.0"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml;
            julia = nothing,
            include_julia = false,
            allow_install_juliaup = false,
            julia_fallback = "1.10"
        )
        data = TOML.parsefile(project_toml)
        @test haskey(data["compat"], "julia")
        @test occursin(r"^\d+\.\d+$", data["compat"]["julia"])
    end
end

@testset "compat_lower_bound" begin
    @test MassApplyPatch.compat_lower_bound(v"1.2.3") == "1.2"
    @test MassApplyPatch.compat_lower_bound(v"2.0.0") == "2.0"
    @test MassApplyPatch.compat_lower_bound(v"0.7.4") == "0.7"
    @test MassApplyPatch.compat_lower_bound(v"0.0.5") == "0.0.5"
end
