module TestInteractionATE

include("interaction_transformer.jl")

using Test
using TMLE
using MLJBase
using Distributions
using Random
using StableRNGs
using Tables
using StatsBase
using MLJModels
using MLJLinearModels
using LogExpFunctions

cont_interacter = InteractionTransformer |> LinearRegressor
cat_interacter = InteractionTransformer |> LogisticClassifier


function binary_target_binary_treatment_pb(;n=100)
    rng = StableRNG(123)
    μy_fn(W, T₁, T₂) = logistic.(2W[:, 1] .+ 1W[:, 2] .- 2W[:, 3] .- T₁ .+ T₂ .+ 2*T₁ .* T₂)
    # Sampling W: Bernoulli
    W = rand(rng, Bernoulli(0.5), n, 3)

    # Sampling T₁, T₂ from W: Softmax
    θ = rand(rng, 3, 4)
    softmax = exp.(W*θ) ./ sum(exp.(W*θ), dims=2)
    T = [sample(rng, [1, 2, 3, 4], Weights(softmax[i, :])) for i in 1:n]
    T₁ = [t in (1,2) ? true : false for t in T]
    T₂ = [t in (1,3) ? true : false for t in T]

    # Sampling y from T₁, T₂, W: Logistic
    μy = μy_fn(W, T₁, T₂)
    y = [rand(rng, Bernoulli(μy[i])) for i in 1:n]

    # Respect the Tables.jl interface and convert types
    W = float(W)
    T₁ = categorical(T₁)
    T₂ = categorical(T₂)
    y = categorical(y)

    # Compute the theoretical IATE
    Wcomb = [1 1 1;
            1 1 0;
            1 0 0;
            1 0 1;
            0 1 0;
            0 0 0;
            0 0 1;
            0 1 1]
    IATE = 0
    for i in 1:8
        w = reshape(Wcomb[i, :], 1, 3)
        temp = μy_fn(w, [1], [1])[1]
        temp += μy_fn(w, [0], [0])[1]
        temp -= μy_fn(w, [1], [0])[1]
        temp -= μy_fn(w, [0], [1])[1]
        IATE += temp*0.5*0.5*0.5
    end
    return (T₁=T₁, T₂=T₂, W₁=W[:, 1], W₂=W[:, 2], W₃=W[:, 3], y=y), IATE
end


function binary_target_categorical_treatment_pb(;n=100)
    rng = StableRNG(123)
    function μy_fn(W, T, Hmach)
        Thot = MLJBase.transform(Hmach, T)
        logistic.(2W[:, 1] .+ 1W[:, 2] .- 2W[:, 3] 
                    .- Thot[1] .+ Thot[2] .+ 2Thot[3] .- 3Thot[4]
                    .+ 2*Thot[1].*Thot[2]
                    .+ 1*Thot[1].*Thot[3]
                    .- 4*Thot[1].*Thot[4]
                    .- 3*Thot[2].*Thot[3]
                    .+ 1.5*Thot[2].*Thot[4]
                    .- 2.5*Thot[3].*Thot[4]
                    )
    end
    # Sampling W:
    W = rand(rng, Bernoulli(0.5), n, 3)

    # Sampling T from W:
    # T₁, T₂ will have 3 categories each
    # This is embodied by a 9 dimensional full joint
    θ = rand(rng, 3, 9)
    softmax = exp.(W*θ) ./ sum(exp.(W*θ), dims=2)
    encoding = collect(Iterators.product(["CC", "GG", "CG"], ["TT", "AA", "AT"]))
    T = [sample(rng, encoding, Weights(softmax[i, :])) for i in 1:n]
    T = (T₁=categorical([t[1] for t in T]), T₂=categorical([t[2] for t in T]))

    Hmach = machine(OneHotEncoder(drop_last=true), T)
    fit!(Hmach, verbosity=0)

    # Sampling y from T, W:
    μy = μy_fn(W, T, Hmach)
    y = [rand(rng, Bernoulli(μy[i])) for i in 1:n]

    # Compute the theoretical IATE for the query
    # (CC, AT) against (CG, AA)
    Wcomb = [1 1 1;
            1 1 0;
            1 0 0;
            1 0 1;
            0 1 0;
            0 0 0;
            0 0 1;
            0 1 1]
            IATE = 0
    levels₁ = levels(T.T₁)
    levels₂ = levels(T.T₂)
    for i in 1:8
        w = reshape(Wcomb[i, :], 1, 3)
        temp = μy_fn(w, (T₁=categorical(["CC"], levels=levels₁), T₂=categorical(["AT"], levels=levels₂)), Hmach)[1]
        temp += μy_fn(w, (T₁=categorical(["CG"], levels=levels₁), T₂=categorical(["AA"], levels=levels₂)), Hmach)[1]
        temp -= μy_fn(w, (T₁=categorical(["CC"], levels=levels₁), T₂=categorical(["AA"], levels=levels₂)), Hmach)[1]
        temp -= μy_fn(w, (T₁=categorical(["CG"], levels=levels₁), T₂=categorical(["AT"], levels=levels₂)), Hmach)[1]
        IATE += temp*0.5*0.5*0.5
    end
    return (T₁=T.T₁, T₂=T.T₂, W₁=W[:, 1], W₂=W[:, 2], W₃=W[:, 3], y=categorical(y)), IATE
end


