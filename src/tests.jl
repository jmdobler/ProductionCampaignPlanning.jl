#module Tests

include("ProductionCampaignPlanning.jl")
import .ProductionCampaignPlanning as KP
using .KP, DataFrames, CSV

kg = 1.0
g = 0.001kg

## Synthesis plan
#             A  ────┐
#                    ├─────>  S
#   R  ────>  B  ────┘ 

A = Stage("Acid", "Acid304"; scaling = OptimalBatchsize())
A1 = Step("Saponification", "enamelled reactor")
charge("Solvent", 0.145kg)
charge("Ester", 25.7g; reference = true)
charge("Caustic soda", 45.0g)
operate("react")
release("Acid304", 16.2g; reference = true)

R = Stage("R pure", "Pure R"; scaling = OptimalBatchsize())
R1 = Step("Purification", "reactor")
charge("Reagent", 900kg; reference = true)
operate("purify")
release("Pure R", 800kg; reference = true)

B = Stage("Base", "Base304 soln"; scaling = OptimalBatchsize())
B1 = Step("Solution of R in water", "stirred tank")
charge("Water", 300kg)
charge("Pure R", 30kg; reference = true)
operate("dissolve at 50°C")
B2 = Step("Suspension", "stainless steel reactor")
resume(B1)
charge("Caustic soda", 60kg)
operate("cool to 5°C")
B3 = Step("Isolation", "filter")
filtrate(B2, "Wet cake", "Mother liquor", 280kg)
cakewash("Water", 80kg)
cakewash("Water", 70kg)
charge("Ethanol", 115kg)
operate("dissolve")
release("Base304 soln", 166kg; reference = true)

S = Stage("Salt", "Salt304"; scaling = OptimalBatchsize())
S1 = Step("Heterogeneous reaction mixture", "enamelled reactor")
charge("Base304 soln", 10g)
charge("Acid304", 3.14g; reference = true)
operate("stirr at ambient temperature")
S2 = Step("Isolation", "filter dryer")
filtrate(S1, "Wet salt", 8.8g, "Mother liquor")
cakewash("Ethanol", 3g)
operate("dry salt at 140°C")
release("Salt304", 8.2g; reference = true)


implement!(A, "enamelled reactor" => "C403")
implement!(R, "reactor" => "C403")
implement!(B, "stirred tank" => "C401", "stainless steel reactor" => "C402", "filter" => "F404")
implement!(S, "enamelled reactor" => "C403", "filter dryer" => "F403")


production = produce(S; amount = 450kg, intermediates = [A, B, R])



# p = production[4].process.df

# p[!, :Step] .= KP.stepnames(S)[p[!, :StepIndex]]
# p[!, :Resource] .= KP.resources(S)[p[!, :StepIndex]]
# p[!, :Unit] .= S.implementation[p[!, :Resource]]
# p


## Make a Figure in a matrix layout
# in rows: different Campaigns from the `produce`-function
# in cols: different Units (Reactors, Filters, etc.) used
# each plot shows a bar plot with the volumes over operation-number for each Step defined in the ProcessTable 
# the plots have fixed y-achses showing the volume per each row (Campaign)

