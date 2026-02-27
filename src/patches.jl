# Built-in patches.

# Patch utilities.

using Pkg: Pkg
using TOML: TOML

"""
    add_compat_entries!(project_toml, entries)
    add_compat_entries!(project_toml; include_weakdeps=true, include_julia=true, kwargs...)

Add or update `[compat]` entries in a `Project.toml` file.

If a compat value is `nothing`, the bound is inferred from resolved dependencies.
By default, a Julia compat entry is added from Julia LTS.

# Examples

  - `add_compat_entries!("Project.toml", Dict("julia" => "1.10", "ITensors" => "0.7"))`
  - `add_compat_entries!("Project.toml"; julia=nothing, ITensors=nothing, NDTensors="0.4")`
"""
function add_compat_entries!(
        project_toml::AbstractString,
        entries::AbstractDict{<:AbstractString, <:Union{Nothing, AbstractString}};
        include_weakdeps::Bool = true,
        include_julia::Bool = true,
        allow_install_juliaup::Bool = true,
        julia_fallback::AbstractString = "1.10"
    )
    infer_names = String[]
    normalized_entries = Dict{String, Union{Nothing, String}}()
    for (pkg, compat_entry) in entries
        pkgname = String(pkg)
        if compat_entry === nothing
            normalized_entries[pkgname] = nothing
            lowercase(pkgname) == "julia" || push!(infer_names, pkgname)
        else
            normalized_entries[pkgname] = String(compat_entry)
        end
    end

    inferred = if isempty(infer_names)
        Dict{String, String}()
    else
        infer_compat_entries(project_toml; include_weakdeps)
    end
    resolved = Dict{String, String}()
    for (pkgname, compat_entry) in normalized_entries
        if compat_entry === nothing
            if lowercase(pkgname) == "julia"
                resolved["julia"] = lts_julia_compat(;
                    allow_install_juliaup, fallback = julia_fallback
                )
            else
                haskey(inferred, pkgname) ||
                    error("Could not infer compat entry for dependency \"$pkgname\".")
                resolved[pkgname] = inferred[pkgname]
            end
        else
            resolved[pkgname] = compat_entry
        end
    end
    if include_julia && !haskey(normalized_entries, "julia")
        resolved["julia"] =
            lts_julia_compat(; allow_install_juliaup, fallback = julia_fallback)
    end

    data = TOML.parsefile(project_toml)
    compat = get!(data, "compat", Dict{String, Any}())
    for (pkg, compat_entry) in resolved
        compat[String(pkg)] = String(compat_entry)
    end
    data["compat"] = compat
    open(project_toml, "w") do io
        return TOML.print(io, data)
    end
    sort_project_toml!(project_toml)
    return nothing
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

"""
    add_compat_entries_auto!(project_toml; include_weakdeps=true, extras=Dict(), include_julia=true)

Infer compat bounds by resolving the package in a temporary environment, then
add/update `[compat]` with those inferred bounds plus any explicit `extras`.
"""
function add_compat_entries_auto!(
        project_toml::AbstractString;
        include_weakdeps::Bool = true,
        extras::AbstractDict{<:AbstractString, <:AbstractString} = Dict{String, String}(),
        include_julia::Bool = true,
        allow_install_juliaup::Bool = true,
        julia_fallback::AbstractString = "1.10"
    )
    inferred = infer_compat_entries(project_toml; include_weakdeps)
    merged = Dict{String, Union{Nothing, String}}(k => v for (k, v) in inferred)
    for (pkg, compat_entry) in extras
        merged[String(pkg)] = String(compat_entry)
    end
    include_julia && !haskey(merged, "julia") && (merged["julia"] = nothing)
    return add_compat_entries!(
        project_toml,
        merged;
        include_weakdeps,
        include_julia = false,
        allow_install_juliaup,
        julia_fallback
    )
end

function sort_project_toml!(path::AbstractString)
    top_key_order = ["name", "uuid", "version", "authors"]
    table_order = [
        "workspace", "deps", "weakdeps", "extensions", "compat", "apps", "extras",
        "targets",
    ]
    is_table(x) = x isa AbstractDict
    raw = read(path, String)
    data = TOML.parse(raw)
    io = IOBuffer()
    scalar_keys = String[]
    for k in top_key_order
        haskey(data, k) && !is_table(data[k]) && push!(scalar_keys, k)
    end
    for k in sort(collect(keys(data)))
        !(k in scalar_keys) && !is_table(data[k]) && push!(scalar_keys, k)
    end
    for k in scalar_keys
        TOML.print(io, Dict(k => data[k]))
    end
    table_keys = String[]
    seen = Set{String}()
    for k in table_order
        if haskey(data, k) && is_table(data[k])
            push!(table_keys, k)
            push!(seen, k)
        end
    end
    for k in sort(collect(keys(data)))
        is_table(data[k]) && !(k in seen) && push!(table_keys, k)
    end
    for k in table_keys
        println(io)
        TOML.print(io, Dict(k => data[k]); sorted = true)
    end
    out = String(take!(io))
    endswith(out, "\n") || (out *= "\n")
    out == raw && return false
    write(path, out)
    return true
end

# Strip trailing `.0` segments from a single version string.
# E.g. `"1.10.0"` → `"1.10"`, `"4.0.0"` → `"4"`, `"1.2.3"` → `"1.2.3"`.
function strip_version_zeros(s::AbstractString)
    s = replace(s, r"\.0\.0$" => "")
    s = replace(s, r"\.0$" => "")
    return s
end

# Strip trailing `.0` or `.0.0` from version strings in `[compat]`.
# E.g. `"1.10.0"` → `"1.10"`, `"4.0.0"` → `"4"`. Returns `true` if the file changed.
function strip_compat_trailing_zeros!(path::AbstractString)
    data = TOML.parsefile(path)
    haskey(data, "compat") || return false
    changed = false
    for (pkg, val) in data["compat"]
        # Handle comma-separated version specs like "0.6.2, 0.7"
        parts = map(strip, split(val, ","))
        new_parts = map(strip_version_zeros, parts)
        new_val = join(new_parts, ", ")
        if new_val != val
            data["compat"][pkg] = new_val
            changed = true
        end
    end
    changed || return false
    open(path, "w") do io
        return TOML.print(io, data)
    end
    sort_project_toml!(path)
    return true
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
    # Re-format after writing to ensure canonical ordering
    sort_project_toml!(path)
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
    strip_compat_trailing_zeros!(project_toml)
    return nothing
end
