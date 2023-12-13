#####################################################################
###                       CMRelevantFactors                       ###
#####################################################################

"""
Defines relevant factors that need to be estimated in order to estimate any
Counterfactual Mean composite estimand (see `StatisticalCMCompositeEstimand`).
"""
struct CMRelevantFactors <: Estimand
    outcome_mean::ConditionalDistribution
    propensity_score::Tuple{Vararg{ConditionalDistribution}}
end

CMRelevantFactors(outcome_mean, propensity_score::ConditionalDistribution) = 
    CMRelevantFactors(outcome_mean, (propensity_score,))

CMRelevantFactors(;outcome_mean, propensity_score) = 
    CMRelevantFactors(outcome_mean, propensity_score)

string_repr(estimand::CMRelevantFactors) = 
    string("Composite Factor: \n",
           "----------------\n- ",
        string_repr(estimand.outcome_mean),"\n- ", 
        join((string_repr(f) for f in estimand.propensity_score), "\n- "))

variables(estimand::CMRelevantFactors) = 
    Tuple(union(variables(estimand.outcome_mean), (variables(est) for est in estimand.propensity_score)...))

#####################################################################
###                         Functionals                           ###
#####################################################################

const ESTIMANDS_DOCS = Dict(
    :CM => (formula="``CM(Y, T=t) = E[Y|do(T=t)]``",),
    :ATE => (formula="``ATE(Y, T, case, control) = E[Y|do(T=case)] - E[Y|do(T=control)``",),
    :IATE => (formula="``IATE = E[Y|do(T₁=1, T₂=1)] - E[Y|do(T₁=1, T₂=0)] - E[Y|do(T₁=0, T₂=1)] + E[Y|do(T₁=0, T₂=0)]``",)
)

for (estimand, (formula,)) ∈ ESTIMANDS_DOCS
    causal_estimand = Symbol(:Causal, estimand)
    statistical_estimand = Symbol(:Statistical, estimand)
    ex = quote
        # Causal Estimand
        struct $(causal_estimand) <: Estimand
            outcome::Symbol
            treatment_values::NamedTuple

            function $(causal_estimand)(outcome, treatment_values)
                outcome = Symbol(outcome)
                treatment_values = get_treatment_specs(treatment_values)
                return new(outcome, treatment_values)
            end
        end
        # Statistical Estimand
        struct $(statistical_estimand) <: Estimand
            outcome::Symbol
            treatment_values::NamedTuple
            treatment_confounders::NamedTuple
            outcome_extra_covariates::Tuple{Vararg{Symbol}}

            function $(statistical_estimand)(outcome, treatment_values, treatment_confounders, outcome_extra_covariates)
                outcome = Symbol(outcome)
                treatment_values = get_treatment_specs(treatment_values)
                treatment_variables = Tuple(keys(treatment_values))
                treatment_confounders = NamedTuple{treatment_variables}([confounders_values(treatment_confounders, T) for T ∈ treatment_variables])
                outcome_extra_covariates = unique_sorted_tuple(outcome_extra_covariates)
                return new(outcome, treatment_values, treatment_confounders, outcome_extra_covariates)
            end
        end

        # Constructors
        $(causal_estimand)(;outcome, treatment_values) =  $(causal_estimand)(outcome, treatment_values)

        $(statistical_estimand)(;outcome, treatment_values, treatment_confounders, outcome_extra_covariates) =
            $(statistical_estimand)(outcome, treatment_values, treatment_confounders, outcome_extra_covariates)
        
        # Short Name Constructors
        $(estimand)(outcome, treatment_values) = $(causal_estimand)(outcome, treatment_values)

        $(estimand)(outcome, treatment_values, treatment_confounders, outcome_extra_covariates) = 
            $(statistical_estimand)(outcome, treatment_values, treatment_confounders, outcome_extra_covariates)

        $(estimand)(outcome, treatment_values, treatment_confounders::Nothing, outcome_extra_covariates) = 
            $(causal_estimand)(outcome, treatment_values)

        $(estimand)(;outcome, treatment_values, treatment_confounders=nothing, outcome_extra_covariates=()) =
            $(estimand)(outcome, treatment_values, treatment_confounders, outcome_extra_covariates)

    end
    eval(ex)
