"""
This structure is used as a cache for both:
    - η_spec: The specification of the learning algorithms used to estimate the nuisance parameters
    - η: nuisance parameters
    - data: data changes

If the input data does not change, then the nuisance parameters do not have to be estimated again.
"""
mutable struct TMLECache
    data
    η::NuisanceParameters
    Ψ::Parameter
    η_spec::NuisanceSpec
    function TMLECache(dataset)
        data = Dict{Symbol, Any}(:source => dataset)
        η = NuisanceParameters(nothing, nothing, nothing, nothing)
        new(data, η)
    end
end

function check_treatment_values(cache::TMLECache, Ψ::Parameter)
    for T in treatments(Ψ)
        Tlevels = levels(Tables.getcolumn(cache.data[:source], T))
        Tsetting = getproperty(Ψ.treatment, T)
        for (key, val) in zip(keys(Tsetting), Tsetting) 
            any(val .=== Tlevels) || 
                throw(ArgumentError(string(
                    "The ", key, " value '", val, "' for treatment ", T, 
                    " in Ψ does not match (in the sense of ===) ",
                    "any level of the corresponding variable in the dataset: ", Tlevels)))
        end
    end
end


function update!(cache::TMLECache, Ψ::Parameter)
    check_treatment_values(cache, Ψ)
    any_variable_changed = false
    if !isdefined(cache, :Ψ)
        any_variable_changed = true
    else
        if keys(cache.Ψ.treatment) != keys(Ψ.treatment)
            cache.η.G = nothing
            cache.η.Q = nothing
            cache.η.H = nothing
            any_variable_changed = true
        end
        if cache.Ψ.confounders != Ψ.confounders
            cache.η.G = nothing
            cache.η.Q = nothing
            any_variable_changed = true
        end
        if cache.Ψ.covariates != Ψ.covariates
            cache.η.Q = nothing
            any_variable_changed = true
        end
        if cache.Ψ.target != Ψ.target
            cache.η.Q = nothing
            any_variable_changed = true
        end
        cache.η.F = nothing
    end
    # Update no missing dataset
    if any_variable_changed
        cache.data[:no_missing] = nomissing(cache.data[:source], allcolumns(Ψ))
    end
    cache.Ψ = Ψ
    return cache
end

function update!(cache::TMLECache, η_spec::NuisanceSpec)
    if isdefined(cache, :η_spec)
        if cache.η_spec.G != η_spec.G
            cache.η.G = nothing
        end
        if cache.η_spec.Q != η_spec.Q
            cache.η.Q = nothing
        end
        cache.η.F = nothing
    end
    cache.η_spec = η_spec
    return cache
end

function update!(cache::TMLECache, Ψ::Parameter, η_spec::NuisanceSpec)
    update!(cache, Ψ)
    update!(cache, η_spec)
end

"""
    tmle(Ψ::Parameter, η_spec::NuisanceSpec, dataset; verbosity=1, threshold=1e-8)

Main entrypoint to run the TMLE procedure.

# Arguments

- Ψ: The parameter of interest
- η_spec: The specification for learning `Q_0` and `G_0`
- dataset: A tabular dataset respecting the Table.jl interface
- verbosity: The logging level
- threshold: To avoid small values of Ĝ to cause the "clever covariate" to explode
- mach_cache: Whether underlying MLJ.machines will cache data or not
"""
function tmle(Ψ::Parameter, η_spec::NuisanceSpec, dataset; verbosity=1, threshold=1e-8)
    cache = TMLECache(dataset)
    update!(cache, Ψ, η_spec)
    return tmle!(cache; verbosity=verbosity, threshold=threshold)
end

function tmle!(cache::TMLECache; verbosity=1, threshold=1e-8)
    # Initial fit of the nuisance parameters
    verbosity >= 1 && @info "Fitting the nuisance parameters..."
    TMLE.fit_nuisance!(cache, verbosity=verbosity)
    
    # TMLE step
    verbosity >= 1 && @info "Targeting the nuisance parameters..."
    tmle_step!(cache, verbosity=verbosity, threshold=threshold)
    
    # Estimation results after TMLE
    IC, Ψ̂, Ψ̂ᵢ = TMLE.gradient_and_estimates(cache)
    result = PointTMLE(Ψ̂, IC, Ψ̂ᵢ)

    verbosity >= 1 && @info "Done."
    return result, cache
