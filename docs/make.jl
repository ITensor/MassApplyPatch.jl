using Documenter: Documenter, DocMeta, deploydocs, makedocs
using ITensorFormatter: ITensorFormatter
using MassApplyPatch: MassApplyPatch

DocMeta.setdocmeta!(
    MassApplyPatch, :DocTestSetup, :(using MassApplyPatch); recursive = true
)

ITensorFormatter.make_index!(pkgdir(MassApplyPatch))

makedocs(;
    modules = [MassApplyPatch],
    authors = "ITensor developers <support@itensor.org> and contributors",
    sitename = "MassApplyPatch.jl",
    format = Documenter.HTML(;
        canonical = "https://itensor.github.io/MassApplyPatch.jl",
        edit_link = "main",
        assets = ["assets/favicon.ico", "assets/extras.css"]
    ),
    pages = ["Home" => "index.md", "Reference" => "reference.md"]
)

deploydocs(;
    repo = "github.com/ITensor/MassApplyPatch.jl", devbranch = "main", push_preview = true
)
