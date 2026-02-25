function parse_pr_ref(pr::AbstractString)
    # URL format: https://github.com/OWNER/REPO/pull/123
    m = match(r"github\.com/([^/]+/[^/]+)/pull/([0-9]+)", pr)
    if !isnothing(m)
        repo = String(m.captures[1])
        number = parse(Int, m.captures[2])
        return repo, number
    end

    # Shorthand format: OWNER/REPO#123
    m = match(r"^([^/#]+/[^/#]+)#([0-9]+)$", pr)
    if !isnothing(m)
        repo = String(m.captures[1])
        number = parse(Int, m.captures[2])
        return repo, number
    end

    return error("Unsupported PR reference format: $pr")
end

"""
    pr_statuses(prs::AbstractVector{<:AbstractString})

Return a `Vector{String}` of PR statuses in the same order as `prs`.

Accepted PR formats:

  - `"https://github.com/OWNER/REPO/pull/123"`
  - `"OWNER/REPO#123"`

Statuses are `"draft"` (when draft), otherwise `"open"` or `"closed"`.

Requires: `gh` installed and authenticated (`gh auth login`).
"""
function pr_statuses(prs::AbstractVector{<:AbstractString})
    return map(prs) do pr
        repo, number = parse_pr_ref(pr)
        # Query status via gh CLI to avoid version-specific GitHub.jl field differences.
        return readchomp(
            `gh pr view $number --repo $repo --json state,isDraft --jq '. | if .isDraft then "draft" else (.state | ascii_downcase) end'`
        )
    end
end