end

"""
    tmle!(cache::TMLECache, Ψ::Parameter; verbosity=1, threshold=1e-8)

Runs the TMLE procedure for the new parameter Ψ while potentially reusing cached nuisance parameters.
"""
function tmle!(cache::TMLECache, Ψ::Parameter; verbosity=1, threshold=1e-8)
    update!(cache, Ψ)
    tmle!(cache, verbosity=verbosity, threshold=threshold)
end

"""
    tmle!(cache::TMLECache, η_spec::NuisanceSpec; verbosity=1, threshold=1e-8)

Runs the TMLE procedure for the new nuisance parameters specification η_spec while potentially reusing cached nuisance parameters.
"""
function tmle!(cache::TMLECache, η_spec::NuisanceSpec; verbosity=1, threshold=1e-8, mach_cache=false)
    update!(cache, η_spec)
    tmle!(cache, verbosity=verbosity, threshold=threshold)
end

"""
    tmle!(cache::TMLECache, Ψ::Parameter, η_spec::NuisanceSpec; verbosity=1, threshold=1e-8)

Runs the TMLE procedure for the new parameter Ψ and the new nuisance parameters specification η_spec 
while potentially reusing cached nuisance parameters.
"""
function tmle!(cache::TMLECache, Ψ::Parameter, η_spec::NuisanceSpec; verbosity=1, threshold=1e-8)
    update!(cache, Ψ, η_spec)
    tmle!(cache, verbosity=verbosity, threshold=threshold)
end

"""
    tmle!(cache::TMLECache, η_spec::NuisanceSpec, Ψ::Parameter; verbosity=1, threshold=1e-8)

Runs the TMLE procedure for the new parameter Ψ and the new nuisance parameters specification η_spec 
while potentially reusing cached nuisance parameters.
"""
function tmle!(cache::TMLECache, η_spec::NuisanceSpec, Ψ::Parameter; verbosity=1, threshold=1e-8)
    update!(cache, Ψ, η_spec)
    tmle!(cache, verbosity=verbosity, threshold=threshold)
end


"""
    fit_nuisance!(cache::TMLECache; verbosity=1, mach_cache=false)
    
Fits the nuisance parameters η on the dataset using the specifications from η_spec
and the variables defined by Ψ.
"""
function fit_nuisance!(cache::TMLECache; verbosity=1)
    Ψ, η_spec, η = cache.Ψ, cache.η_spec, cache.η
    # Fitting P(T|W)
    # Only rows with missing values in either W or Tₜ are removed
    if η.G === nothing
        log_fit(verbosity, "P(T|W)")
        nomissing_WT = nomissing(cache.data[:source], treatment_and_confounders(Ψ))
        W = confounders(nomissing_WT, Ψ)
        jointT = joint_treatment(treatments(nomissing_WT, Ψ))
        mach = machine(η_spec.G, W, jointT, cache=η_spec.cache)
        MLJBase.fit!(mach, verbosity=verbosity-1)
        η.G = mach
        cache.data[:jointT_levels] = levels(jointT)
    else
        log_no_fit(verbosity, "P(T|W)")
    end

    # Fitting E[Y|X]
    if η.Q === nothing
        # Data
        X = Qinputs(cache.data[:no_missing], Ψ)
        y = target(cache.data[:no_missing], Ψ)

        # Fitting the Encoder
        if η.H === nothing
            log_fit(verbosity, "Encoder")
            mach = machine(η_spec.H, X, cache=η_spec.cache)
            MLJBase.fit!(mach, verbosity=verbosity-1)
            η.H = mach
        else
            log_no_fit(verbosity, "Encoder")
        end
        log_fit(verbosity, "E[Y|X]")
        Xfloat = MLJBase.transform(η.H, X)
        cache.data[:Xfloat] = Xfloat
        mach = machine(η_spec.Q, Xfloat, y, cache=η_spec.cache)
        MLJBase.fit!(mach, verbosity=verbosity-1)
        η.Q = mach
    else
        log_no_fit(verbosity, "Encoder")
        log_no_fit(verbosity, "E[Y|X]")
    end