function continuous_target_binary_treatment_pb(;n=100)
    rng = StableRNG(123)
    μy_fn(W, T₁, T₂) = 2W[:, 1] .+ 1W[:, 2] .- 2W[:, 3] .- T₁ .+ T₂ .+ 2*T₁ .* T₂
    # Sampling W: Bernoulli
    W = rand(rng, Bernoulli(0.5), n, 3)

    # Sampling T₁, T₂ from W: Softmax
    θ = rand(rng, 3, 4)
    softmax = exp.(W*θ) ./ sum(exp.(W*θ), dims=2)
    T = [sample(rng, [1, 2, 3, 4], Weights(softmax[i, :])) for i in 1:n]
    T₁ = [t in (1,2) ? true : false for t in T]
    T₂ = [t in (1,3) ? true : false for t in T]

    # Sampling y from T₁, T₂, W: Logistic
    μy = μy_fn(W, T₁, T₂)
    y = μy + rand(rng, Normal(0, 0.1), n)

    # Respect the Tables.jl interface and convert types
    W = float(W)
    T₁ = categorical(T₁)
    T₂ = categorical(T₂)

    # Compute the theoretical ATE
    Wcomb = [1 1 1;
            1 1 0;
            1 0 0;
            1 0 1;
            0 1 0;
            0 0 0;
            0 0 1;
            0 1 1]
    IATE = 0
    for i in 1:8
        w = reshape(Wcomb[i, :], 1, 3)
        temp = μy_fn(w, [1], [1])[1]
        temp += μy_fn(w, [0], [0])[1]
        temp -= μy_fn(w, [1], [0])[1]
        temp -= μy_fn(w, [0], [1])[1]
        IATE += temp*0.5*0.5*0.5
    end

    return (T₁=T₁, T₂=T₂,  W₁=W[:, 1], W₂=W[:, 2], W₃=W[:, 3], y=y), IATE
end

@testset "Test Double Robustness IATE on binary_target_binary_treatment_pb" begin
    dataset, Ψ₀ = binary_target_binary_treatment_pb(n=1000)
    Ψ = IATE(
        target=:y,
        treatment=(T₁=(case=true, control=false), T₂=(case=true, control=false)),
        confounders = [:W₁, :W₂, :W₃]
    )
    # When Q is misspecified but G is well specified
    η_spec = NuisanceSpec(
        ConstantClassifier(),
        LogisticClassifier(lambda=0)
    )
    tmle_result, initial_result, cache = tmle(Ψ, η_spec, dataset, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ 0.287 atol=1e-3
    # The initial estimate is far away
    @test TMLE.estimate(initial_result) == 0

    # When Q is well specified  but G is misspecified
    η_spec = NuisanceSpec(
        LogisticClassifier(lambda=0),
        ConstantClassifier()
    )
    
    tmle_result, initial_result, cache = tmle!(cache, η_spec, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ 0.288 atol=1e-3
    # Since Q is well specified, it still gets the correct answer in this case
    @test TMLE.estimate(initial_result) ≈ -0.0003 atol=1e-4
end

@testset "Test Double Robustness IATE on continuous_target_binary_treatment_pb" begin
    dataset, Ψ₀ = continuous_target_binary_treatment_pb(n=1000)
    Ψ = IATE(
        target=:y,
        treatment=(T₁=(case=true, control=false), T₂=(case=true, control=false)),
        confounders = [:W₁, :W₂, :W₃]
    )
    # When Q is misspecified but G is well specified
    η_spec = NuisanceSpec(
        MLJModels.DeterministicConstantRegressor(),
        LogisticClassifier(lambda=0)
    )

    tmle_result, initial_result, cache = tmle(Ψ, η_spec, dataset, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ 1.947 atol=1e-3
    # The initial estimate is far away
    @test TMLE.estimate(initial_result) == 0 

    # When Q is well specified  but G is misspecified
    η_spec = NuisanceSpec(
        cont_interacter,
        ConstantClassifier()
    )

    tmle_result, initial_result, cache = tmle!(cache, η_spec, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ 1.999 atol=1e-3
    # Since Q is well specified, it still gets the correct answer in this case
    @test TMLE.estimate(initial_result) ≈ 1.999 atol=1e-3
end


@testset "Test Double Robustness IATE on binary_target_categorical_treatment_pb" begin
    dataset, Ψ₀ = binary_target_categorical_treatment_pb(n=1000)
    Ψ = IATE(
        target=:y,
        treatment=(T₁=(case="CC", control="CG"), T₂=(case="AT", control="AA")),
        confounders = [:W₁, :W₂, :W₃]
    )
    # When Q is misspecified but G is well specified
    η_spec = NuisanceSpec(
        ConstantClassifier(),
        LogisticClassifier(lambda=0)
    )

    tmle_result, initial_result, cache = tmle(Ψ, η_spec, dataset, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ -0.736 atol=1e-3
    # The initial estimate is far away
    @test TMLE.estimate(initial_result) == 0 

    # When Q is well specified but G is misspecified
    η_spec = NuisanceSpec(
        cat_interacter,
        ConstantClassifier()
    )

    tmle_result, initial_result, cache = tmle!(cache, η_spec, verbosity=0)
    Ψ̂ = TMLE.estimate(tmle_result)
    lb, ub = confint(OneSampleTTest(tmle_result))
    @test lb ≤ Ψ̂ ≤ ub
    @test Ψ̂ ≈ -0.779 atol=1e-3
    # Here the initial cannot get it it seems
    @test TMLE.estimate(initial_result) ≈ -0.017 atol=1e-3
end


end;


true