#:Kampagnenplanung in names(Main) || 
include("Kampagnenplanung.jl")
import .Kampagnenplanung as KP
using .KP, DataFrames, CSV


# Initializations

kg = 1.0
g = 0.001kg


# Body


Dihydrazon = Stage("WP30 Stufe 1", "Dihydrazon"; scaling = OptimalBatchsize())
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Hydrazin_Lösung = Step("Hydrazin Lösung", "Reaktor")
charge("Ethanol", 405kg)
charge("Hydrazin Hydrat", 165kg)
operate("erwärmen auf 30°C")

Diimidat_Lösung = Step("Diimidat Lösung", "Vorlage")
charge("Imidoester", 334; reference = true)
charge("Ethanol", 700)
operate("erwärmen auf 30°C")

Reaktionsgemisch = Step("Reaktionsgemisch", "Reaktor")
resume(Hydrazin_Lösung)
transfer(Diimidat_Lösung, 1/2)
transfer(Diimidat_Lösung)
operate("für 3 Stunden reagieren lassen")
operate("eine IPK 11 Probe ziehen (kein Haltepunkt)")
operate("auf 0°C abkühlen")
operate("für 30 Minunten nachrühren")

Stage1 = Step("Isolierung und Trocknung", "Filtertrockner")
filtrate(Reaktionsgemisch, "Filterkuchen", "Mutterlauge", 1200) # Mutterlauge als Substanz-artiger Stoffstrom
charge("Ethanol", 400)
operate("aufrühren und eine Suspensionswäsche durchführen")
release("Waschlösung", 450)
operate("entfeuchten")
operate("trocknen bei 50°C im Vakuum")
release("Dihydrazon", 265; reference = true)
operate("eine IPK 12 Freigabeprobe ziehen")

implement("Reaktor" => "C403", "Vorlage" => "C404", "Filtertrockner" => "F403")



WP30 = Stage("WP30", "WP30"; scaling = OptimalBatchsize())
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WP30_Rgm = Step("Reaktionsgemisch", "Reaktor")
charge("Ethanol", 350kg)
charge("Dihydrazon", 115kg)
charge("Benzil", 50kg; reference = true)
operate("aufheizen bis 100°C")
operate("für 8 Stunden nachrühren")
operate("abkühlen")

EP = Step("Isolierung", "Filtertrockner")
filtrate(WP30_Rgm, "Feuchtprodukt", "Mutterlauge", 385kg)
cakewash("Ethanol", 120kg)
operate("trocknen im Vakuum < 50 mbar bei < 60°C")
release("WP30", 105kg; reference = true)

implement("Reaktor" => "C401", "Filtertrockner" => "F404")

production_campaign = produce(WP30; amount = 135kg, intermediates = [Dihydrazon])
# x = KP.PT.readable(production_campaign[2])