end


function tmle_step!(cache::TMLECache; verbosity=1, threshold=1e-8)
    # Fit fluctuation
    ŷ = MLJBase.predict(cache.η.Q, cache.data[:Xfloat])
    offset = TMLE.compute_offset(ŷ)
    W = TMLE.confounders(cache.data[:no_missing], cache.Ψ)
    jointT = TMLE.joint_treatment(TMLE.treatments(cache.data[:no_missing], cache.Ψ))
    covariate = TMLE.compute_covariate(jointT, W, cache.Ψ, cache.η.G; threshold=threshold)
    X = TMLE.fluctuation_input(covariate, offset)
    y = TMLE.target(cache.data[:no_missing], cache.Ψ)
    mach = machine(cache.η_spec.F, X, y, cache=cache.η_spec.cache)
    MLJBase.fit!(mach, verbosity=verbosity-1)
    # Update cache
    cache.η.F = mach
    # This is useful for gradient_Y_X
    cache.data[:covariate] = X.covariate
    cache.data[:μy] = TMLE.expected_value(MLJBase.predict(mach, X))
end

function counterfactual_aggregates(cache::TMLECache; threshold=1e-8)
    dataset = cache.data[:no_missing]
    WC = TMLE.confounders_and_covariates(dataset, cache.Ψ)
    Ttemplate = TMLE.treatments(dataset, cache.Ψ)
    n = nrows(Ttemplate)
    counterfactual_aggregateᵢ = zeros(n)
    counterfactual_aggregate = zeros(n)
    # Loop over Treatment settings
    for (vals, sign) in TMLE.indicator_fns(cache.Ψ, x -> x)
        # Counterfactual dataset for a given treatment setting
        Tc = TMLE.counterfactualTreatment(vals, Ttemplate)
        Xc = Qinputs(merge(WC, Tc), cache.Ψ)
        # Counterfactual predictions with the initial Q
        ŷᵢ = MLJBase.predict(cache.η.Q,  MLJBase.transform(cache.η.H, Xc))
        counterfactual_aggregateᵢ .+= sign .* expected_value(ŷᵢ)
        # Counterfactual predictions with F
        offset = compute_offset(ŷᵢ)
        jointT = categorical(repeat([joint_name(vals)], n), levels=cache.data[:jointT_levels])
        covariate = compute_covariate(jointT, confounders(WC, cache.Ψ), cache.Ψ, cache.η.G; threshold=threshold)
        Xfluct = fluctuation_input(covariate, offset)
        ŷ = predict(cache.η.F, Xfluct)
        counterfactual_aggregate .+= sign .* expected_value(ŷ)
    end
    return counterfactual_aggregate, counterfactual_aggregateᵢ
end

"""
    gradient_W(counterfactual_aggregate, estimate)

∇_W = counterfactual_aggregate - Ψ
"""
gradient_W(counterfactual_aggregate, estimate) =
    counterfactual_aggregate .- estimate


"""
    gradient_Y_X(cache)

∇_YX(w, t, c) = covariate(w, t)  ̇ (y - E[Y|w, t, c])

This part of the gradient is evaluated on the original dataset. All quantities have been precomputed and cached.
"""
function gradient_Y_X(cache::TMLECache)
    covariate = cache.data[:covariate]
    y = target(cache.data[:no_missing], cache.Ψ)
    return covariate .* (float(y) .- cache.data[:μy])
end


function gradient_and_estimates(cache::TMLECache; threshold=1e-8)
    counterfactual_aggregate, counterfactual_aggregateᵢ = TMLE.counterfactual_aggregates(cache; threshold=threshold)
    Ψ̂, Ψ̂ᵢ = mean(counterfactual_aggregate), mean(counterfactual_aggregateᵢ)
    IC = gradient_Y_X(cache) .+ gradient_W(counterfactual_aggregate, Ψ̂)
    return IC, Ψ̂, Ψ̂ᵢ
end

