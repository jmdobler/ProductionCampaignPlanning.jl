module Catalogues

export Catalogue

using DataFrames, CSV

struct Catalogue
    file::String
    data::DataFrame
    index_keys::Vector{String}
    primary_key::String
    registry::Dict
end

function open(fname::String; kwargs...)
    regs = Dict(kwargs...)
    data = CSV.read(joinpath(@__DIR__, fname), DataFrame)

    potential_index_keys = names(data, eltype.(eachcol(data)) .<: AbstractString)
    checks = [length(unique(data[:, i])) > 0.8 * length(data[:, i]) for i in potential_index_keys]
    index_keys = [ikey for (i, ikey) in enumerate(potential_index_keys) if checks[i] == true]

    return Catalogue(fname, data, index_keys, index_keys[1], regs)
end

#
# new("filename", Dichte = Float64[], Molgewicht = Float64[]; density = :Dichte, molweight = :Molgewicht)
#
function fieldtypes()
    Dict(
        density => Float64,
        molweight => Float64,
        assay => Float64
    )
end

function new(fname::String, args...; kwargs...)
    # args: name[]
    regs = Dict(kwargs...)
    columns = values(regs)
    @info columns
    data = DataFrame(args)
    #data = CSV.write()
end


end