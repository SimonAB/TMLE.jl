module TMLE

using Tables
using TableOperations
using CategoricalArrays
using MLJBase
using HypothesisTests
using Base: Iterators
using MLJGLMInterface
using MLJModels
using Missings
using Statistics
using Distributions
using Zygote
using LogExpFunctions
using PrecompileTools
using PrettyTables
using Random
import AbstractDifferentiation as AD
using Graphs
using MetaGraphsNext
using Combinatorics
using SplitApplyCombine

# #############################################################################
# EXPORTS
# #############################################################################

export SCM, StaticSCM, add_equations!, add_equation!, parents, vertices
export CM, ATE, IATE
export AVAILABLE_ESTIMANDS
export generateATEs, generateIATEs
export TMLEE, OSE, NAIVE
export ComposedEstimand
export var, estimate, OneSampleTTest, OneSampleZTest, OneSampleHotellingT2Test,pvalue, confint, emptyIC
export compose
export TreatmentTransformer, with_encoder, encoder
export BackdoorAdjustment, identify
export last_fluctuation_epsilon
export Configuration
export brute_force_ordering, groups_ordering

# #############################################################################
# INCLUDES
# #############################################################################

include("utils.jl")
include("scm.jl")
include("adjustment.jl")
include("estimands.jl")
include("estimators.jl")
include("estimates.jl")
include("treatment_transformer.jl")
include("estimand_ordering.jl")

include("counterfactual_mean_based/estimands.jl")
include("counterfactual_mean_based/estimates.jl")
include("counterfactual_mean_based/fluctuation.jl")
include("counterfactual_mean_based/estimators.jl")
include("counterfactual_mean_based/clever_covariate.jl")
include("counterfactual_mean_based/gradient.jl")

include("configuration.jl")


end