#       *Figure: TITLE Production of Product*
#   ┌───┬───────────────────────────────────────────────────────────────────
#   │   │    Step 1 / Unit x         Step 2 / Unit y 
#   │ S │  6┌───────────────┐      6┌───────────────┐      6┌───────┐
#   │ T │  5│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│      5│               │      5│▒▒▒▒▒▒▒│
#   │ A │  4│▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│      4│  ▄ ▄   █ █    │      4│▒▒▒▒▒▒▒│
#   │ G │  3│      ▄ ▄      │      3│  █ █   █ █    │      3│▒▒▒▒▒▒▒│
#   │ E │  2│  █ █ █ █      │      2│  █ █ █ █ █ ▄  │      2│▄ █ ▄ ▄│
#   │   │  1│█ █ █ █ █   █ █│      1│█ █ █ █ █ █ █ █│      1│█ █ █ █│
#   │ 1 │   └───────────────┘       └───────────────┘       └───────┘
#   │   │    1 2 3 4 5 6 7 8         1 2 3 4 5 6 7 8         1 2 3 4
#   └───┴─────────────────────────────────────────────────────────────────
#   ┌───┬──────────────────────────────────────────────────────────────────
#   │ S │    Step 1 / Unit z         
#   │ T │   4┌───────────────┐     
#   │ A │   3│      ▄ ▄      │   
#   │ G │   2│      █ █      │      
#   │ E │   1│█ █ ▄ █ █ ▄ ▄ █│    
#   │   │    └───────────────┘     
#   │ 2 │    1 2 3 4 5 6 7 8        
#   └───┴─────────────────────────────────────────────────────────────────
#
##
using CairoMakie
CairoMakie.activate!(type = "svg")

fig = Figure(backgroundcolor = RGBf(0.98, 0.98, 0.98), size = (100, 800));

length(production)


function format_ticklabel(label::String)
    label = replace(label, "-" => "-~")
    label_segments = split(label, r"[ ~]")
    linebreak = 0
    newlabel = String[]
    for (i, segment) in enumerate(label_segments)
        if segment[end] == '-'
            sep = ""
        else
            sep = " "
        end
        push!(newlabel, segment)
        linebreak += length(segment)
        if linebreak >= 8 
            push!(newlabel, "\n")
            linebreak = 0
        else 
            push!(newlabel, sep)
        end
    end
    return cumprod(newlabel[1:end-1])[end]
end

# TODO: make a function that either takes a Vector{Campaign}, a Campaign or a Stage (if there is an implementation)
# this function return a Makie.Figure

function levelplot(pt::KP.ProcessTable, plotfigure = Figure()) #---> ProcessTables.jl
    # if there is a `:Step` column, this process table is a multi-step process from a Campaign.process
    # if there no such column, than this process table is a single-step process from a Stage.step
    multi_step_process = "Step" in names(pt.df)
    # if multi_step_process
    #     processes = subset(pt.df, :Step => s -> s .)


    
    gridrow = plotfigure[end + 1, 1] = GridLayout(; halign = :left)

end


for icmp in 1:length(production)
    campaign = production[icmp]
    process_steps = unique(campaign.process.df[:, :Step]) 

    gridrow = fig[icmp, 1] = GridLayout(; halign = :left)
    steps_count = length(process_steps)

    for istp in 1:steps_count
        step_name = process_steps[istp]
        sb = subset(campaign.process.df, :Step => s -> s .== step_name)
        lvls = KP.ProcessTables.levels(KP.ProcessTable(sb))
        oprs = KP.ProcessTables.operations(KP.ProcessTable(sb))
        
        step_unit = unique(sb[:, :Unit]) |> first

        ax = Axis(gridrow[1, istp], title = "$(step_name) in $(step_unit)", xticks = (1:1:length(lvls), format_ticklabel.(oprs)))
        
        colsize!(gridrow, istp, Fixed(120 * length(lvls)))
        barplot!(lvls)
        ylims!(0, KP.unit_volume(step_unit))

        # TODO: add y-axislabel Volume 

    end
end

resize_to_layout!(fig)
display(fig)

# barplot(fig[1,1], v1);
# barplot(fig[1,2], v1);
# display(fig)


# a = collect(zip(KP.units(S), KP.unit_volumes(S)))

# b = KP.levels(S)

z = KP.readable(production[3].process)
lv = KP.levels(production[3])
KP.unit_volumes(B)

# KP.units(B)

# p = [c.process.df for c in prod]
# px = vcat(p...)

# p = prod[4].process
# v1 = px[px[:, :StepIndex] .== 1, :Volume] 
# v1 = replace(v1, missing => 0)

# x1 = 1:size(v1,1)
# v1 = cumsum(v1)


#end