end

CausalCMCompositeEstimands = Union{(eval(Symbol(:Causal, x)) for x in keys(ESTIMANDS_DOCS))...}

StatisticalCMCompositeEstimand = Union{(eval(Symbol(:Statistical, x)) for x in keys(ESTIMANDS_DOCS))...}

const AVAILABLE_ESTIMANDS = [x[1] for x ∈ ESTIMANDS_DOCS]

indicator_fns(Ψ::StatisticalCM) = Dict(values(Ψ.treatment_values) => 1.)

function indicator_fns(Ψ::StatisticalATE)
    case = []
    control = []
    for treatment in Ψ.treatment_values
        push!(case, treatment.case)
        push!(control, treatment.control)
    end
    return Dict(Tuple(case) => 1., Tuple(control) => -1.)
end

ncases(value, Ψ::StatisticalIATE) = sum(value[i] == Ψ.treatment_values[i].case for i in eachindex(value))

function indicator_fns(Ψ::StatisticalIATE)
    N = length(treatments(Ψ))
    key_vals = Pair[]
    for cf in Iterators.product((values(Ψ.treatment_values[T]) for T in treatments(Ψ))...)
        push!(key_vals, cf => float((-1)^(N - ncases(cf, Ψ))))
    end
    return Dict(key_vals...)
end

outcome_mean(Ψ::StatisticalCMCompositeEstimand) = ExpectedValue(Ψ.outcome, Tuple(union(Ψ.outcome_extra_covariates, keys(Ψ.treatment_confounders), (Ψ.treatment_confounders)...)))

outcome_mean_key(Ψ::StatisticalCMCompositeEstimand) = variables(outcome_mean(Ψ))

propensity_score(Ψ::StatisticalCMCompositeEstimand) = Tuple(ConditionalDistribution(T, Ψ.treatment_confounders[T]) for T in treatments(Ψ))

propensity_score_key(Ψ::StatisticalCMCompositeEstimand) = Tuple(variables(x) for x ∈ propensity_score(Ψ))

function get_relevant_factors(Ψ::StatisticalCMCompositeEstimand)
    outcome_model = outcome_mean(Ψ)
    treatment_factors = propensity_score(Ψ)
    return CMRelevantFactors(outcome_model, treatment_factors)
end

n_uniques_nuisance_functions(Ψ::StatisticalCMCompositeEstimand) = length(propensity_score(Ψ)) + 1

nuisance_functions_iterator(Ψ::StatisticalCMCompositeEstimand) =
    (propensity_score(Ψ)..., outcome_mean(Ψ))

function Base.show(io::IO, ::MIME"text/plain", Ψ::T) where T <: StatisticalCMCompositeEstimand 
    param_string = string(
        Base.typename(T).wrapper,
        "\n-----",
        "\nOutcome: ", Ψ.outcome,
        "\nTreatment: ", Ψ.treatment_values
    )
    println(io, param_string)
end

function treatment_specs_to_dict(treatment_values::NamedTuple{T, <:Tuple{Vararg{NamedTuple}}}) where T
    Dict(key => Dict(pairs(vals)) for (key, vals) in pairs(treatment_values))
end

treatment_specs_to_dict(treatment_values::NamedTuple) = Dict(pairs(treatment_values))

treatment_values(d::AbstractDict) = (;d...)
treatment_values(d) = d

confounders_values(key_value_iterable::Union{NamedTuple, Dict}, T) = unique_sorted_tuple(key_value_iterable[T])

confounders_values(iterable, T) = unique_sorted_tuple(iterable)

get_treatment_specs(treatment_specs::NamedTuple{names, }) where names = 
    NamedTuple{Tuple(sort(collect(names)))}(treatment_specs)

function get_treatment_specs(treatment_specs::NamedTuple{names, <:Tuple{Vararg{NamedTuple}}}) where names
    case_control = ((case=v[:case], control=v[:control]) for v in values(treatment_specs))
    treatment_specs = (;zip(keys(treatment_specs), case_control)...)
    sorted_names = Tuple(sort(collect(names)))
    return NamedTuple{sorted_names}(treatment_specs)
