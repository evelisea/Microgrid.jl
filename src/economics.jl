# Economic modeling of a microgrid project

# TODO 2022: use the ComponentCosts struct as an output of annual_costs functions, rather than Vectors
"Cost factors of a Microgrid component, expressed as Net Present Values over the Microgrid project lifetime"
struct ComponentCosts
    "Total cost (initial + replacement + O&M + fuel + salvage)"
    total
    "Initial investment cost"
    investment
    "Replacement cost"
    replacement
    "Operation & Maintenance (O&M) cost"
    om
    "Fuel cost"
    fuel
    "Salvage cost (negative)"
    salvage
end

# TODO 2022: split the giant MicrogridCosts struct into a hierarchical struct of structs
"Cost components of a Microgrid project"
struct MicrogridCosts
    # general
    "Levelized cost of electricity (currency unit)"
    lcoe
    "Cost of electricity (currency unit)"
    coe # annualized
    "Net present cost (currency unit)"
    npc
    "Present investment cost (currency unit)"
    total_investment_cost
    "Present replacement cost (currency unit)"
    total_replacement_cost
    "Present operation and maintenance cost (currency unit)"
    total_om_cost
    "Present salvage cost (currency unit)"
    total_salvage_cost

    # components
    "Generator's total present cost (currency unit)"
    DG_total_cost
    "Generator's present investment cost (currency unit)"
    DG_investment_cost
    "Generator's present replacement cost (currency unit)"
    DG_replacement_cost
    "Generator's present operation and maintenance cost (currency unit)"
    DG_om_cost
    "Generator's present salvage cost (currency unit)"
    DG_salvage_cost
    "Generator's present fuel cost (currency unit)"
    DG_fuel_cost

    "Battery's total present cost (currency unit)"
    BT_total_cost
    "Battery's present investment cost (currency unit)"
    BT_investment_cost
    "Battery's present replacement cost (currency unit)"
    BT_replacement_cost
    "Battery's present operation and maintenance cost (currency unit)"
    BT_om_cost
    "Battery's present salvage cost (currency unit)"
    BT_salvage_cost

    "Photovoltaic's total present cost (currency unit)"
    PV_total_cost
    "Photovoltaic's present investment cost (currency unit)"
    PV_investment_cost
    "Photovoltaic's present replacement cost (currency unit)"
    PV_replacement_cost
    "Photovoltaic's present operation and maintenance cost (currency unit)"
    PV_om_cost
    "Photovoltaic's present salvage cost (currency unit)"
    PV_salvage_cost

    "Wind turbine's total present cost (currency unit)"
    WT_total_cost
    "Wind turbine's present investment cost (currency unit)"
    WT_investment_cost
    "Wind turbine's present replacement cost (currency unit)"
    WT_replacement_cost
    "Wind turbine's present operation and maintenance cost (currency unit)"
    WT_om_cost
    "Wind turbine's present salvage cost (currency unit)"
    WT_salvage_cost
end


function annual_costs(mg_project::Project, quantity, investment_price, replacement_price, salvage_price, om_price, fuel_consumption, fuel_price, lifetime)
    # discount factor for each year of the project
    discount_factors = [ 1/((1 + mg_project.discount_rate)^i) for i=1:mg_project.lifetime ]
    sum_discounts = sum(discount_factors)

    # number of replacements
    replacements_number = ceil(Integer, mg_project.lifetime/lifetime) - 1
    # years that the replacements happen
    replacement_years = [i*lifetime for i=1:replacements_number]
    # discount factors for the replacements years
    replacement_factors = [1/(1 + mg_project.discount_rate)^i for i in replacement_years]

    # component remaining life at the project end
    remaining_life = lifetime*(1+replacements_number) - mg_project.lifetime
    # proportional unitary salvage cost given remaining life
    salvage_price_effective = salvage_price * remaining_life / lifetime

    # present investment cost
    investment_cost = investment_price * quantity
    # present operation and maintenance cost
    om_cost = om_price * quantity * sum_discounts
    # present replacement cost
    if replacements_number == 0
        replacement_cost = 0.0
    else
        replacement_cost = replacement_price * quantity * sum(replacement_factors)
    end
    # Salvage cost (<0)
    salvage_cost = -salvage_price_effective * quantity * discount_factors[mg_project.lifetime]

    if fuel_consumption > 0.0
        fuel_cost = fuel_price * fuel_consumption * sum_discounts
    else
        fuel_cost = 0.0
    end

    total_cost = investment_cost + replacement_cost + om_cost + fuel_cost + salvage_cost

    return ComponentCosts(total_cost, investment_cost, replacement_cost, om_cost, fuel_cost, salvage_cost)
