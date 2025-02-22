module TestEstimands

using Test
using TMLE

@testset "Test StatisticalCMCompositeEstimand" begin
    dataset = (
        W  = [1, 2, 3, 4, 5, 6, 7, 8],
        T₁ = ["A", "B", "A", "B", "A", "B", "A", "B"],
        T₂ = [0, 0, 1, 1, 0, 0, 1, 1],
        T₃ = ["C", "C", "C", "C", "D", "D", "D", "D"],
        Y =  [1, 1, 1, 1, 1, 1, 1, 1]
    )
    # Counterfactual Mean
    Ψ = CM(
        outcome=:Y, 
        treatment_values=(T₁="A", T₂=1),
        treatment_confounders=(T₁=[:W], T₂=[:W])
    )
    indicator_fns = TMLE.indicator_fns(Ψ)
    @test indicator_fns == Dict(("A", 1) => 1.)
    indic_values = TMLE.indicator_values(indicator_fns, TMLE.selectcols(dataset, TMLE.treatments(Ψ)))
    @test indic_values == [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
    # ATE
    Ψ = ATE(
        outcome=:Y, 
        treatment_values=(
            T₁=(case="A", control="B"), 
            T₂=(control=0, case=1)
        ),
        treatment_confounders=(T₁=[:W], T₂=[:W])
    )
    indicator_fns = TMLE.indicator_fns(Ψ)
    @test indicator_fns == Dict(
        ("A", 1) => 1.0,
        ("B", 0) => -1.0
    )
    indic_values = TMLE.indicator_values(indicator_fns, TMLE.selectcols(dataset, TMLE.treatments(Ψ)))
    @test indic_values == [0.0, -1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0]
    # 2-points IATE
    Ψ = IATE(
        outcome=:Y, 
        treatment_values=(
            T₁=(case="A", control="B"), 
            T₂=(case=1, control=0)
        ),
        treatment_confounders=(T₁=[:W], T₂=[:W])
    )
    indicator_fns = TMLE.indicator_fns(Ψ)
    @test indicator_fns == Dict(
        ("A", 1) => 1.0,
        ("A", 0) => -1.0,
        ("B", 1) => -1.0,
        ("B", 0) => 1.0
    )
    indic_values = TMLE.indicator_values(indicator_fns, TMLE.selectcols(dataset, TMLE.treatments(Ψ)))
    @test indic_values == [-1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0]
    # 3-points IATE
    Ψ = IATE(
        outcome=:Y, 
        treatment_values=(
            T₁=(case="A", control="B"), 
            T₂=(case=1, control=0), 
            T₃=(control="D", case="C")
        ),
        treatment_confounders=(T₁=[:W], T₂=[:W], T₃=[:W])
    )
    indicator_fns = TMLE.indicator_fns(Ψ)
    @test indicator_fns == Dict(
        ("A", 1, "D") => -1.0,
        ("A", 1, "C") => 1.0,
        ("B", 0, "D") => -1.0,
        ("B", 0, "C") => 1.0,
        ("B", 1, "C") => -1.0,
        ("A", 0, "D") => 1.0,
        ("B", 1, "D") => 1.0,
        ("A", 0, "C") => -1.0
    )
    indic_values = TMLE.indicator_values(indicator_fns, TMLE.selectcols(dataset, TMLE.treatments(Ψ)))
    @test indic_values == [-1.0, 1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0]
end

@testset "Test standardization of StatisticalCMCompositeEstimand" begin
    # ATE
    Ψ₁ = ATE(
        outcome="Y",
        treatment_values = (T₁=(case=1, control=0), T₂=(control=1, case=0)),
        treatment_confounders = (
            T₂ = [:W₂, "W₁"],
            T₁ = ["W₀"]
            ),
        outcome_extra_covariates = ["Z", :A]
    )
    Ψ₂ = ATE(
        outcome=:Y,
        treatment_values = (T₁=(case=1, control=0), T₂=(case=0, control=1)),
        treatment_confounders = (
            T₁ = [:W₀],
            T₂ = [:W₂, :W₁]
            ),
        outcome_extra_covariates = [:A, :Z]
    )
    @test Ψ₁ == Ψ₂
    @test Ψ₁.outcome == :Y
    @test Ψ₁.treatment_values == (T₁=(case=1, control=0), T₂=(case=0, control=1))
    @test Ψ₁.treatment_confounders == (T₁ = (:W₀,), T₂ = (:W₁, :W₂))
    @test Ψ₁.outcome_extra_covariates == (:A, :Z)
    
    # CM
    Ψ₁ = CM(
        outcome=:Y,
        treatment_values=(T₁=1, T₂=0),
        treatment_confounders = (T₂ = ["W₁", "W₂"], T₁ = [:W₀]),
    )
    Ψ₂ = CM(
        outcome=:Y,
        treatment_values=(T₂=0, T₁=1),
        treatment_confounders = (T₂ = [:W₂, "W₁"],T₁ = ["W₀"]),
    )
    @test Ψ₁ == Ψ₂
    @test Ψ₁.outcome == :Y
    @test Ψ₁.treatment_values == (T₁=1, T₂=0)
    @test Ψ₁.treatment_confounders == (T₁ = (:W₀,), T₂ = (:W₁, :W₂))
    @test Ψ₁.outcome_extra_covariates == ()
end

@testset "Test structs are concrete types" begin
    for type in Base.uniontypes(TMLE.StatisticalCMCompositeEstimand)
        @test isconcretetype(type)
    end
end

@testset "Test dictionary conversion" begin
    # Causal CM
    Ψ = CM(
        outcome=:y,
        treatment_values = (T₁=1, T₂="AC")
    )
    d = TMLE.to_dict(Ψ)
    @test d == Dict(
        :type             => "CM",
        :treatment_values => Dict(:T₁=>1, :T₂=>"AC"),
        :outcome          => :y
    )
    Ψreconstructed = TMLE.from_dict!(d)
    @test Ψreconstructed == Ψ
    # Causal ATE
    Ψ = ATE(
        outcome=:y, 
        treatment_values=(
            T₁=(case="A", control="B"), 
            T₂=(case=1, control=0), 
            T₃=(case="C", control="D")
        ),
    )
    d = TMLE.to_dict(Ψ)
    @test d == Dict(
        :type => "ATE",
        :treatment_values => Dict(
            :T₁ => Dict(:case => "A", :control => "B"),
            :T₂ => Dict(:case => 1, :control => 0), 
            :T₃ => Dict(:control => "D", :case => "C")
        ),
        :outcome => :y
    )
    Ψreconstructed = TMLE.from_dict!(d)
    @test Ψ == Ψ
    
    # Statistical CM
    Ψ = CM(
        outcome=:y,
        treatment_values = (T₁=1, T₂="AC"),
        treatment_confounders = (T₁=[:W₁₁, :W₁₂], T₂=[:W₁₂, :W₂₂])
    )
    d = TMLE.to_dict(Ψ)
    @test d == Dict(
        :outcome_extra_covariates => [],
        :type                     => "CM",
        :treatment_values         => Dict(:T₁=>1, :T₂=>"AC"),
        :outcome                  => :y,
        :treatment_confounders    => Dict(:T₁=>[:W₁₁, :W₁₂], :T₂=>[:W₁₂, :W₂₂])
    )
    Ψreconstructed = TMLE.from_dict!(d)
    @test Ψreconstructed == Ψ

    # Statistical IATE
    Ψ = IATE(
        outcome=:y,
        treatment_values = (T₁=1, T₂="AC"),
        treatment_confounders = (T₁=[:W₁₁, :W₁₂], T₂=[:W₁₂, :W₂₂]),
        outcome_extra_covariates=[:C]
    )
    d = TMLE.to_dict(Ψ)
    @test d == Dict(
        :outcome_extra_covariates => [:C],
        :type                     => "IATE",
        :treatment_values         => Dict(:T₁=>1, :T₂=>"AC"),
        :outcome                  => :y,
        :treatment_confounders    => Dict(:T₁=>[:W₁₁, :W₁₂], :T₂=>[:W₁₂, :W₂₂])
    )
    Ψreconstructed = TMLE.from_dict!(d)
    @test Ψreconstructed == Ψ
end

@testset "Test control_case_settings" begin
    treatments_unique_values = (T₁=(1, 0, 2),)
    @test TMLE.get_treatments_contrasts(treatments_unique_values) == [[[1, 0], [1, 2], [0, 2]]]
    treatments_unique_values = (T₁=(1, 0, 2), T₂=["AC", "CC"])
    @test TMLE.get_treatments_contrasts(treatments_unique_values) == [[[1, 0], [1, 2], [0, 2]], [["AC", "CC"]]]
end
@testset "Test generateATEs" begin
    dataset = (
        T₁=[0, 1, 2, missing], 
        T₂ = ["AC", "CC", missing, "AA"],
        W₁ = [1, 2, 3, 4],
        W₂ = [1, 2, 3, 4],
        C  = [1, 2, 3, 4],
        Y₁ = [1, 2, 3, 4],
        Y₂ = [1, 2, 3, 4]
    )
    # No confounders, 1 treatment, no extra covariate: 3 causal ATEs
    composedATE = generateATEs(dataset, [:T₁], :Y₁)
    @test composedATE.args == (
        TMLE.CausalATE(:Y₁, (T₁ = (case = 1, control = 0),)),
        TMLE.CausalATE(:Y₁, (T₁ = (case = 2, control = 0),)),
        TMLE.CausalATE(:Y₁, (T₁ = (case = 2, control = 1),))
    )
    # 2 treatments
    composedATE = generateATEs(dataset, [:T₁, :T₂], :Y₁;
        confounders=[:W₁, :W₂],
        outcome_extra_covariates=[:C]
    )
    ## 9 expected different treatment settings
    @test length(composedATE.args) == 9
    @test length(unique([Ψ.treatment_values for Ψ in composedATE.args])) == 9
    ## Covariates and confounders
    @test all(Ψ.outcome_extra_covariates == (:C,) for Ψ in composedATE.args)
    @test all(Ψ.treatment_confounders == (T₁ = (:W₁, :W₂), T₂ = (:W₁, :W₂)) for Ψ in composedATE.args)

    # positivity constraint
    composedATE = generateATEs(dataset, [:T₁, :T₂], :Y₁;
        confounders=[:W₁, :W₂],
        outcome_extra_covariates=[:C],
        positivity_constraint=0.1
    )
    @test length(composedATE.args) == 1

end

@testset "Test generateIATEs" begin
    dataset = (
        T₁ = [0, 1, 2, missing], 
        T₂ = ["AC", "CC", missing, "AA"],
        W₁ = [1, 2, 3, 4],
        W₂ = [1, 2, 3, 4],
        C  = [1, 2, 3, 4],
        Y₁ = [1, 2, 3, 4],
        Y₂ = [1, 2, 3, 4]
    )
    # From dataset
    composedIATE = generateIATEs(dataset, [:T₁, :T₂], :Y₁, 
        confounders=[:W₁], 
        outcome_extra_covariates=[:C]
    )
    @test composedIATE isa ComposedEstimand
    ## 3 x 3 = 9 expected components
    @test length(composedIATE.args) == 9
    for arg ∈ composedIATE.args
        @test arg isa TMLE.StatisticalIATE
        @test arg.treatment_confounders == (T₁=(:W₁,), T₂=(:W₁,))
        @test arg.outcome_extra_covariates == (:C,)
    end
    # From unique values
    composedIATE = generateIATEs((T₁ = (0, 1), T₂=(0, 1, 2)), :Y₁)
    @test composedIATE isa ComposedEstimand
    ## 1 x 3 expected components
    @test length(composedIATE.args) == 1*3
    for arg ∈ composedIATE.args
        @test arg isa TMLE.CausalIATE
    end

    # positivity constraint
    composedIATE = generateIATEs(dataset, [:T₁, :T₂], :Y₁, 
        confounders=[:W₁], 
        outcome_extra_covariates=[:C],
        positivity_constraint=0.1
    )
    @test length(composedIATE.args) == 0

end


end

true