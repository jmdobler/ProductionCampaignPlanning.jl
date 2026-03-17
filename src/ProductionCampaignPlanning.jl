module ProductionCampaignPlanning

include("Processtables.jl")
import .ProcessTables as PT
using .ProcessTables, DataFrames, CSV

include("Catalogues.jl")
import .Catalogues as CAT
using .Catalogues


export Step, charge, operate, resume, filtrate, release, complete, transfer, implement, implement!, cakewash			# dose, distill, extract
export Stage, MaxBatchsize, Scalefactor, FixedBatchsize, OptimalBatchsize, scale, produce
export Campaign

		
# Import catalogues
equipment_catalogue = CSV.read(joinpath(@__DIR__, "equipment_volumes.csv"), DataFrame)
substances_catalogue = CSV.read(joinpath(@__DIR__, "substances.csv"), DataFrame)

# TODO add a specific materials_catalogue that keeps all process related materials / streams.
# TODO this should be exported into a separate csv-file and loaded at the start of a project
# TODO figure out how to add user input a) by function call? b) by input prompt? - but how a about Pluto notebooks. Can these take prompt inputs? Check

current_stage = nothing
current_step = nothing


function _lookup(item::String, catalogue::DataFrame, information::Info = All()) where Info 			#{All, Vector{Symbol}, Symbol}
	cols = propertynames(catalogue)
	lookup_key = :Name in cols ? :Name : Symbol(names(catalogue, InlineString)[1])
	hits = catalogue[catalogue[!, lookup_key] .== item, information]
	if isempty(hits) 
		missing
	else 
		size(hits, 1) > 1 && @info "$(size(hits, 1)) Treffer zu '$(item)' gefunden."
		first(hits)
	end												
end


# Definitions

"""
Die Step Datenstruktur ist die kleinste zusammenhängende Einheit, die einen Prozessschritt repräsentiert. Um einen Prozessschritt zu beschreiben
wird ein Step Element erstellt. 

prozessschritt = Step("Name des Prozessschritts", ["Ressourcen Name"])

	* Name muss eindeutig sein
	* Ressource ist eine abstraktere Art der Beschreibung, z.B. Synthesereaktor, Destillatvorlage (keine Apparatebezeichnung). 
	  Ein Prozessschritt kann auch außerhalb von Anlagen ablaufen, deshalb kann die Angabe einer Ressource entfallen.

Mit einer Reihe von Funktionen können dem Prozessschritt Arbeitsvorgänge zugeordnet werden. Jede diese Funktionen ergänzten die dem Prozessschritt
zugrunde liegende Prozesstabelle. Diese ist im `data`-Feld des Step-Objekts tabellarisch hinterlegt.

# Beispiel: Auflösen des Rohstoffs Carbonsäure bei 50°C in Ethylacetat als Lösemittel
```julia-repl
carbonsäure_Lösung = Step("15%ige Säurelösung ", "Dosiervorlage")
charge("Carbonsäure", 55)
charge("Ethylacetat", 310)
operate("rühren und bis 50°C erwärmen")
carbonsäure_Lösung.data

3×9 DataFrame
 Row │ In     Out    Ref    Material     Amount     Fix    Operation                     Volume     Mol      
     │ Bool   Bool   Bool   String?      Float64?   Bool   String?                       Float64?   Float64?
─────┼───────────────────────────────────────────────────────────────────────────────────────────────────────
   1 │  true  false  false  Carbonsäure       55.0  false  missing                            55.0   missing
   2 │  true  false  false  Ethylacetat      310.0  false  missing                           310.0   missing
   3 │ false  false  false  missing      missing    false  rühren und bis 50°C erwärmen  missing     missing
```

Ein oder mehrere Step-Prozessschritte werden in einer Stufe (Stage-Typ) zusammengefasst. Wird vor der Definition des Prozessschritt eine Stufe definiert, so werden alle folgenden 
Prozessschritte dieser Stufe zugeordnet. Ohne vorherige Anlage einer Stufe, wird ein Fehler ausgelöst.
"""
struct Step
	data::ProcessTable
	name::String
	resource::Union{String, Missing}
end

# ScalingOptions
# a Stage is contructed with a specified way how it will scale 

abstract type AbstractScalingOption end

struct FixedBatchsize <: AbstractScalingOption; value::Float64; end
struct Scalefactor <: AbstractScalingOption; value::Float64; end
struct MaxBatchsize <: AbstractScalingOption end
struct OptimalBatchsize <: AbstractScalingOption end


