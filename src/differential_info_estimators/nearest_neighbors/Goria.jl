using StateSpaceSets: AbstractStateSpaceSet, StateSpaceSet
using Neighborhood: KDTree, NeighborNumber, Theiler
using Neighborhood: bulksearch
using SpecialFunctions: digamma

export Goria

"""
    Goria <: DifferentialInfoEstimator
    Goria(measure = Shannon(); k = 1, w = 0, base = 2)

The `Goria` estimator computes the [`Shannon`](@ref) differential
[`information`](@ref) of a multi-dimensional [`StateSpaceSet`](@ref) in the given `base`.

## Description

Assume we have samples ``\\{\\bf{x}_1, \\bf{x}_2, \\ldots, \\bf{x}_N \\}`` from a
continuous random variable ``X \\in \\mathbb{R}^d`` with support ``\\mathcal{X}`` and
density function``f : \\mathbb{R}^d \\to \\mathbb{R}``. `Goria` estimates
the [Shannon](@ref) differential entropy

```math
H(X) = \\int_{\\mathcal{X}} f(x) \\log f(x) dx = \\mathbb{E}[-\\log(f(X))].
```


Specifically, let ``\\bf{n}_1, \\bf{n}_2, \\ldots, \\bf{n}_N`` be the distance of the
samples ``\\{\\bf{x}_1, \\bf{x}_2, \\ldots, \\bf{x}_N \\}`` to their
`k`-th nearest neighbors. Next, let the geometric mean of the distances be

```math
\\hat{\\rho}_k = \\left( \\prod_{i=1}^N \\right)^{\\dfrac{1}{N}}
```
Goria et al. (2005)[^Goria2005]'s estimate of Shannon differential entropy is then

```math
\\hat{H} = m\\hat{\\rho}_k + \\log(N - 1) - \\psi(k) + \\log c_1(m),
```

where ``c_1(m) = \\dfrac{2\\pi^\\frac{m}{2}}{m \\Gamma(m/2)}`` and ``\\psi``
is the digamma function.

[^Goria2005]:
    Goria, M. N., Leonenko, N. N., Mergel, V. V., & Novi Inverardi, P. L. (2005). A new
    class of random vector entropy estimators and its applications in testing statistical
    hypotheses. Journal of Nonparametric Statistics, 17(3), 277-297.
"""
struct Goria{I <: InformationMeasure, B} <: NNDifferentialInfoEstimator{I}
    measure::I
    k::Int
    w::Int
    base::B
end
function Goria(measure = Shannon(); k = 1, w = 0, base = 2)
    return Goria(measure, k, w, base)
end

function information(est::Goria{<:Shannon}, x::AbstractStateSpaceSet{D}) where D
    (; k, w) = est
    N = length(x)

    tree = KDTree(x, Euclidean())
    ds = last.(bulksearch(tree, x, NeighborNumber(k), Theiler(w))[2])
    # The estimated entropy has "unit" [nats]
    h = D * log(prod(ds .^ (1 / N))) +
          log(N - 1) +
          log(c1(D)) -
          digamma(k)
    return convert_logunit(h, ℯ, est.base)
end
c1(D::Int) = (2π^(D/2)) / (D* gamma(D/2))