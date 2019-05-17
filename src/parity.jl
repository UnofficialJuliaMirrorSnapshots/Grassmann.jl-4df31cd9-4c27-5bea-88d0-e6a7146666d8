
#   This file is part of Grassmann.jl. It is licensed under the GPL license
#   Grassmann Copyright (C) 2019 Michael Reed

@pure function parityjoin(N,S,a,b)
    B = DirectSum.ndigits(b<<1,N)
    isodd(sum(DirectSum.ndigits(a,N) .* cumsum(B))+count_ones((a .& b) .& S))
end

## adjoint parities

@pure parityreverse(G) = isodd(Int((G-1)*G/2))
@pure parityinvolute(G) = isodd(G)
@pure parityconj(G) = parityreverse(G)⊻parityinvolute(G)

## complement parity

@pure parityright(V::Int,B,G,N=nothing) = isodd(V)⊻isodd(B+Int((G+1)*G/2))
@pure parityleft(V::Int,B,G,N=nothing) = (isodd(G) && iseven(N)) ⊻ parityright(V,B,G,N)

for side ∈ (:left,:right)
    p = Symbol(:parity,side)
    @eval begin
        @pure $p(V::Bits,B::Bits,N::Int) = $p(count_ones(V&B),sum(indices(B,N)),count_ones(B))
        @pure $p(V::Signature,B,G=count_ones(B)) = $p(count_ones(value(V)&B),sum(indices(B,ndims(V))),G,ndims(V))
        @pure function $p(V::DiagonalForm,B,G=count_ones(B))
            ind = indices(B,ndims(V))
            g = prod(V[ind])
            $p(0,sum(ind),G,ndims(V)) ? -(g) : g
        end
        @pure $p(b::Basis{V,G,B}) where {V,G,B} = $p(V,B,G)
    end
end

## product parities

@pure conformalmask(V::T) where T<:VectorSpace = UInt(2)^(hasinf(V)+hasorigin(V))-1

@pure function parityconformal(V,A,B)
    bt = conformalmask(V)
    i2o,o2i = DirectSum.hasi2o(V,A,B),DirectSum.haso2i(V,A,B)
    A&bt, B&bt, i2o, o2i, i2o ⊻ o2i
end

@pure function parityregressive(V::Signature{N,M,S},A,B,::Grade{skew}=Grade{false}()) where {N,M,S,skew}
    α,β = complement(N,A),complement(N,B)
    cc = skew && (hasinforigin(V,A,β) || hasorigininf(V,A,β))
    if ((count_ones(α&β)==0) && !dualcheck(V,α,β)) || cc
        C,L = α ⊻ β, count_ones(A)+count_ones(B)
        pcc,bas = if skew
            A3,β3,i2o,o2i,xor = parityconformal(V,A,β)
            cx,bas = cc || xor, complement(N,C)
            cx && parity(A3,β3,V)⊻(i2o || o2i)⊻(xor&!i2o), cx ? (A3|β3)⊻bas : bas
        else
            false, A+B≠0 ? complement(N,C) : g_zero(UInt)
        end
        par = parityright(S,A,N)⊻parityright(S,B,N)⊻parityright(S,C,N)
        return (isodd(L*(L-N))⊻par⊻parity(N,S,α,β)⊻pcc)::Bool, bas, true
    else
        return false, g_zero(UInt), false
    end
end

@pure function parityregressive(V::DiagonalForm,A,B)
    p,C,t = regressive(A,B,Signature(V))
    return p ? -1 : 1, C, t
end

@pure function parityinterior(V::Signature{N,M,S},A,B) where {N,M,S}
    dualcheck(V,A,B) && (return false,g_zero(UInt),false)
    γ = complement(N,B)
    p,C,t = parityregressive(V,A,γ,Grade{true}())
    return t ? p⊻parityright(S,B,N) : p, C, t
end

@pure function parityinterior(V::DiagonalForm{N,M,S},A,B) where {N,M,S}
    dualcheck(V,A,B) && (return false,g_zero(UInt),false)
    γ = complement(N,B)
    p,C,t = parityregressive(Signature(V),A,γ,Grade{true}())
    ind = indices(B,N)
    g = prod(V[ind])
    return t ? (p⊻parityright(0,sum(ind),count_ones(B)) ? -(g) : g) : g, C, t
end

@pure function parityinner(a::Bits,b::Bits,V::DiagonalForm)
    g = abs(prod(V[indices(a&b,ndims(V))]))
    parity(a,b,Signature(V)) ? -(g) : g
end

@pure function paritycrossprod(::Signature{N,M,S},A,B) where {N,M,S}
    if (count_ones(A&B)==0) && !(hasinf(M) && isodd(A) && isodd(B))
        C = A ⊻ B
        return (parity(N,S,A,B)⊻parityright(S,C,N)), complement(N,C), true
    else
        return false, zero(Bits), false
    end
end

