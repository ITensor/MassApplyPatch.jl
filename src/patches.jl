# Built-in patches.

# Patch utilities.

using ITensorFormatter: ITensorFormatter
using Pkg: Pkg
using TOML: TOML

function dependency_tables(project::AbstractDict; include_weakdeps::Bool = true)
    deps = get(project, "deps", Dict{String, Any}())
    if include_weakdeps
        return (deps, get(project, "weakdeps", Dict{String, Any}()))
    end
    return (deps,)
end

function is_stdlib_name(name::AbstractString)
    path = try
        Base.find_package(String(name))
    catch
        nothing
    end
    isnothing(path) && return false
    norm = replace(String(path), '\\' => '/')
    return occursin("/stdlib/", norm)
end

function project_dependency_names(project::AbstractDict; include_weakdeps::Bool = true)
    names = Set{String}()
    stdlibs = Set{String}()
    for table in dependency_tables(project; include_weakdeps)
        for (name, _) in pairs(table)
            name = String(name)
            push!(names, name)
            is_stdlib_name(name) && push!(stdlibs, name)
        end
    end
    return names, stdlibs
end

function is_developable_project(project::AbstractDict, project_dir::AbstractString)
    pkg_name = get(project, "name", nothing)
    pkg_name isa AbstractString || return false
    return haskey(project, "uuid") && isfile(joinpath(project_dir, "src", "$(pkg_name).jl"))
end

function run_capture(cmd::Cmd)
    out = IOBuffer()
    err = IOBuffer()
    proc = run(pipeline(ignorestatus(cmd); stdout = out, stderr = err))
    if !success(proc)
        stdout_str = strip(String(take!(out)))
        stderr_str = strip(String(take!(err)))
        msg = IOBuffer()
        println(msg, "Failed to run command")
        println(msg, "Command: $(cmd)")
        println(msg, "Exit code: $(proc.exitcode)")
        !isempty(stdout_str) && println(msg, "stdout:\n$stdout_str")
        !isempty(stderr_str) && println(msg, "stderr:\n$stderr_str")
        error(String(take!(msg)))
    end
    return String(take!(out))
end

function infer_versions_in_subprocess(
        names::Set{String};
        project_dir::Union{Nothing, AbstractString} = nothing
    )
    isempty(names) && return Dict{String, VersionNumber}()

    script = """
    using Pkg
    names = String.(filter(!isempty, split(get(ENV, "MAP_DEP_NAMES", ""), '\\n')))
    names_set = Set(names)
    Pkg.activate(mktempdir(); io = devnull)

    if get(ENV, "MAP_DEVELOP_PROJECT", "0") == "1"
        try
            Pkg.develop(; path = ENV["MAP_PROJECT_DIR"], io = devnull)
            Pkg.resolve(; io = devnull)
        catch
        end
    end

    function versions_by_name()
        return Dict(
            String(info.name) => info.version for
            (_, info) in Pkg.dependencies() if !isnothing(info.name) && !isnothing(info.version)
        )
    end

    by_name = versions_by_name()
    missing = setdiff(names_set, Set(keys(by_name)))
    if !isempty(missing)
        specs = [Pkg.PackageSpec(; name) for name in sort(collect(missing))]
        try
            Pkg.add(specs; io = devnull)
        catch
            for spec in specs
                try
                    Pkg.add(spec; io = devnull)
                catch
                end
            end
        end
        by_name = versions_by_name()
    end

    for name in sort(names)
        version = get(by_name, name, nothing)
        isnothing(version) && continue
        println(name, "=", version)
    end
    """

    env = Dict(
        "MAP_DEP_NAMES" => join(sort(collect(names)), "\n"),
        "MAP_DEVELOP_PROJECT" => isnothing(project_dir) ? "0" : "1",
        "MAP_PROJECT_DIR" => isnothing(project_dir) ? "" : String(project_dir)
    )
    julia_cmd = Base.julia_cmd()
    cmd = setenv(
        `$julia_cmd --startup-file=no --history-file=no --color=no -e $script`,
        env
    )
    output = run_capture(cmd)

    inferred = Dict{String, VersionNumber}()
    for line in split(chomp(output), '\n')
        isempty(line) && continue
        parts = split(line, '='; limit = 2)
        length(parts) == 2 || continue
        name, version = parts
        try
            inferred[String(name)] = VersionNumber(String(version))
        catch
        end
    end
    return inferred
end

function write_compat_entries!(
        project_toml::AbstractString,
        entries::AbstractDict{<:AbstractString, <:AbstractString}
    )
    data = TOML.parsefile(project_toml)
    compat = get!(data, "compat", Dict{String, Any}())
    for (pkg, compat_entry) in entries
        compat[String(pkg)] = String(compat_entry)
    end
    data["compat"] = compat
    open(project_toml, "w") do io
        return TOML.print(io, data)
    end
    ITensorFormatter.format_project_toml!(project_toml)
    return nothing
end

