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
            [deps]
            ExistingDep = "22222222-2222-2222-2222-222222222222"
            [compat]
            ExistingDep = "0.3"
            """
        )
        MassApplyPatch.add_compat_entries!(project_toml; include_julia = false)
        data = TOML.parsefile(project_toml)
        @test data["compat"]["ExistingDep"] == "0.3"
        @test length(keys(data["compat"])) == 1
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
            allow_install_juliaup = false,
            julia_fallback = "1.10"
        )
        data = TOML.parsefile(project_toml)
        @test haskey(data["compat"], "julia")
        @test occursin(r"^\d+\.\d+$", data["compat"]["julia"])
    end
end

@testset "add_compat_entries! unnamed project file" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            [deps]
            JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml;
            include_julia = false,
            allow_install_juliaup = false
        )
        data = TOML.parsefile(project_toml)
        @test haskey(data, "compat")
        @test haskey(data["compat"], "JSON")
    end
end

@testset "add_compat_entries! unnamed project skips julia by default" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            [deps]
            JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml;
            allow_install_juliaup = false
        )
        data = TOML.parsefile(project_toml)
        @test !haskey(data["compat"], "julia")
    end
end

@testset "add_compat_entries! includes weakdeps" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            name = "ExamplePkg"
            uuid = "11111111-1111-1111-1111-111111111111"
            version = "0.1.0"
            [deps]
            JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            [weakdeps]
            HDF5 = "f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f"
            [compat]
            JSON = "1.4"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml;
            include_julia = false,
            allow_install_juliaup = false
        )
        data = TOML.parsefile(project_toml)
        @test haskey(data["compat"], "JSON")
        @test haskey(data["compat"], "HDF5")
    end
end

@testset "add_compat_entries! includes stdlib deps" begin
    mktempdir() do dir
        project_toml = joinpath(dir, "Project.toml")
        write(
            project_toml,
            """
            name = "ExamplePkg"
            uuid = "11111111-1111-1111-1111-111111111111"
            version = "0.1.0"
            [deps]
            Random = "9a3f8284-686f-5f34-9a11-845980a1fd5c"
            """
        )
        MassApplyPatch.add_compat_entries!(
            project_toml;
            include_julia = true,
            allow_install_juliaup = false,
            julia_fallback = "1.10"
        )
        data = TOML.parsefile(project_toml)
        @test occursin(r"^\d+\.\d+$", data["compat"]["julia"])
        @test haskey(data["compat"], "Random")
        @test data["compat"]["Random"] == data["compat"]["julia"]
    end
end

@testset "compat_lower_bound" begin
    @test MassApplyPatch.compat_lower_bound(v"1.2.3") == "1.2"
    @test MassApplyPatch.compat_lower_bound(v"2.0.0") == "2.0"
    @test MassApplyPatch.compat_lower_bound(v"0.7.4") == "0.7"
    @test MassApplyPatch.compat_lower_bound(v"0.0.5") == "0.0.5"
end
