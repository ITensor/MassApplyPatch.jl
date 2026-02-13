using MassApplyPatch: MassApplyPatch
using Documenter: Documenter, DocMeta, deploydocs, makedocs

DocMeta.setdocmeta!(
    MassApplyPatch, :DocTestSetup, :(using MassApplyPatch); recursive = true
)

include("make_index.jl")

makedocs(;
    modules = [MassApplyPatch],
    authors = "ITensor developers <support@itensor.org> and contributors",
    sitename = "MassApplyPatch.jl",
    format = Documenter.HTML(;
        canonical = "https://itensor.github.io/MassApplyPatch.jl",
        edit_link = "main",
        assets = ["assets/favicon.ico", "assets/extras.css"],
    ),
    pages = ["Home" => "index.md", "Reference" => "reference.md"],
)

deploydocs(;
    repo = "github.com/ITensor/MassApplyPatch.jl", devbranch = "main", push_preview = true
)