struct Stage{ScalingOption <: AbstractScalingOption} 
	steps::Vector{Step}
	name::String
	product::String
	implementation::Dict{String, String}
	scaling::ScalingOption  
end

function Stage(stage_name::String, product_name, implementations...; scaling::ScalingOption = MaxBatchsize()) where ScalingOption <: AbstractScalingOption 
	sg = Stage(Step[], stage_name, product_name, Dict{String, String}(implementations), scaling)
	global current_stage = sg
end

function scaling(stage::Stage, scaling_option::ScalingOption) where ScalingOption <: AbstractScalingOption
	if stage.scaling == scaling_option
		return stage
	else
		return Stage(stage.steps, stage.name, stage.product, stage.implementation, scaling_option)
	end
end



function Step(stepname, resource_name = missing) 
	stp = Step(ProcessTable(), stepname, resource_name)
	current_stage === nothing && error("es wurde keine Stufe definiert. Bitte zuvor die zugehörige Stufe anlegen. stufe = Stage(\"Name_der_Stufe\")")
	push!(current_stage.steps, stp)
	global current_step = stp
end


struct Campaign
	product::String
	process::ProcessTable
	batches::Float64
end

Campaign(product_name::String, process::ProcessTable, batch_count::Int64) = Campaign(product_name, process, Float64(batch_count))
#Campaign(product_name::String, s::Tuple{ProcessTable, Int64}) = Campaign(product_name, first(s), last(s))
levels(campaign::Campaign) = ProcessTables.levels(campaign.process)


# Class Functions
# with regards to Step struct

input_amounts(step::Step) = inputs(step.data)
output_amounts(step::Step) = outputs(step.data)
materials(step::Step) = aggregate(step.data, :Material)
amounts(step::Step) = aggregate(step.data, :Amount)
volumes(step::Step) = aggregate(step.data, :Volume)
levels(step::Step) = ProcessTables.levels(step.data)

molweight(substance) = _lookup(substance, substances_catalogue, :Molgewicht)
assay(substance) = _lookup(substance, substances_catalogue, :Gehalt)
density(substance, default_density_value::Float64=1.0) = coalesce(_lookup(substance, substances_catalogue, :Dichte), default_density_value)


# Process Operation Functions

function charge!(step::Step, substance, amount; fix::Bool=false, reference::Bool=false) 
	patch!(step.data, 
		:In => true, 
		:Material => substance, 
		:Amount => amount, 
		:Ref => reference, 
		:Fix => fix, 
		:Operation => "charge $(substance)",
		:Volume => amount / density(substance), 
		:Mol => (assay(substance) / 100) * amount / molweight(substance)
	)
end

charge(substance, amount; fix::Bool=false, reference::Bool=false) = charge!(current_step, substance, amount; fix=fix, reference=reference)

function operate!(step::Step, operation) 
	patch!(step.data, :Operation => operation)
end

operate(operation) = operate!(current_step, operation)

function resume!(step::Step, preceding_step::Step) 
	patch!(step.data,
		:In => true,
		:Material => preceding_step.name,
		:Amount => sum(amounts(preceding_step)),
		:Operation => "resume with $(preceding_step.name)",
		:Volume => levels(preceding_step)[end]
	)
end

resume(preceding_step::Step) = resume!(current_step, preceding_step)

function transfer!(step::Step, preceding_step::Step, fraction::Float64=1.0)
	transferred_amount = sum(amounts(preceding_step)) * fraction
	transferred_volume = levels(preceding_step)[end] * fraction

	patch!(step.data,
		:In => true, 
		:Material => preceding_step.name,
		:Operation => fraction == 1.0 ? "receive all of $(preceding_step.name)" : (fraction == 0.5 ? "receive half of $(preceding_step.name)" : "receive " * string(Int(round((fraction) * 100))) * "% of ($(preceding_step.name))"),
		:Amount => transferred_amount,
		:Volume => transferred_volume
	)
	patch!(preceding_step.data,
		:Out => true, 
		:Material => preceding_step.name,
		:Operation => fraction == 1.0 ? "transfer all of $(preceding_step.name)" : (fraction == 0.5 ? "transfer half of $(preceding_step.name)" : "transfer " * string(Int(round((fraction) * 100))) * "% of ($(preceding_step.name))"),
		:Amount => transferred_amount,
		:Volume => transferred_volume
	)	
end

transfer(preceding_step::Step, fraction::Float64=1.0) = transfer!(current_step, preceding_step, fraction)

