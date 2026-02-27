# Built-in patches.

# Patch utilities.

using ITensorFormatter: ITensorFormatter
using Pkg: Pkg
using TOML: TOML

function resolve_compat_entries(
        project_toml::AbstractString,
        entries::AbstractDict{<:AbstractString, <:Union{Nothing, AbstractString}};
        include_weakdeps::Bool = true,
        include_julia::Bool = true,
        allow_install_juliaup::Bool = true,
        julia_fallback::AbstractString = "1.10"
    )
    needs_inference = [
        String(pkg) for (pkg, compat_entry) in entries
            if compat_entry === nothing && String(pkg) != "julia"
    ]
    inferred = if isempty(needs_inference)
        Dict{String, String}()
    else
        infer_compat_entries(project_toml; include_weakdeps)
    end
    resolved = Dict{String, String}()
    for (pkg, compat_entry) in entries
        pkg_str = String(pkg)
        if compat_entry !== nothing
            resolved[pkg_str] = String(compat_entry)
        elseif pkg_str == "julia"
            resolved["julia"] =
                lts_julia_compat(; allow_install_juliaup, fallback = julia_fallback)
        else
            haskey(inferred, pkg_str) ||
                error("Could not infer compat entry for dependency \"$pkg_str\".")
            resolved[pkg_str] = inferred[pkg_str]
        end
    end
    if include_julia && !haskey(entries, "julia")
        resolved["julia"] =
            lts_julia_compat(; allow_install_juliaup, fallback = julia_fallback)
    end
    return resolved
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
    add_compat_entries!(project_toml, entries)
    add_compat_entries!(project_toml; include_weakdeps=true, include_julia=true, kwargs...)

Add or update `[compat]` entries in a `Project.toml` file.
If a compat value is `nothing`, the bound is inferred from resolved dependencies.
By default, a Julia compat entry is added from Julia LTS.
"""
function add_compat_entries!(
        project_toml::AbstractString,
        entries::AbstractDict{<:AbstractString, <:Union{Nothing, AbstractString}};
        include_weakdeps::Bool = true,
        include_julia::Bool = true,
        allow_install_juliaup::Bool = true,
        julia_fallback::AbstractString = "1.10"
    )
    resolved = resolve_compat_entries(
        project_toml,
        entries;
        include_weakdeps,
        include_julia,
        allow_install_juliaup,
        julia_fallback
    )
    return write_compat_entries!(project_toml, resolved)
end

function add_compat_entries!(
        project_toml::AbstractString;
        include_weakdeps::Bool = true,
        include_julia::Bool = true,
        allow_install_juliaup::Bool = true,
        julia_fallback::AbstractString = "1.10",
        kwargs...
    )
    entries = Dict{String, Union{Nothing, String}}(
        String(k) => (v === nothing ? nothing : String(v)) for (k, v) in kwargs
    )
    return add_compat_entries!(
        project_toml,
        entries;
        include_weakdeps,
        include_julia,
        allow_install_juliaup,
        julia_fallback
    )
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
        include_weakdeps::Bool = true
    )
    project_toml = abspath(project_toml)
    project_dir = dirname(project_toml)
    project = TOML.parsefile(project_toml)
    deps = get(project, "deps", Dict{String, Any}())
    weakdeps = if include_weakdeps
        get(project, "weakdeps", Dict{String, Any}())
    else
        Dict{String, Any}()
    end
    names = Set(String.(collect(keys(deps))))
    union!(names, String.(collect(keys(weakdeps))))

    inferred = Dict{String, String}()
    isempty(names) && return inferred

    mktempdir() do tmp
        Pkg.activate(tmp)
        Pkg.develop(; path = project_dir)
        Pkg.resolve()
        depinfo = Pkg.dependencies()
        by_name = Dict(info.name => info for (_, info) in depinfo if !isnothing(info.name))
        for name in sort!(collect(names))
            info = get(by_name, name, nothing)
            isnothing(info) && continue
            isnothing(info.version) && continue
            inferred[name] = compat_lower_bound(info.version)
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
    version = read_version_cmd(`julia +lts -e "print(VERSION)"`)
    !isnothing(version) && return version

    allow_install_juliaup || return nothing

    success_quiet(`juliaup --version`) || try_install_juliaup!()
    success_quiet(`juliaup add lts`)
    return read_version_cmd(`julia +lts -e "print(VERSION)"`)
end

function lts_julia_compat(;
        allow_install_juliaup::Bool = true,
        fallback::AbstractString = "1.10"
    )
    version = detect_lts_julia_version(; allow_install_juliaup)
    isnothing(version) && return String(fallback)
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
