# Built-in patches.

# Patch utilities.

using TOML: TOML

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