function filtrate!(step::Step, suspension::Step, cake::String, liquor::String, liquor_amount)			# fraction=1.0, like transfer function
	operate!(step, "filtrate " * suspension.name)
	suspension_amount = sum(amounts(suspension)) 

	patch!(step.data, 
		:In	=> true, 
		:Out => true, 
		:Material => liquor,
		:Amount => liquor_amount,
		:Operation => "eject $(liquor)",
		:Volume => liquor_amount / density(liquor), 								
		:Mol => (assay(liquor) / 100) * liquor_amount / molweight(liquor)			
	)
	
	cake_amount = suspension_amount - liquor_amount

	patch!(step.data,
		:In => true,
		:Material => cake,
		:Amount => cake_amount,
		:Operation => "collect $(cake) as filter cake",
		:Volume => cake_amount / density(cake),
		:Mol => (assay(cake) / 100) * cake_amount / molweight(cake)
	)
end

filtrate(suspension::Step, cake::String, liquor::String, liquor_amount) = filtrate!(current_step, suspension, cake, liquor, liquor_amount)
filtrate(suspension::Step, cake::String, cake_amount, liquor::String) = filtrate!(current_step, suspension, cake, liquor, (sum(amounts(suspension)) - cake_amount))

function cakewash!(step::Step, material, amount)
	patch!(step.data,
		:In => true, 
		:Out => true,
		:Material => material,
		:Amount => amount,
		:Volume => amount / density(material),
		:Mol => (assay(material) / 100) * amount / molweight(material),
		:Operation => "wash cake with $(material)"	
	)
end

cakewash(material, amount) = cakewash!(current_step, material, amount)

function release!(step::Step, material, amount; fix::Bool=false, reference::Bool=false) 
	patch!(step.data,
		:Out => true, 
		:Material => material,
		:Amount => amount,
		:Ref => reference,
		:Operation => "receive $(material)",
		:Fix => fix,
		:Volume => amount / density(material),
		:Mol => (assay(material) / 100) * amount / molweight(material)
	)
end

release(material, amount; fix::Bool=false, reference::Bool=false) = release!(current_step, material, amount; fix=fix, reference=reference)



# with regards to Stage struct

stepnames(stage::Stage) = collect([step.name for step in stage.steps])
resources(stage::Stage) = collect([step.resource for step in stage.steps])
unitnames(stage::Stage) = []

processdata(step::Step) = step.data.df

# complete(stage::Stage) = ProcessTable(vcat(map(processdata, stage.steps)...; source = :StepIndex))    funktioniert ...

function complete(stage::Stage) 
	pt = ProcessTable(vcat(map(processdata, stage.steps)...; source = :StepIndex))
	steps = stepnames(stage)
	resrs = resources(stage)
	# @info steps
	# @info units
	
	pt.df[!, :Step] .= steps[pt.df[!, :StepIndex]] 
	pt.df[!, :Resource] .= resrs[pt.df[!, :StepIndex]]
	pt.df[!, :Unit] .= stage.implementation[pt.df[!, :Resource]]
	return pt
end

materials(stage::Stage) = materials(complete(stage))

Base.getindex(d::Dict{K, V}, keys::Vector{K}) where {K, V} = collect([d[k] for k in keys])		# still required?



# function complete(stage::Stage) 
# 	isempty(stage.implementation) ? error("für die Stufe \"$(stage.name)\" ist keine Implementierung vorgesehen.") :
# 	tbl = vcat(map(processdata, stage.steps)...; source = :StepIndex)
# 	step_names = stepnames(stage)
# 	step_units = unitnames(stage)
# 	tbl[!, :Step] .= step_names[tbl[!, :StepIndex]]
# 	tbl[!, :Unit] .= step_units[tbl[!, :StepIndex]]
# 	tbl[!, :Resource] .= stage.implementation[tbl[!, :Unit]]

# 	# Problem with adding an Equivalents column, because reference_mass function calls complete (Stack Overflow)
# 	# solution, complete should just stack the steps.data tables and add the stepindex column
# 	# other useful information should be added afterword - or a view / an implementation struct

# 	return tbl
# end

# reference_mass(stage::Stage) = subset(complete(stage).df, :Out, :Ref)[!, :Amount] |> skipmissing |> sum
reference_mass(stage::Stage) = [ProcessTables.reference_mass(stp.data) for stp in stage.steps] |> sum
reference_mole(stage::Stage) = subset(complete(stage).df, :In, :Ref)[!, :Mol] |> skipmissing |> sum

maximum_volumes(stage::Stage) = collect([stp.data.df[!, :Volume] |> skipmissing |> collect |> maximum for stp in stage.steps])
levels(stage::Stage) = [ProcessTables.levels(stp.data) for stp in stage.steps]


