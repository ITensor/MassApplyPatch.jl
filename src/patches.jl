# Built-in patches.

# Patch utilities.

function format_project_toml(path::AbstractString)
    top_key_order = ["name", "uuid", "version", "authors"]
    table_order =
        ["workspace", "deps", "weakdeps", "extensions", "compat", "extras", "targets"]
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

# bump_patch_version patch.
using TOML: TOML
function patch!(::Val{:bump_patch_version}, path)
    project_toml = joinpath(path, "Project.toml")
    if !isfile(project_toml)
        error("No Project.toml found in $path")
    end
    # Bump patch version
    data = TOML.parsefile(project_toml)
    haskey(data, "version") || error("No version field in $project_toml")
    v = VersionNumber(data["version"])
    new_v = VersionNumber(v.major, v.minor, v.patch + 1)
    data["version"] = string(new_v)
    open(project_toml, "w") do io
        return TOML.print(io, data)
    end
    # Re-format after writing to ensure canonical ordering
    format_project_toml(project_toml)
    return nothing
end
