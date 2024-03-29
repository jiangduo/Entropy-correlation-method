using ComplexityMeasures
using Test
using Random

@testset "Standard ranges binning" begin

    x = StateSpaceSet(rand(Random.MersenneTwister(1234), 100_000, 2))
    push!(x, SVector(0, 0)) # ensure both 0 and 1 have values in, exactly.
    push!(x, SVector(1, 1))

    # All these binnings give exactly the same ranges because of the 0-1 values
    # The value 1 is always included, due to the call of `nextfloat` when making
    # ranges for the `FixedRectangularBinning`
    n = 10
    ε = nextfloat(0.1) # when dividing 0-nextfloat(1) into 10, you get this width

    # All following binnings are equivalent
    # (`nextfloat` is necessary in Fixed, due to the promise given in the regular)
    binnings = [
        RectangularBinning(n),
        RectangularBinning(n, true),
        RectangularBinning(ε),
        RectangularBinning([n, n]),
        RectangularBinning([ε, ε]),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n+1), 2),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n+1), 2, true),
        FixedRectangularBinning(
            (range(0, nextfloat(1.0); step = ε), range(0, nextfloat(1.0); step = ε))
        ),
    ]

    for bin in binnings
        @testset "bin isa $(nameof(typeof(bin)))" begin
            o = ValueBinning(bin)
            out = outcome_space(o, x)
            @test length(out) == n^2
            p = probabilities(o, x)
            # all bins are covered due to random data
            @test length(p) == 100
            # ensure uniform coverage since input is uniformly random
            @test all(e -> 0.009 ≤ e ≤ 0.011, p)

            p2, outs = probabilities_and_outcomes(o, x)
            @test p2 == p
            @test outs isa Vector{SVector{2, Float64}}
            @test length(outs) == length(p)
            @test all(x -> x < 1, maximum(outs))
            o2 = outcomes(o, x)
            @test o2 == outs

            ospace = outcome_space(o, x)
            @test ospace isa Vector{SVector{2, Float64}}
            @test size(ospace) == (n*n, )
            @test SVector(0.0, 0.0) ∈ ospace
            @test issorted(ospace)

            # ensure 1 is included, and must also be in the last bin
            rbe = RectangularBinEncoding(bin, x)
            @test encode(rbe, SVector(1.0, 1.0)) == n^2
        end
    end

    @testset "vector" begin
        x = rand(Random.MersenneTwister(1234), 100_000)
        push!(x, 0, 1)
        n = 10 # boxes cover 0 - 1 in steps of slightly more than 0.1
        ε = nextfloat(0.1) # this guarantees that we get the same as the `n` above!
        for bin in (RectangularBinning(n), RectangularBinning(ε))
            p = probabilities(ValueBinning(bin), x)
            @test length(p) == 10
            @test all(e -> 0.09 ≤ e ≤ 0.11, p)
        end
    end

    @testset "convenience" begin
        @test ValueBinning(n) == ValueBinning(RectangularBinning(n))
        @test ValueBinning(ε) == ValueBinning(RectangularBinning(ε))
    end
end