resources(stage::Stage) = collect(stp.resource for stp in stage.steps)

implement!(stage, implementations...) = push!(stage.implementation, implementations...)
implement(implementations...) = implement!(current_stage, implementations...)

units(stage::Stage) = collect([ismissing(res) ? missing : stage.implementation[res] for res in resources(stage)])	
unit_volume(unitname::String) = _lookup(unitname, equipment_catalogue, :Max_Volume)
unit_volumes(stage::Stage) = collect([ismissing(unitname) ? missing : unit_volume(unitname) for unitname in units(stage)])

io_factors(stage::Stage) = PT.io_factors(complete(stage), reference_mass(stage))


function max_scalefactor(stage::Stage) 
	unit_volumes(stage) ./ maximum_volumes(stage) |> skipmissing |> minimum
end

function scalefactor(stage::Stage{T}) where T <: AbstractScalingOption 
	max_scalefactor(stage)
end

scalefactor(stage::Stage{Scalefactor}) = stage.scaling.value
scalefactor(stage::Stage{FixedBatchsize}) = stage.scaling.value / reference_mass(stage)

function scalefactor(stage::Stage{T}, target_amount::Float64) where T <: AbstractScalingOption
	sf = scalefactor(stage)
	return sf, target_amount / (reference_mass(stage) * sf)
end

# function scalefactor(stage::Stage{FixedBatchsize}, target_amount::Float64)
# 	sf = scalefactor(stage)
# 	return sf, ceil 
# end


# scalefactor(stage::Stage{MaxBatchsize}) = max_scalefactor(stage)
# function scalefactor(stage::Stage{MaxBatchsize}, target_amount::Float64)
# 	sf = scalefactor(stage)
# 	return sf, ceil(reference_mass(stage) * sf / target_amount)
# end

function scalefactor(stage::Stage{OptimalBatchsize}, target_amount::Float64)
	max_sf = max_scalefactor(stage)
	ref_batchsize = reference_mass(stage)
	max_batchsize = max_sf * ref_batchsize
	batch_count = ceil(target_amount / max_batchsize)
	batchsize = target_amount / batch_count
	sf = batchsize / ref_batchsize
	return sf, batch_count
end


function scale(stage::Stage; kwargs...) #scalefactor::Float64=scalefactor(stage); target::Float64, batchsize::Float64
	scale_options = Dict(kwargs)
	@info stage.name

	if haskey(scale_options, :target)
		@info scale_options[:target]
		sf, batch_count = scalefactor(stage, scale_options[:target])
	else
		sf = scalefactor(stage)
		batch_count = 1.0
	end

	return scale_processtable(complete(stage), sf), batch_count
end


# Base.:*(b::Bool, sg::Stage) = b ? sg : missing		# overloding *-function so that: true * Stage = Stage and false * Stage = missing, is broadcastable
# Base.:*(b::Bool, matamount::Tuple{String, Float64}) = b ? matamount : missing

function _stageproducing(product_name::String, stages)
	for i in stages
		if i.product == product_name
			return i
		end
	end
	return []
end

function _preceeding_stages(matinput::NamedTuple, stages)
	r = Dict{Stage, Float64}()

	im_productnames = collect([sg.product for sg in stages])

	for (mat, qnt) in zip(matinput[1], matinput[2])
		if mat in im_productnames
			push!(r, _stageproducing(mat, stages) => qnt)
		end
	end

	return r
end

stages(d::Dict) = keys(d)

function produce(stage::Stage; production=Vector{Campaign}(), amount=1000.0, intermediates=Stage[])
	
	production_process, number_of_batches = scale(stage, target = amount)
	# something missing here?
	pushfirst!(production, Campaign(stage.product, production_process, number_of_batches))

	# Make a Dict of Stage => Inputfactor of the Stage
	# we can easily get the intermediates' product names by calling
	# but careful, once we are a level deeper in the recursion 
	# ...
	inputs = io_factors(stage)
	preceeding_stages = _preceeding_stages(inputs, intermediates)
	
	for next_stage in stages(preceeding_stages)
		stage_inputfactor = preceeding_stages[next_stage]
		next_intermediates = [i for i in intermediates if i != next_stage]
		produce(next_stage; production = production, amount = amount * stage_inputfactor, intermediates = next_intermediates)
	end

	return production
end


Base.show(io::IO, ::MIME"text/plain", sg::Stage) = print(io, "Stufe '$(sg.name)' produziert '$(sg.product)' in $(length(sg.steps)) Schritten")

view(stage::Stage) = readable(complete(stage))

end