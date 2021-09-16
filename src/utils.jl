logit(X) = log.(X ./ (1 .- X))
expit(X) = 1 ./ (1 .+ exp.(-X))

"""
Hack into GLM to compute deviance on y a real
"""
function GLM.devresid(::Bernoulli, y::Vector{<:Real}, μ::Real)
    return -2*(y*log(μ) + (1-y)*log1p(-μ))
end

"""
Remove default check for y to be binary
"""
GLM.checky(y, d::Bernoulli) = nothing


###############################################################################
## Interactions Generation
###############################################################################

"""
    interaction_combinations(query::NamedTuple{names,})
Returns a generator over the different combinations of interactions that
can be built from a query.
"""
function interaction_combinations(query::NamedTuple{names,}) where names
    return (NamedTuple{names}(query) for query in Iterators.product(query...))
end


"""
    indicator_fns(query::NamedTuple{names,})

Implements the (-1)^{n-j} formula representing the cross-value of
indicator functions,  where:
    - n is the order of interaction considered
    - j is the number of treatment variables different from the "case" value
"""
function indicator_fns(query::NamedTuple{nms,}) where nms
    case = NamedTuple{nms}([v[1] for v in query])
    interactionorder = length(query)
    return Dict(q => (-1)^(interactionorder - sum(q[key] == case[key] for key in nms)) 
                for q in interaction_combinations(query))
end


###############################################################################
## Offset and covariate
###############################################################################

function compute_offset(Q̅mach::Machine{<:Probabilistic}, X)
    # The machine is an estimate of a probability distribution
    # In the binary case, the expectation is assumed to be the probability of the second class
    expectation = MLJ.predict(Q̅mach, X).prob_given_ref[2]
    return logit(expectation)
end


function compute_offset(Q̅mach::Machine{<:Deterministic}, X)
    return MLJ.predict(Q̅mach, X)
end


"""
For each data point, computes: (-1)^(interaction-oder - j)
Where j is the number of treatments different from the reference in the query.
"""
function compute_covariate(Gmach::Machine, W, T, query)
    # Build the Indicator function dictionary
    indicators = indicator_fns(query)
    
    # Compute the indicator value
    covariate = zeros(nrows(T))
    for (i, row) in enumerate(Tables.namedtupleiterator(T))
        if haskey(indicators, row)
            covariate[i] = indicators[row]
        end
    end

    # Compute density and truncate
    d = density(Gmach, W, T)
    # is this really necessary/suitable?
    d = min.(0.995, max.(0.005, d))
    return covariate ./ d
end


###############################################################################
## Fluctuation
###############################################################################

function compute_fluctuation(Fmach::Machine, 
                             Q̅mach::Machine, 
                             Gmach::Machine, 
                             Hmach::Machine,
                             W, 
                             T)
    Thot = transform(Hmach, T)
    X = merge(Thot, W)
    offset = compute_offset(Q̅mach, X)
    cov = compute_covariate(Gmach, W, T, Fmach.model.query)
    Xfluct = (covariate=cov, offset=offset)
    return  MLJ.predict_mean(Fmach, Xfluct)
end