end

"""costs for NonDispatchableSource (PV, wind...) components"""
function annual_costs(nd::NonDispatchableSource, mg_project::Project)
    c = annual_costs(
        mg_project,
        nd.power_rated,
        nd.investment_price,
        nd.investment_price * nd.replacement_price_ratio,
        nd.investment_price * nd.salvage_price_ratio,
        nd.om_price,
        0.0, 0.0,
        nd.lifetime)
    return [c.total, c.investment, c.om, c.replacement, -c.salvage]
end

function annual_costs(pvi::PVInverter, mg_project::Project)
    c_ac = annual_costs(
        mg_project,
        pvi.power_rated,
        pvi.investment_price_ac,
        pvi.investment_price_ac * pvi.replacement_price_ratio,
        pvi.investment_price_ac * pvi.salvage_price_ratio,
        pvi.om_price_ac,
        0.0, 0.0,
        pvi.lifetime_ac)
    c_dc = annual_costs(
        mg_project,
        pvi.power_rated*pvi.ILR, # DC rated power
        pvi.investment_price_dc,
        pvi.investment_price_dc * pvi.replacement_price_ratio,
        pvi.investment_price_dc * pvi.salvage_price_ratio,
        pvi.om_price_dc,
        0.0, 0.0,
        pvi.lifetime_dc)
    return [c_ac.total + c_dc.total,
            c_ac.investment + c_dc.investment,
            c_ac.om + c_dc.om,
            c_ac.replacement+c_dc.replacement,
            -(c_ac.salvage+c_dc.salvage)]
end

function annual_costs(dg::DispatchableGenerator, mg_project::Project, oper_stats::OperationStats)

    # discount factor for each year of the project
    discount_factors = [ 1/((1 + mg_project.discount_rate)^i) for i=1:mg_project.lifetime ]

    # total diesel generator operation hours over the project lifetime
    total_gen_hours = mg_project.lifetime * oper_stats.gen_hours

    # number of replacements
    replacements_number = ceil(Integer, total_gen_hours/dg.lifetime_hours) - 1
    # years that the replacements happen
    replacement_years = [i*(dg.lifetime_hours/oper_stats.gen_hours) for i=1:replacements_number]     # TODO verify
    # discount factors for the replacements years
    replacement_factors = [1/(1 + mg_project.discount_rate)^i for i in replacement_years]

    # present investment cost
    investment_cost = dg.investment_price * dg.power_rated
    # present operation and maintenance cost
    om_cost = sum(dg.om_price_hours * dg.power_rated * oper_stats.gen_hours * discount_factors) # depends on the nb of the DG working Hours
    # present replacement cost
    if replacements_number == 0
        replacement_cost = 0.0
    else
        replacement_cost = sum(dg.replacement_price_ratio * investment_cost * replacement_factors)
    end

    # component remaining life at the project end
    remaining_life = dg.lifetime_hours - (total_gen_hours - dg.lifetime_hours * replacements_number)
    # present salvage cost
    if remaining_life == 0
        salvage_cost = 0.0
    else
        nominal_salvage_cost = dg.salvage_price_ratio * investment_cost * remaining_life / dg.lifetime_hours
        salvage_cost = nominal_salvage_cost * discount_factors[mg_project.lifetime]
    end

    fuel_cost = sum(dg.fuel_price * oper_stats.gen_fuel * discount_factors)

    total_cost = investment_cost + replacement_cost + om_cost - salvage_cost + fuel_cost

    return [total_cost, investment_cost, om_cost, replacement_cost, salvage_cost, fuel_cost]
end

function annual_costs(bt::Battery, mg_project::Project, oper_stats::OperationStats)
    if oper_stats.storage_cycles > 0.0
        lifetime = min(
            bt.lifetime_cycles/oper_stats.storage_cycles, # cycling lifetime
            bt.lifetime_calendar # calendar lifetime
        )
    else
        lifetime = bt.lifetime_calendar
    end

    c = annual_costs(
        mg_project,
        bt.energy_rated,
        bt.investment_price,
        bt.investment_price * bt.replacement_price_ratio,
        bt.investment_price * bt.salvage_price_ratio,
        bt.om_price,
        0.0, 0.0,
        lifetime)
    return [c.total, c.investment, c.om, c.replacement, -c.salvage]