@testset "Encodings, edge cases" begin
    # Encoding has been practically tested fully in the codes above.
    # here we just ensure the API works as expected and edge cases also
    # work as expected.
    # Concrete examples where a rogue extra bin has appeared.
    x1 = [0.5213236385155418, 0.03516318860292644, 0.5437726723245310, 0.52598710966469610, 0.34199879802511246, 0.6017129426606275, 0.6972844365031351, 0.89163995617220900, 0.39009862510518045, 0.06296038912844315, 0.9897176284081909, 0.7935001082966890, 0.890198448900077700, 0.11762640519877565, 0.7849413168095061, 0.13768932585886573, 0.50869900547793430, 0.18042178201388548, 0.28507312391861270, 0.96480406570924970]
    N = 10

    b1 = RectangularBinning(N)
    rb1 = RectangularBinEncoding(RectangularBinning(N, false), x1)
    rb2 = RectangularBinEncoding(RectangularBinning(N, true), x1)

    # low accuracy uses twice the next float, so no rounding error
    @test encode(rb1, maximum(x1)) == 10
    @test encode(rb2, maximum(x1)) == 10

    x2 = [0.4125754262679051, 0.52844411982339560, 0.4535277505543355, 0.25502420827802674, 0.77862522996085940, 0.6081939026664078, 0.2628674795466387, 0.18846258495465185, 0.93320375283233840, 0.40093871561247874, 0.8032730760974603, 0.3531608285217499, 0.018436525139752136, 0.55541857934068420, 0.9907521337888632, 0.15382361136212420, 0.01774321666660561, 0.67569337507728300, 0.06130971689608822, 0.31417161558476836]
    rb1 = RectangularBinEncoding(RectangularBinning(N, false), x2)
    rb2 = RectangularBinEncoding(RectangularBinning(N, true), x2)
    # Same as above
    @test encode(rb1, maximum(x2)) == 10
    @test encode(rb2, maximum(x2)) == 10

    # and a final analytic test with decode
    bin = FixedRectangularBinning(range(0, 1.0; length = 11), 2, true)
    rbc = RectangularBinEncoding(bin)
    @test encode(rbc, SVector(0.0, 0.0)) == 1
    @test encode(rbc, SVector(1.0, 1.0)) == -1
    @test decode(rbc, 1) == SVector(0.0, 0.0)
    @test decode(rbc, 100) == SVector(0.9, 0.9)
end

@testset "All points covered" begin
    x = StateSpaceSet(rand(100, 2))
    binnings = [
        RectangularBinning(5, true),
        RectangularBinning(0.2, true),
        RectangularBinning([2, 4], true),
        RectangularBinning([0.5, 0.25], true),
    ]

    for bin in binnings
        rbe = RectangularBinEncoding(bin, x)
        visited_bins = map(pᵢ -> encode(rbe, pᵢ), x)
        @test -1 ∉ visited_bins
    end
end

@testset "Codification of vector inputs (time series)" begin 
    rng = MersenneTwister(1234)

    # Scalar time series
    # ------------------
    x = rand(rng, 100) # some number on [0, 1]
    # All following binnings are equivalent
    # (`nextfloat` is necessary in Fixed, due to the promise given in the regular)
    n = 10
    ε = nextfloat(0.1) # when dividing 0-nextfloat(1) into 10, you get this width
    binnings = [
        RectangularBinning(n),
        RectangularBinning(n, true),
        RectangularBinning(ε),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n), 1, true),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n), 1, false),
    ]

    for bin in binnings
        o = ValueBinning(bin)
        ospace = outcome_space(o, x)
        codes = codify(o, x)
        @test codes isa Vector{Int}
    end

    # Higher dimensions
    y = StateSpaceSet(rand(rng, 100, 2)) # tuples whose elements are on [0, 1]
    binnings = [
        RectangularBinning(n),
        RectangularBinning(n, true),
        RectangularBinning(ε),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n), 2, true),
        FixedRectangularBinning(range(0, nextfloat(1.0); length = n), 2, false),
    ]
    for bin in binnings
        o = ValueBinning(bin)
        ospace = outcome_space(o, y)
        codes = codify(o, y)
        @test codes isa Vector{Int}
    end

    
    # When the dimensions of the fixed rectangular binning and input data don't match
    ranges = (0:0.1:1, range(0, 1; length = 101), range(0, 3.2; step = 0.33))
    f = FixedRectangularBinning(ranges)
    o = ValueBinning(f)
    x = rand(rng, 100)
    y = StateSpaceSet(rand(rng, 100, 2))
    @test_throws DimensionMismatch codify(o, x)
    @test_throws DimensionMismatch codify(o, y)
end