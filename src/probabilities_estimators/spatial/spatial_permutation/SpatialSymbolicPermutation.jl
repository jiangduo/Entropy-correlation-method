using StaticArrays: @MVector

export SpatialSymbolicPermutation
###########################################################################################
# type creation
###########################################################################################

"""
    SpatialSymbolicPermutation <: ProbabilitiesEstimator
    SpatialSymbolicPermutation(stencil, x; periodic = true)

A symbolic, permutation-based probabilities estimator for spatiotemporal systems that
generalises [`SymbolicPermutation`](@ref) to high-dimensional arrays.

`SpatialSymbolicPermutation` is based on the 2D and 3D *spatiotemporal permutation entropy*
estimators by by Ribeiro et al. (2012)[^Ribeiro2012] and Schlemmer et al.
(2018)[^Schlemmer2018]), respectively, but is here implemented as a pure probabilities
probabilities estimator that is generalized for `N`-dimensional input data `x`,
with arbitrary neighborhood regions (stencils) and periodic boundary conditions.

In combination with [`entropy`](@ref) and [`entropy_normalized`](@ref), this
probabilities estimator can be used to compute (normalized) generalized spatiotemporal
permutation [`Entropy`](@ref) of any type.

## Arguments

- `stencil`. Defines what local area (hyperrectangle), or which points within this area,
    to include around each hypervoxel (i.e. pixel in 2D). The examples below demonstrate
    different ways of specifying stencils. For details, see
    [`SpatialSymbolicPermutation`](@ref).
-  `x::AbstractArray`. The input data. Must be provided because we need to know its size
    for optimization and bound checking.

## Keyword arguments

- `periodic::Bool`. If `periodic == true`, then the stencil should wrap around at the
    end of the array. If `periodic = false`, then pixels whose stencil exceeds the array
    bounds are skipped.

## Stencils

Stencils are passed in one of the following three ways:

1. As vectors of `CartesianIndex` which encode the pixels to include in the
    stencil, with respect to the current pixel, or integer arrays of the same dimensionality
    as the data. For example `stencil = CartesianIndex.([(0,0), (0,1), (1,1), (1,0)])`.
    Don't forget to include the zero offset index if you want to include the point itself,
    which is almost always the case.
    Here the stencil creates a 2x2 square extending to the bottom and right of the pixel
    (directions here correspond to the way Julia prints matrices by default).
    When passing a stencil as a vector of `CartesianIndex`, `m = length(stencil)`.

2. As a `D`-dimensional array (where `D` matches the dimensionality of the input data)
    containing `0`s and `1`s, where if `stencil[index] == 1`, the corresponding pixel is
    included, and if `stencil[index] == 0`, it is not included.
    To generate the same estimator as in 1., use `stencil = [1 1; 1 1]`.
    When passing a stencil as a `D`-dimensional array, `m = sum(stencil)`

3. As a `Tuple` containing two `Tuple`s, both of length `D`, for `D`-dimensional data.
    The first tuple specifies the `extent` of the stencil, where `extent[i]`
    dictates the number of pixels to be included along the `i`th axis and `lag[i]`
    the separation of pixels along the same axis.
    This method can only generate (hyper)rectangular stencils. To create the same estimator as
    in the previous examples, use here `stencil = ((2, 2), (1, 1))`.
    When passing a stencil using `extent` and `lag`, `m = prod(extent)!`.

## Example: spatiotemporal entropy for time series

Usage is simple. First, define a `SpatialSymbolicPermutation` estimator by specifying
a stencil and giving some input data (a matrix with the same dimensions as the data
as you're going to analyse). Then simply call [`entropy`](@ref) with the estimator.

```julia
using Entropies
x = rand(50, 50) # first "time slice" of a spatial system evolution
stencil = [1 1; 0 1] # or one of the other ways of specifying stencils
est = SpatialSymbolicPermutation(stencil, x)
h = entropy(est, x)
```

To apply this to timeseries of spatial data, simply loop over the call, e.g.:

```julia
data = [rand(50, 50) for i in 1:50]
est = SpatialSymbolicPermutation(stencil, first(data))
h_vs_t = [entropy(est, d) for d in data]
```

Computing generalized spatiotemporal permutation entropy is trivial, e.g. with
[`Renyi`](@ref):

```julia
x = reshape(repeat(1:5, 500) .+ 0.1*rand(500*5), 50, 50)
est = SpatialSymbolicPermutation(stencil, x)
entropy(Renyi(q = 2), est, x)
```

## Outcome space

The outcome space `Ω` for `SpatialSymbolicPermutation` is the set of length-`m` ordinal
patterns (i.e. permutations) that can be formed by the integers `1, 2, …, m`,
ordered lexicographically. There are `factorial(m)` such patterns.
Here, `m` refers to the number of points included by `stencil`.

[^Ribeiro2012]:
    Ribeiro et al. (2012). Complexity-entropy causality plane as a complexity measure
    for two-dimensional patterns. https://doi.org/10.1371/journal.pone.0040689

[^Schlemmer2018]:
    Schlemmer et al. (2018). Spatiotemporal Permutation Entropy as a Measure for
    Complexity of Cardiac Arrhythmia. https://doi.org/10.3389/fphy.2018.00039
"""
struct SpatialSymbolicPermutation{D,P,V} <: SpatialProbEst{D, P}
    stencil::Vector{CartesianIndex{D}}
    viewer::Vector{CartesianIndex{D}}
    arraysize::Dims{D}
    valid::V
    lt::Function
    m::Int