end

"""
    economics(mg::Microgrid, oper_stats::OperationStats)

Return the economics results for the microgrid `mg` and
the aggregated operation statistics `oper_stats`.

See also: [`aggregation`](@ref)
"""
function economics(mg::Microgrid, oper_stats::OperationStats)

    # discount factor for each year of the project
    discount_factors = [ 1/((1 + mg.project.discount_rate)^i) for i=1:mg.project.lifetime ]

    # Photovoltaic costs initialization
    PV_total_cost = 0.
    PV_investment_cost = 0.
    PV_om_cost = 0.
    PV_replacement_cost= 0.
    PV_salvage_cost = 0.
    # Wind power costs initialization
    WT_total_cost = 0.
    WT_investment_cost = 0.
    WT_om_cost = 0.
    WT_replacement_cost= 0.
    WT_salvage_cost = 0.
    # Diesel generator costs initialization
    #= DG_total_cost = 0.
    DG_investment_cost = 0.
    DG_om_cost = 0.
    DG_replacement_cost= 0.
    DG_salvage_cost = 0.
    DG_fuel_cost = 0. =#

    # NonDispatchables costs
    for i=1:length(mg.nondispatchables)
        if (typeof(mg.nondispatchables[i]) <: Photovoltaic) || (typeof(mg.nondispatchables[i]) <: PVInverter)
            PV_total_cost, PV_investment_cost, PV_om_cost, PV_replacement_cost, PV_salvage_cost = annual_costs(mg.nondispatchables[i], mg.project)
        elseif typeof(mg.nondispatchables[i]) == WindPower
            WT_total_cost, WT_investment_cost, WT_om_cost, WT_replacement_cost, WT_salvage_cost = annual_costs(mg.nondispatchables[i], mg.project)
        end
    end

    # DieselGenerator costs
    DG_total_cost, DG_investment_cost, DG_om_cost, DG_replacement_cost, DG_salvage_cost, DG_fuel_cost = annual_costs(mg.generator, mg.project, oper_stats)

    # Battery costs
    BT_total_cost, BT_investment_cost, BT_om_cost, BT_replacement_cost, BT_salvage_cost = annual_costs(mg.storage, mg.project, oper_stats)

    # SUMMARY
    # total present investment cost
    total_investment_cost = DG_investment_cost + BT_investment_cost + PV_investment_cost + WT_investment_cost
    # total present replacement cost
    total_replacement_cost = DG_replacement_cost + BT_replacement_cost + PV_replacement_cost + WT_replacement_cost
    # total present operation and maintenance cost
    total_om_cost = DG_om_cost + BT_om_cost + PV_om_cost + WT_om_cost
    # total present salvage cost
    total_salvage_cost = DG_salvage_cost + BT_salvage_cost + PV_salvage_cost + WT_salvage_cost
    # net present cost
    npc = DG_total_cost + BT_total_cost + PV_total_cost + WT_total_cost

    # recovery factor
    recovery_factor = (mg.project.discount_rate * (1 + mg.project.discount_rate)^mg.project.lifetime)/((1 + mg.project.discount_rate)^mg.project.lifetime - 1)
    # total annualized cost
    annualized_cost = npc * recovery_factor
    # cost of energy
    coe = annualized_cost / oper_stats.served_energy

    # energy served over the project lifetime
    energy_served_lifetime = oper_stats.served_energy * sum([1.0; discount_factors[1:length(discount_factors)-1]])
    # levelized cost of energy
    lcoe = npc / energy_served_lifetime

    costs = MicrogridCosts(lcoe, coe, npc,
            total_investment_cost, total_replacement_cost, total_om_cost, total_salvage_cost,
            DG_total_cost, DG_investment_cost, DG_replacement_cost, DG_om_cost, DG_salvage_cost, DG_fuel_cost,
            BT_total_cost, BT_investment_cost, BT_replacement_cost, BT_om_cost, BT_salvage_cost,
            PV_total_cost, PV_investment_cost, PV_replacement_cost, PV_om_cost, PV_salvage_cost,
            WT_total_cost, WT_investment_cost, WT_replacement_cost, WT_om_cost, WT_salvage_cost)

    return costs
end