@pure function paritycrossprod(V::DiagonalForm{N,M,S}) where {N,M,S}
    if (count_ones(A&B)==0) && !(hasinf(M) && isodd(A) && isodd(B))
        C = A ⊻ B
        g = parityright(V,C,N)
        return parity(A,B,V) ? -(g) : g, complement(N,C), true
    else
        return 1, zero(Bits), false
    end
end

### parity cache

const parity_cache = Dict{Bits,Vector{Vector{Bool}}}[]
const parity_extra = Dict{Bits,Dict{Bits,Dict{Bits,Bool}}}[]
@pure function parity(n,s,a,b)::Bool
    if n > sparse_limit
        N = n-sparse_limit
        for k ∈ length(parity_extra)+1:N
            push!(parity_extra,Dict{Bits,Dict{Bits,Dict{Bits,Bool}}}())
        end
        @inbounds !haskey(parity_extra[N],s) && push!(parity_extra[N],s=>Dict{Bits,Dict{Bits,Bool}}())
        @inbounds !haskey(parity_extra[N][s],a) && push!(parity_extra[N][s],a=>Dict{Bits,Bool}())
        @inbounds !haskey(parity_extra[N][s][a],b) && push!(parity_extra[N][s][a],b=>parityjoin(n,s,a,b))
        @inbounds parity_extra[N][s][a][b]
    else
        a1 = a+1
        for k ∈ length(parity_cache)+1:n
            push!(parity_cache,Dict{Bits,Vector{Bool}}())
        end
        @inbounds !haskey(parity_cache[n],s) && push!(parity_cache[n],s=>Vector{Bool}[])
        @inbounds for k ∈ length(parity_cache[n][s]):a
            @inbounds push!(parity_cache[n][s],Bool[])
        end
        @inbounds for k ∈ length(parity_cache[n][s][a1]):b
            @inbounds push!(parity_cache[n][s][a1],parityjoin(n,s,a,k))
        end
        @inbounds parity_cache[n][s][a1][b+1]
    end
end
@pure parity(a::Bits,b::Bits,v::Signature) = parity(ndims(v),value(v),a,b)
@pure parity(a::Bits,b::Bits,v::VectorSpace) = parity(a,b,Signature(v))
@pure parity(a::Basis{V,G,B},b::Basis{V,L,C}) where {V,G,B,L,C} = parity(bits(a),bits(b),V)

### parity product caches

for par ∈ (:interior,:regressive,:crossprod)
    calc = Symbol(:parity,par)
    for (vs,space,dat) ∈ ((:_sig,Signature,Bool),(:_diag,DiagonalForm,Any))
        T = Tuple{dat,Bits,Bool}
        extra = Symbol(par,vs,:_extra)
        cache = Symbol(par,vs,:_cache)
        @eval begin
            const $cache = Vector{Dict{Bits,Vector{Vector{$T}}}}[]
            const $extra = Vector{Dict{Bits,Dict{Bits,Dict{Bits,$T}}}}[]
            @pure function ($par(a,b,V::$space{n,m,s})::$T) where {n,m,s}
                m1 = m+1
                if n > sparse_limit
                    N = n-sparse_limit
                    for k ∈ length($extra)+1:N
                        push!($extra,Dict{Bits,Dict{Bits,Dict{Bits,$T}}}[])
                    end
                    for k ∈ length($extra[N])+1:m1
                        push!($extra[N],Dict{Bits,Dict{Bits,Dict{Bits,$T}}}())
                    end
                    @inbounds !haskey($extra[N][m1],s) && push!($extra[N][m1],s=>Dict{Bits,Dict{Bits,$T}}())
                    @inbounds !haskey($extra[N][m1][s],a) && push!($extra[N][m1][s],a=>Dict{Bits,$T}())
                    @inbounds !haskey($extra[N][m1][s][a],b) && push!($extra[N][m1][s][a],b=>$calc(V,a,b))
                    @inbounds $extra[N][m1][s][a][b]
                else
                    a1 = a+1
                    for k ∈ length($cache)+1:n
                        push!($cache,Dict{Bits,Vector{Vector{$T}}}[])
                    end
                    for k ∈ length($cache[n])+1:m1
                        push!($cache[n],Dict{Bits,Vector{Vector{$T}}}())
                    end
                    @inbounds !haskey($cache[n][m1],s) && push!($cache[n][m1],s=>Vector{$T}[])
                    @inbounds for k ∈ length($cache[n][m1][s]):a
                        @inbounds push!($cache[n][m1][s],$T[])
                    end
                    @inbounds for k ∈ length($cache[n][m1][s][a1]):b
                        @inbounds push!($cache[n][m1][s][a1],$calc(V,a,k))
                    end
                    @inbounds $cache[n][m1][s][a1][b+1]
                end
            end
        end
    end
    @eval @pure $par(a::Basis{V,G,B},b::Basis{V,L,C}) where {V,G,B,L,C} = $par(bits(a),bits(b),V)
end