end

function SpatialSymbolicPermutation(stencil, x::AbstractArray{T, D};
        periodic::Bool = true, lt = isless_rand) where {T, D}
    stencil, arraysize, valid = preprocess_spatial(stencil, x, periodic)
    m = stencil_length(stencil)

    SpatialSymbolicPermutation{D, periodic, typeof(valid)}(
        stencil, copy(stencil), arraysize, valid, lt, m
    )
end

function probabilities(est::SpatialSymbolicPermutation, x)
    # TODO: This can be literally a call to `symbolize` and then
    # calling probabilities on it. Should do once the `symbolize` refactoring is done.
    s = zeros(Int, length(est.valid))
    probabilities!(s, est, x)
end

function probabilities!(s, est::SpatialSymbolicPermutation, x)
    encodings_from_permutations!(s, est, x)
    return probabilities(s)
end

function probabilities_and_outcomes(est::SpatialSymbolicPermutation, x)
    # TODO: This can be literally a call to `symbolize` and then
    # calling probabilities on it. Should do once the `symbolize` refactoring is done.
    s = zeros(Int, length(est.valid))
    probabilities_and_outcomes!(s, est, x)
end

function probabilities_and_outcomes!(s, est::SpatialSymbolicPermutation, x)
    m, lt = est.m, est.lt
    encoding = OrdinalPatternEncoding(; m, lt)

    encodings_from_permutations!(s, est, x)
    observed_outcomes = decode.(Ref(encoding), s)
    return probabilities(s), observed_outcomes
end

# Pretty printing
function Base.show(io::IO, est::SpatialSymbolicPermutation{D}) where {D}
    print(io, "Spatial permutation estimator for $D-dimensional data. Stencil:")
    print(io, "\n")
    show(io, MIME"text/plain"(), est.stencil)
end

function outcome_space(est::SpatialSymbolicPermutation)
    encoding = OrdinalPatternEncoding(; est.m, est.lt)
    decode.(Ref(encoding), 1:factorial(est.m))
end

function total_outcomes(est::SpatialSymbolicPermutation)
    return factorial(est.m)
end

function check_preallocated_length!(πs, est::SpatialSymbolicPermutation{D, periodic}, x::AbstractArray{T, N}) where {D, periodic, T, N}
    if periodic
        # If periodic boundary conditions, then each pixel has a well-defined neighborhood,
        # and there are as many encoded symbols as there are pixels.
        length(πs) == length(x) ||
            throw(
                ArgumentError(
                    """Need length(πs) == length(x), got `length(πs)=$(length(πs))`\
                    and `length(x)==$(length(x))`."""
                )
            )
    else
        # If not periodic, then we must count the number of encoded symbols from the
        # valid coordinates of the estimator.
        length(πs) == length(est.valid) ||
        throw(
            ArgumentError(
                """Need length(πs) == length(est.valid), got `length(πs)=$(length(πs))`\
                and `length(est.valid)==$(length(est.valid))`."""
            )
        )
    end
end

function encodings_from_permutations!(πs, est::SpatialSymbolicPermutation{D, periodic},
        x::AbstractArray{T, N}) where {T, N, D, periodic}
    m, lt = est.m, est.lt
    check_preallocated_length!(πs, est, x)
    encoding = OrdinalPatternEncoding(; m, lt)

    perm = @MVector zeros(Int, m)
    for (i, pixel) in enumerate(est.valid)
        pixels = pixels_in_stencil(est, pixel)
        sortperm!(perm, view(x, pixels)) # Find permutation for currently selected pixels.
        πs[i] = encode(encoding, perm) # Encode based on the permutation.
    end
    return πs
end