end
    
get_treatment_specs(treatment_specs::AbstractDict) = 
    get_treatment_specs((;(key => treatment_values(val) for (key, val) in treatment_specs)...))

constructorname(T; prefix="TMLE.Causal") = replace(string(T), prefix => "")

treatment_confounders_to_dict(treatment_confounders::NamedTuple) = 
    Dict(key => collect(vals) for (key, vals) in pairs(treatment_confounders))

"""
    to_dict(Ψ::T) where T <: CausalCMCompositeEstimands

Converts Ψ to a dictionary that can be serialized.
"""
function to_dict(Ψ::T) where T <: CausalCMCompositeEstimands
    return Dict(
        :type => constructorname(T; prefix="TMLE.Causal"),
        :outcome => Ψ.outcome,
        :treatment_values => treatment_specs_to_dict(Ψ.treatment_values)
        )
end

"""
    to_dict(Ψ::T) where T <: StatisticalCMCompositeEstimand

Converts Ψ to a dictionary that can be serialized.
"""
function to_dict(Ψ::T) where T <: StatisticalCMCompositeEstimand
    return Dict(
        :type => constructorname(T; prefix="TMLE.Statistical"),
        :outcome => Ψ.outcome,
        :treatment_values => treatment_specs_to_dict(Ψ.treatment_values),
        :treatment_confounders => treatment_confounders_to_dict(Ψ.treatment_confounders),
        :outcome_extra_covariates => collect(Ψ.outcome_extra_covariates)
        )
end

identify(method, Ψ::StatisticalCMCompositeEstimand, scm) = Ψ

function identify(method::BackdoorAdjustment, causal_estimand::T, scm::SCM) where T<:CausalCMCompositeEstimands
    # Treatment confounders
    treatment_names = keys(causal_estimand.treatment_values)
    treatment_codes = [code_for(scm.graph, treatment) for treatment ∈ treatment_names]
    confounders_codes = scm.graph.graph.badjlist[treatment_codes]
    treatment_confounders = NamedTuple{treatment_names}(
        [[scm.graph.vertex_labels[w] for w in confounders_codes[i]] 
        for i in eachindex(confounders_codes)]
    )

    return statistical_type_from_causal_type(T)(;
        outcome=causal_estimand.outcome,
        treatment_values = causal_estimand.treatment_values,
        treatment_confounders = treatment_confounders,
        outcome_extra_covariates = method.outcome_extra_covariates
    )
end

unique_non_missing(dataset, colname) = unique(skipmissing(Tables.getcolumn(dataset, colname)))

unique_treatment_values(dataset, colnames) =(;(colname => unique_non_missing(dataset, colname) for colname in colnames)...)

"""
    generateATEs(dataset, treatments, outcome; confounders=nothing, outcome_extra_covariates=())

Find all unique values for each treatment variable in the dataset and generate all possible ATEs from these values.
"""
function generateATEs(dataset, treatments, outcome; confounders=nothing, outcome_extra_covariates=())
    treatments_unique_values = unique_treatment_values(dataset, treatments)
    return generateATEs(treatments_unique_values, outcome; confounders=confounders, outcome_extra_covariates=outcome_extra_covariates)
end

"""
    generateATEs(treatments_unique_values, outcome; confounders=nothing, outcome_extra_covariates=())

Generate all possible ATEs from the `treatments_unique_values`.
"""
function generateATEs(treatments_unique_values, outcome; confounders=nothing, outcome_extra_covariates=())
    treatments = Tuple(Symbol.(keys(treatments_unique_values)))
    treatments_control_case = [collect(Combinatorics.combinations(treatments_unique_values[T], 2)) for T in treatments]
    
    ATEs = []
    for combo ∈ Iterators.product(treatments_control_case...)
        treatments_control_case = [NamedTuple{(:control, :case)}(treatment_control_case) for treatment_control_case ∈ combo]
        push!(
            ATEs, 
            ATE(
                outcome=outcome,
                treatment_values=NamedTuple{treatments}(treatments_control_case),
                treatment_confounders = confounders,
                outcome_extra_covariates=outcome_extra_covariates
            )
        )
    end
    return ATEs
end