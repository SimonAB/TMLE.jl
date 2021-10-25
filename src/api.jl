"""
    TMLEstimator(Q̅, G, F)

# Scope:

Implements the Targeted Minimum Loss-Based Estimator for the Interaction 
Average Treatment Effect (IATE) defined by Beentjes and Khamseh in
https://link.aps.org/doi/10.1103/PhysRevE.102.053314.
For instance, The IATE is defined for two treatment variables as: 

IATE = E[E[Y|T₁=1, T₂=1, W=w] - E[E[Y|T₁=1, T₂=0, W=w]
        - E[E[Y|T₁=0, T₂=1, W=w] + E[E[Y|T₁=0, T₂=0, W=w]

where:

- Y is the target variable (Binary)
- T = T₁, T₂ are the treatment variables (Binary)
- W are confounder variables

The TMLEstimator procedure relies on plugin estimation. Like the ATE, the IATE 
requires an estimator of t,w → E[Y|T=t, W=w], an estimator of  w → p(T|w) 
and an estimator of w → p(w). The empirical distribution will be used for w → p(w) all along. 
The estimator of t,w → E[Y|T=t, W=w] is then fluctuated to solve the efficient influence
curve equation. 

# Arguments:

- Q̅::MLJ.Supervised : The learner to be used
for E[Y|W, T]. Typically a `MLJ.Stack`.
- G::MLJ.Supervised : The learner to be used
for p(T|W). Typically a `MLJ.Stack`.
- fluctuation_family::Distribution : This will be used to build the fluctuation 
using a GeneralizedLinearModel. Typically `Normal` for a continuous target 
and `Bernoulli` for a Binary target.

# Examples:

TODO
"""
mutable struct TMLEstimator <: MLJ.DeterministicComposite 
    Q̅::MLJ.Supervised
    G::MLJ.Supervised
    F::Union{LinearRegressor, LinearBinaryClassifier}
    R::Report
    query::NamedTuple
    indicators::Dict
    threshold::Float64
end


function TMLEstimator(Q̅, G, F, query; threshold=0.005)
    indicators = indicator_fns(query)
    if F == "continuous"
        fluct = LinearRegressor(fit_intercept=false, offsetcol=:offset)
        return TMLEstimator(Q̅, G, fluct, Report(), query, indicators, threshold)
    elseif F == "binary"
        fluct = LinearBinaryClassifier(fit_intercept=false, offsetcol=:offset)
        return TMLEstimator(Q̅, G, fluct, Report(), query, indicators, threshold)
    else
        throw(ArgumentError("Unsuported fluctuation mode."))
    end
    
end


function Base.setproperty!(tmle::TMLEstimator, name::Symbol, x)
    name == :indicators && throw(ArgumentError("This field must not be changed manually."))
    name != :query && setfield!(tmle, name, x)

    indicators = indicator_fns(x)
    setfield!(tmle, :query, x)
    setfield!(tmle, :indicators, indicators)
end


"""

Let's default to no warnings for now.
"""
MLJBase.check(model::TMLEstimator, args... ; full=false) = true

pvalue(tmle::TMLEstimator, estimate, stderror) = 2*(1 - cdf(Normal(0, 1), abs(estimate/stderror)))

confint(tmle::TMLEstimator, estimate, stderror) = (estimate - 1.96stderror, estimate + 1.96stderror)

###############################################################################
## Fit
###############################################################################


"""
    MLJ.fit(tmle::TMLEstimator, 
                 verbosity::Int, 
                 T,
                 W, 
                 y::Union{CategoricalVector{Bool}, Vector{<:Real}}
"""
function MLJ.fit(tmle::TMLEstimator, 
                 verbosity::Int, 
                 T,
                 W, 
                 y::Union{CategoricalVector{Bool}, Vector{<:Real}})
    Ts = source(T)
    Ws = source(W)
    ys = source(y)

    # Converting all tables to NamedTuples
    T = node(t->NamedTuple{keys(tmle.query)}(Tables.columntable(t)), Ts)
    W = node(w->Tables.columntable(w), Ws)
    # intersect(keys(T), keys(W)) == [] || throw("T and W should have different column names")

    # Initial estimate of E[Y|T, W]:
    #   - The treatment variables are hot-encoded  
    #   - W and T are merged
    #   - The machine is implicitely fit
    Hmach = machine(OneHotEncoder(drop_last=true), T)
    Thot = transform(Hmach, T)

    X = node((t, w) -> merge(t, w), Thot, W)
    Q̅mach = machine(tmle.Q̅, X, ys)

    # Initial estimate of P(T|W)
    #   - T is converted to an Array
    #   - The machine is implicitely fit
    Gmach = machine(tmle.G, W, adapt(T))

    # Fluctuate E[Y|T, W] 
    # on the covariate and the offset 
    offset = compute_offset(Q̅mach, X)
    covariate = compute_covariate(tmle, Gmach, W, T; verbosity=verbosity)
    Xfluct = fluctuation_input(covariate, offset)

    Fmach = machine(tmle.F, Xfluct, ys)

    # Compute the final estimate 
    ct_fluct = counterfactual_fluctuations(tmle, 
                                     Fmach,
                                     Q̅mach,
                                     Gmach,
                                     Hmach,
                                     W,
                                     T;
                                     verbosity=verbosity)

    # Standard error from the influence curve
    observed_fluct = MLJ.predict_mean(Fmach, Xfluct)

    Rmach = machine(tmle.R, ct_fluct, observed_fluct, covariate, ys)
    out = MLJ.predict(Rmach, ct_fluct)

    mach = machine(Deterministic(), Ts, Ws, ys; predict=out)

    return!(mach, tmle, verbosity)
end