"""
    add_compat_entries!(project_toml; include_weakdeps=true, include_julia=nothing)

Add missing `[compat]` entries in a `Project.toml` file.
Existing `[compat]` entries are preserved as-is.

Missing entries are computed as:

  - package names in `[deps]` (and optionally `[weakdeps]`)
  - minus existing package names in `[compat]`

By default, `julia` compat is added only for package projects (those with both
`name` and `uuid` fields). For sub-environments like `test/docs/examples`,
`julia` compat is skipped unless `include_julia=true` is passed explicitly.
"""
function add_compat_entries!(
        project_toml::AbstractString;
        include_weakdeps::Bool = true,
        include_julia::Union{Nothing, Bool} = nothing,
        allow_install_juliaup::Bool = true,
        julia_fallback::Union{Nothing, AbstractString} = nothing
    )
    project = TOML.parsefile(project_toml)
    is_package_project = haskey(project, "name") && haskey(project, "uuid")
    include_julia = isnothing(include_julia) ? is_package_project : include_julia
    compat = get(project, "compat", Dict{String, Any}())
    depnames, _ = project_dependency_names(project; include_weakdeps)
    existing_compat = Set{String}(String.(keys(compat)))
    missing = setdiff(depnames, existing_compat)
    julia_compat_target = if haskey(compat, "julia")
        String(compat["julia"])
    else
        lts_julia_compat(; allow_install_juliaup, fallback = julia_fallback)
    end

    additions = Dict{String, String}()
    if !isempty(missing)
        inferred = infer_compat_entries(
            project_toml;
            include_weakdeps,
            stdlib_compat = julia_compat_target
        )
        uninferred = setdiff(missing, Set(keys(inferred)))
        isempty(uninferred) || error(
            "Could not infer compat entry for dependencies: $(join(sort(collect(uninferred)), ", "))."
        )
        for pkg in sort(collect(missing))
            additions[pkg] = inferred[pkg]
        end
    end
    if include_julia && !haskey(compat, "julia")
        additions["julia"] = julia_compat_target
    end

    isempty(additions) && return nothing
    return write_compat_entries!(project_toml, additions)
end

function compat_lower_bound(v::VersionNumber)
    return if v.major > 0
        "$(v.major).$(v.minor)"
    elseif v.minor > 0
        "0.$(v.minor)"
    else
        "0.0.$(v.patch)"
    end
end

function infer_compat_entries(
        project_toml::AbstractString;
        include_weakdeps::Bool = true,
        stdlib_compat::AbstractString = "$(VERSION.major).$(VERSION.minor)"
    )
    project_toml = abspath(project_toml)
    project_dir = dirname(project_toml)
    project = TOML.parsefile(project_toml)
    names, stdlib_names = project_dependency_names(project; include_weakdeps)

    inferred = Dict{String, String}()
    isempty(names) && return inferred

    nonstdlib_names = setdiff(names, stdlib_names)
    project_dir_for_develop =
        is_developable_project(project, project_dir) ? project_dir : nothing
    versions = infer_versions_in_subprocess(
        nonstdlib_names;
        project_dir = project_dir_for_develop
    )

    for name in sort(collect(names))
        if name ∈ stdlib_names
            inferred[name] = String(stdlib_compat)
            continue
        end
        version = get(versions, name, nothing)
        isnothing(version) && continue
        inferred[name] = compat_lower_bound(version)
    end

    return inferred
end

function read_version_cmd(cmd::Cmd)
    try
        return VersionNumber(strip(read_quiet(cmd, String)))
    catch
        return nothing
    end
end

function try_install_juliaup!()
    if Sys.isapple() || Sys.islinux()
        ok = success_quiet(
            `sh -c "curl -fsSL https://install.julialang.org | sh -s -- --yes"`
        )
        juliaup_bin = joinpath(homedir(), ".juliaup", "bin")
        if isdir(juliaup_bin)
            ENV["PATH"] = string(juliaup_bin, ":", get(ENV, "PATH", ""))
        end
        return ok
    end
    return false
end

function detect_lts_julia_version(; allow_install_juliaup::Bool = true)
    version = read_version_cmd(`julia +lts --startup-file=no -e "print(VERSION)"`)
    !isnothing(version) && return version

    allow_install_juliaup || return nothing

    success_quiet(`juliaup --version`) || try_install_juliaup!()
    success_quiet(`juliaup add lts`)
    return read_version_cmd(`julia +lts --startup-file=no -e "print(VERSION)"`)
end

function lts_julia_compat(;
        allow_install_juliaup::Bool = true,
        fallback::Union{Nothing, AbstractString} = nothing
    )
    version = detect_lts_julia_version(; allow_install_juliaup)
    if isnothing(version)
        if isnothing(fallback)
            return "$(VERSION.major).$(VERSION.minor)"
        end
        return String(fallback)
    end
    return "$(version.major).$(version.minor)"
end

# Utility to bump a VersionNumber
function bump_version(v::VersionNumber, position::Symbol)
    if position === :major
        return VersionNumber(v.major + 1, 0, 0)
    elseif position === :minor
        return VersionNumber(v.major, v.minor + 1, 0)
    elseif position === :patch
        return VersionNumber(v.major, v.minor, v.patch + 1)
    else
        error("position must be :major, :minor, or :patch")
    end
end

# Utility to bump version in Project.toml
function bump_project_toml_version!(path::AbstractString, position::Symbol)
    data = TOML.parsefile(path)
    haskey(data, "version") || error("No version field in $path")
    version = VersionNumber(data["version"])
    new_version = bump_version(version, position)
    data["version"] = string(new_version)
    open(path, "w") do io
        return TOML.print(io, data)
    end
    ITensorFormatter.format_project_toml!(path)
    return nothing
end

for position in (:major, :minor, :patch)
    patchname = Symbol(:bump_, position, :_version)
    @eval function patch!(::Val{$(QuoteNode(patchname))}, path)
        project_toml = joinpath(path, "Project.toml")
        bump_project_toml_version!(project_toml, $(QuoteNode(position)))
        return nothing
    end
end

function patch!(::Val{:format_project_toml}, path)
    project_toml = joinpath(path, "Project.toml")
    ITensorFormatter.format_project_toml!(project_toml)
    return nothing
end
