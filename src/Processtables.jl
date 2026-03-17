module ProcessTables

using DataFrames

export ProcessTable, patch!, aggregate, levels, inputs, outputs, scale_processtable, readable #,io_factors

struct ProcessTable     
    df::DataFrame
end

ProcessTable() = ProcessTable(DataFrame(In=Bool[], Out=Bool[], Ref=Bool[], Material=String[], Amount=Float64[], Fix=Bool[], Operation=String[], Volume=Float64[], Mol=Float64[]))
default_data_values = (:In => false, :Out => false, :Ref => false, :Material => missing, :Amount => missing, :Fix => false, :Operation => missing, :Volume => missing, :Mol => missing)

function patch(kvpairs...; default = default_data_values)
	patches = Dict{Symbol, Any}(kvpairs)
	defvalues = last.(default)
	r = Vector()
	i = 1
	for key in first.(default)
		if key in keys(patches)
			push!(r, patches[key])
		else
			push!(r, defvalues[i])
		end
		i += 1
	end
	return r
end

patch!(pt::ProcessTable, patches...) = push!(pt.df, patch(patches...), promote = true)


_movement_sign(in::Bool, out::Bool) = in == out ? 0 : in ? 1 : -1

function aggregate(pt::ProcessTable, fieldname::Symbol) 
	io = pt.df[!, [:In, :Out]]
	transform!(io, [:In, :Out] => ByRow(|) => :IO)
	if String <: eltype(pt.df[:, fieldname])
		pt.df[io[!, :IO], fieldname]
	else
		transform!(io, [:In, :Out] => ByRow(_movement_sign) => :Sign)
		pt.df[io[!, :IO], fieldname] .* io[io[!, :IO], :Sign]		# if column fieldname is a non numeric value, simply return the value
	end
end

function _increm_add(v::Vector{V}) where {V}		# = cumsum-Function !!
	r = Vector{V}()
	for el in v
		push!(r, el + (length(r) >= 1 ? last(r) : 0))
	end
	return r
end

levels(pt::ProcessTable) = _increm_add(aggregate(pt, :Volume))
operations(pt::ProcessTable) = aggregate(pt, :Operation)
inputs(pt::ProcessTable, fieldname::Symbol=:Amount) = subset(pt.df, :In)[!, fieldname]
outputs(pt::ProcessTable, fieldname::Symbol=:Amount) = subset(pt.df, :Out)[!, fieldname]
ios(pt::ProcessTable) = (material = aggregate(pt, :Material), amount = aggregate(pt, :Amount))							#::@NamedTuple
io_factors(pt::ProcessTable, ref_mass::Float64) = (material = ios(pt).material, amount = ios(pt).amount ./ ref_mass)	#::@NamedTuple
reference_mass(pt::ProcessTable) = subset(pt.df, :Out, :Ref)[!, :Amount] |> skipmissing |> sum

function scale_processtable(pt::ProcessTable, factor::Float64)
	# TODO don't scale fixed amounts
	ProcessTable(transform(pt.df, :Amount => ByRow(m -> m * factor), :Volume => ByRow(V -> V * factor), :Mol => ByRow(n -> n * factor); renamecols = false))
end


function readable(pt::ProcessTable)	
    transform(pt.df, 
		:In => ByRow(i -> ifelse(i, "▶", "")),
		:Out => ByRow(o -> ifelse(o, "◀", "")),
		:Ref => ByRow(r -> ifelse(r, "■", "")),
		:Material => ByRow(m -> coalesce(m, "-")), 
		:Amount => ByRow(a -> coalesce(round(a, sigdigits=3), "-")),
		:Fix => ByRow(f -> ifelse(f, "fix", "")),
		:Operation => ByRow(o -> coalesce(o, "-")), 
		:Volume => ByRow(v -> coalesce(round(v), "-")), 
		:Mol => ByRow(n -> coalesce(round(n, sigdigits=5), "-")); 
		renamecols = false
	)
end


end