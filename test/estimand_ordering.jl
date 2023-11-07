module TestEstimandOrdering

using TMLE
using Test

scm = SCM([
    :Y₁ => [:T₁, :T₂, :W₁, :W₂, :C],
    :Y₂ => [:T₁, :T₃, :W₃, :W₂, :C],
    :T₁ => [:W₁, :W₂],
    :T₂ => [:W₂],
    :T₃ => [:W₃, :W₂,],
])
causal_estimands = [
    ATE(
        outcome=:Y₁, 
        treatment_values=(T₁=(case=1, control=0),)
    ),
    ATE(
        outcome=:Y₁, 
        treatment_values=(T₁=(case=2, control=0),)
    ),
    CM(
        outcome=:Y₁, 
        treatment_values=(T₁=(case=2, control=0), T₂=(case=1, control=0))
    ),
    CM(
        outcome=:Y₁, 
        treatment_values=(T₂=(case=1, control=0),)
    ),
    IATE(
        outcome=:Y₁, 
        treatment_values=(T₁=(case=2, control=0), T₂=(case=1, control=0))
    ),
    ATE(
        outcome=:Y₂, 
        treatment_values=(T₁=(case=2, control=0),)
    ),
    ATE(
        outcome=:Y₂, 
        treatment_values=(T₃=(case=2, control=0),)
    ),
    ATE(
        outcome=:Y₂, 
        treatment_values=(T₁=(case=1, control=0), T₃=(case=2, control=0),)
    ),
]
statistical_estimands = [identify(x, scm) for x in causal_estimands]

@testset "Test evaluate_proxy_costs" begin
    # Estimand ID || Required models   
    # 1           || (T₁, Y₁|T₁)       
    # 2           || (T₁, Y₁|T₁)       
    # 3           || (T₁, T₂, Y₁|T₁,T₂)
    # 4           || (T₂, Y₁|T₂)       
    # 5           || (T₁, T₂, Y₁|T₁,T₂)
    # 6           || (T₁, Y₂|T₁)       
    # 7           || (T₃, Y₂|T₃)       
    # 8           || (T₁, T₃, Y₂|T₁,T₃)

    η_counts = TMLE.nuisance_counts(statistical_estimands)
    @test η_counts == Dict(
        TMLE.ConditionalDistribution(:Y₂, (:T₁, :W₁, :W₂))           => 1,
        TMLE.ConditionalDistribution(:Y₂, (:T₁, :T₃, :W₁, :W₂, :W₃)) => 1,
        TMLE.ConditionalDistribution(:Y₁, (:T₁, :T₂, :W₁, :W₂))      => 2,
        TMLE.ConditionalDistribution(:T₁, (:W₁, :W₂))                => 6,
        TMLE.ConditionalDistribution(:T₃, (:W₂, :W₃))                => 2,
        TMLE.ConditionalDistribution(:T₂, (:W₂,))                    => 3,
        TMLE.ConditionalDistribution(:Y₁, (:T₁, :W₁, :W₂))           => 2,
        TMLE.ConditionalDistribution(:Y₁, (:T₂, :W₂))                => 1,
        TMLE.ConditionalDistribution(:Y₂, (:T₃, :W₂, :W₃))           => 1
    )
    @test TMLE.evaluate_proxy_costs(statistical_estimands, η_counts) == (4, 9)
    optimal_ordering, optimal_maxmem, optimal_compcost = brute_force_ordering(statistical_estimands)
    @test optimal_maxmem == 3
    @test optimal_compcost == 9
end


end

true