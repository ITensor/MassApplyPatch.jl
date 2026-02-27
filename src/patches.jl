# Built-in patches.

# Patch utilities.

using ITensorFormatter: ITensorFormatter
using Pkg: Pkg
using TOML: TOML

function is_stdlib_uuid(uuid_str::AbstractString)
    try
        uuid = Base.UUID(uuid_str)
        if isdefined(Pkg.Types, :is_stdlib)
            return Pkg.Types.is_stdlib(uuid)
        end
        if isdefined(Pkg.Types, :stdlibs)
            stdlibs = Pkg.Types.stdlibs()
            for (k, v) in pairs(stdlibs)
                try
                    Base.UUID(string(k)) == uuid && return true
                catch
                end
                try
                    Base.UUID(string(v)) == uuid && return true
                catch
                end
            end
        end
        return false
    catch
        return false
    end
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

function project_depnames(project::AbstractDict; include_weakdeps::Bool = true)
    depnames = Set{String}()
    deps = get(project, "deps", Dict{String, Any}())
    weakdeps = if include_weakdeps
        get(project, "weakdeps", Dict{String, Any}())
    else
        Dict{String, Any}()
    end
    for (name, uuid) in pairs(deps)
        push!(depnames, String(name))
    end
    for (name, uuid) in pairs(weakdeps)
        push!(depnames, String(name))
    end
    return depnames
end

function project_stdlib_depnames(project::AbstractDict; include_weakdeps::Bool = true)
    stdlibs = Set{String}()
    deps = get(project, "deps", Dict{String, Any}())
    weakdeps = if include_weakdeps
        get(project, "weakdeps", Dict{String, Any}())
    else
        Dict{String, Any}()
    end
    for (name, uuid) in pairs(deps)
        if (uuid isa AbstractString && is_stdlib_uuid(uuid)) || is_stdlib_name(String(name))
            push!(stdlibs, String(name))
        end
    end
    for (name, uuid) in pairs(weakdeps)
        if (uuid isa AbstractString && is_stdlib_uuid(uuid)) || is_stdlib_name(String(name))
            push!(stdlibs, String(name))
        end
    end
    return stdlibs
end

function add_registry_deps_to_temp_env!(names::Set{String})
    specs = [Pkg.PackageSpec(; name) for name in sort!(collect(names))]
    return try
        Pkg.add(specs; io = devnull)
    catch err
        @warn "Failed to add all dependencies in a single call; falling back to per-package adds." exception =
            (err, catch_backtrace())
        for spec in specs
            try
                Pkg.add(spec; io = devnull)
            catch inner_err
                @warn "Could not add dependency $(spec.name) while inferring compat; skipping." exception =
                    (inner_err, catch_backtrace())
            end
        end
    end
end

function versions_by_name()
    depinfo = Pkg.dependencies()
    by_name = Dict{String, VersionNumber}()
    for (_, info) in depinfo
        isnothing(info.name) && continue
        isnothing(info.version) && continue
        by_name[String(info.name)] = info.version
    end
    return by_name
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
    depnames = project_depnames(project; include_weakdeps)
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
        for pkg in sort!(collect(missing))
            haskey(inferred, pkg) ||
                error("Could not infer compat entry for dependency \"$pkg\".")
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
    names = project_depnames(project; include_weakdeps)
    stdlib_names = project_stdlib_depnames(project; include_weakdeps)

    inferred = Dict{String, String}()
    isempty(names) && return inferred

    previous_project = Base.active_project()
    mktempdir() do tmp
        try
            Pkg.activate(tmp; io = devnull)
            is_package_project = haskey(project, "name") && haskey(project, "uuid")
            pkg_name = get(project, "name", nothing)
            entryfile = if pkg_name isa AbstractString
                joinpath(project_dir, "src", "$(pkg_name).jl")
            else
                ""
            end
            is_developable_project =
                is_package_project && pkg_name isa AbstractString &&
                isfile(entryfile)
            if is_developable_project
                try
                    Pkg.develop(; path = project_dir, io = devnull)
                    Pkg.resolve(; io = devnull)
                catch err
                    @warn "Failed to develop/resolve project at $project_dir while inferring compat, falling back to adding deps by name." exception =
                        (err, catch_backtrace())
                    add_registry_deps_to_temp_env!(names)
                end
            else
                add_registry_deps_to_temp_env!(names)
            end

            by_name = versions_by_name()
            missing_names = setdiff(names, Set(keys(by_name)))
            if !isempty(missing_names)
                add_registry_deps_to_temp_env!(missing_names)
                by_name = versions_by_name()
            end

            for name in sort!(collect(names))
                if name ∈ stdlib_names
                    inferred[name] = String(stdlib_compat)
                    continue
                end
                version = get(by_name, name, nothing)
                isnothing(version) && continue
                inferred[name] = compat_lower_bound(version)
            end
        finally
            if !isnothing(previous_project)
                Pkg.activate(dirname(previous_project); io = devnull)
            end
        end
    end

    return inferred
end

function read_version_cmd(cmd::Cmd)
    try
        return VersionNumber(strip(readchomp(cmd)))
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
