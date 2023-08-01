using Test

@time begin
    @test include("non_regression_test.jl")
    @test include("cache.jl")
    @test include("utils.jl")
    @test include("double_robustness_ate.jl")
    @test include("double_robustness_iate.jl")
    @test include("3points_interactions.jl")
    @test include("warm_restart.jl")
    @test include("estimands.jl")
    @test include("missing_management.jl")
    @test include("composition.jl")
    @test include("treatment_transformer.jl")
    @test include("fit_nuisance.jl")
    @test include("configuration.jl")
end