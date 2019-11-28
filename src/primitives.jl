# These do most of the work in the package.
# They are all @generated or recusive functions for performance.

const UnionAllTupleOrVector = Union{Vector{UnionAll},Tuple{UnionAll,Vararg}}

"""
Sort dimensions into the order they take in the array.

Missing dimensions are replaced with `nothing`
"""
@inline Base.permutedims(tosort::AbDimTuple, perm::Union{Vector{<:Integer},Tuple{<:Integer,Vararg}}) =
    map(p -> tosort[p], Tuple(perm))
@inline Base.permutedims(tosort::Union{Vector{<:Integer},Tuple{<:Integer,Vararg}}, perm::AbDimTuple) =
    tosort

@inline Base.permutedims(tosort::AbDimTuple, order::UnionAllTupleOrVector) =
    permutedims(tosort, Tuple(map(u -> u(), order)))
@inline Base.permutedims(tosort::UnionAllTupleOrVector, order::AbDimTuple) =
    permutedims(Tuple(map(u -> u(), tosort)), order)
@inline Base.permutedims(tosort::AbDimTuple, order::AbDimVector) =
    permutedims(tosort, Tuple(order))
@inline Base.permutedims(tosort::AbDimVector, order::AbDimTuple) =
    permutedims(Tuple(tosort), order)
@inline Base.permutedims(tosort::AbDimTuple, order::AbDimTuple) =
    Base.permutedims(tosort, order, map(d -> dims(grid(d)), order))
@generated Base.permutedims(tosort::AbDimTuple, order::AbDimTuple, griddims) =
    permutedims_inner(tosort, order, griddims)

permutedims_inner(tosort::Type, order::Type, griddims::Type) = begin
    indexexps = []
    for (i, dim) in enumerate(order.parameters)
        dimindex = findfirst(d -> basetypeof(d) <: basetypeof(dim), tosort.parameters)
        if dimindex == nothing
            # The grid may allow dimensions not in dims
            # that will be transformed to the actual dimensions (ie for rotations).
            if griddims <: Nothing
                push!(indexexps, :(nothing))
            else
                gridindex = findfirst(d -> basetypeof(d) <: basetypeof(griddims.parameters[i]), tosort.parameters)
                if gridindex == nothing
                    push!(indexexps, :(nothing))
                else
                    push!(indexexps, :(tosort[$gridindex]))
                end
            end
        else
            push!(indexexps, :(tosort[$dimindex]))
        end
    end
    Expr(:tuple, indexexps...)
end


"""
Convert a tuple of AbstractDimension to indices, ranges or Colon.
"""
@inline dims2indices(A, lookup, emptyval=Colon()) =
    dims2indices(dims(A), lookup, emptyval)
@inline dims2indices(dims::Tuple, lookup, emptyval=Colon()) =
    dims2indices(dims, (lookup,), emptyval)
@inline dims2indices(dims::Tuple, lookup::Tuple, emptyval=Colon()) =
    dims2indices(map(grid, dims), dims, permutedims(lookup, dims), emptyval)

# Deal with irregular grid types that need multiple dimensions indexed together
@inline dims2indices(grids::Tuple{DependentGrid,Vararg}, dims::Tuple, lookup::Tuple, emptyval) = begin
    (irregdims, irreglookup), (regdims, reglookup) = splitgridtypes(grids, dims, lookup)
    (irreg2indices(map(grid, irregdims), irregdims, irreglookup, emptyval)...,
     dims2indices(map(grid, regdims), regdims, reglookup, emptyval)...)
end

@inline dims2indices(grids::Tuple, dims::Tuple, lookup::Tuple, emptyval) = begin
    (dims2indices(grids[1], dims[1], lookup[1], emptyval),
     dims2indices(tail(grids), tail(dims), tail(lookup), emptyval)...)
end
@inline dims2indices(grids::Tuple{}, dims::Tuple{}, lookup::Tuple{}, emptyval) = ()

@inline dims2indices(grid, dim::AbDim, lookup::Type{<:AbDim}, emptyval) = Colon()
@inline dims2indices(grid, dim::AbDim, lookup::Nothing, emptyval) = emptyval
@inline dims2indices(grid, dim::AbDim, lookup::AbDim, emptyval) = val(lookup)
@inline dims2indices(grid, dim::AbDim, lookup::AbDim{<:Selector}, emptyval) =
    sel2indices(grid, dim, val(lookup))

# Selectors select on grid dimensions
@inline irreg2indices(grids::Tuple, dims::Tuple, lookup::Tuple{AbDim{<:Selector},Vararg}, emptyval) =
    sel2indices(grids, dims, map(val, lookup))
# Other dims select on regular dimensions
@inline irreg2indices(grids::Tuple, dims::Tuple, lookup::Tuple, emptyval) = begin
    (dims2indices(grids[1], dims[1], lookup[1], emptyval),
     dims2indices(tail(grids), tail(dims), tail(lookup), emptyval)...)
end

@inline splitgridtypes(grids::Tuple{DependentGrid,Vararg}, dims, lookup) = begin
    (irregdims, irreglookup), reg = splitgridtypes(tail(grids), tail(dims), tail(lookup))
    irreg = (dims[1], irregdims...), (lookup[1], irreglookup...)
    irreg, reg
end
@inline splitgridtypes(grids::Tuple{IndependentGrid,Vararg}, dims, lookup) = begin
    irreg, (regdims, reglookup) = splitgridtypes(tail(grids), tail(dims), tail(lookup))
    reg = (dims[1], regdims...), (lookup[1], reglookup...)
    irreg, reg
end
@inline splitgridtypes(grids::Tuple{}, dims, lookup) = ((), ()), ((), ())


"""
Slice the dimensions to match the axis values of the new array

All methods returns a tuple conatining two tuples: the new dimensions,
and the reference dimensions. The ref dimensions are no longer used in
the new struct but are useful to give context to plots.

Called at the array level the returned tuple will also include the
previous reference dims attached to the array.
"""
@inline slicedims(A, dims::AbDimTuple) = slicedims(A, dims2indices(A, dims))
@inline slicedims(dims2slice::AbDimTuple, dims::AbDimTuple) =
    slicedims(dims2slice, dims2indices(dims2slice, dims))
@inline slicedims(A, I::Tuple) = slicedims(dims(A), refdims(A), I)
@inline slicedims(dims::Tuple, refdims::Tuple, I::Tuple) = begin
    newdims, newrefdims = slicedims(dims, I)
    newdims, (refdims..., newrefdims...)
end
@inline slicedims(dims::Tuple{}, I::Tuple) = ((), ())
@inline slicedims(dims::AbDimTuple, I::Tuple) = begin
    d = slicedims(dims[1], I[1])
    ds = slicedims(tail(dims), tail(I))
    (d[1]..., ds[1]...), (d[2]..., ds[2]...)
end
@inline slicedims(dims::Tuple{}, I::Tuple{}) = ((), ())
@inline slicedims(d::AbDim, i::Colon) = ((rebuild(d, val(d)),), ())
@inline slicedims(d::AbDim, i::Number) = ((), (rebuild(d, val(d)[i]),))
@inline slicedims(d::AbDim{<:AbstractArray}, i::AbstractArray) =
    ((rebuild(d, val(d)[i]),), ())
@inline slicedims(d::AbDim{<:LinRange}, i::UnitRange) = begin
    range = val(d)
    start, stop, len = range[first(i)], range[last(i)], length(i) ÷ step(i)
    ((rebuild(d, LinRange(start, stop, len)),), ())
end


"""
Get the number of an AbstractDimension as ordered in the array
"""
@inline dimnum(A, lookup) = dimnum(typeof(dims(A)), lookup)
@inline dimnum(dimtypes::Type, lookup::AbstractArray) = dimnum(dimtypes, (lookup...,))
@inline dimnum(dimtypes::Type, lookup::Number) = lookup
@inline dimnum(dimtypes::Type, lookup::Tuple) =
    (dimnum(dimtypes, lookup[1]), dimnum(dimtypes, tail(lookup))...,)
@inline dimnum(dimtypes::Type, lookup::Tuple{}) = ()
@inline dimnum(dimtypes::Type, lookup::AbDim) = dimnum(dimtypes, typeof(lookup))
@generated dimnum(dimtypes::Type{DTS}, lookup::Type{D}) where {DTS,D} = begin
    index = findfirst(dt -> D <: basetypeof(dt), DTS.parameters)
    if index == nothing
        :(throw(ArgumentError("No $lookup in $dimtypes")))
    else
        :($index)
    end
end

hasdim(A, lookup) = hasdim(typeof(dims(A)), typeof(lookup))
hasdim(A, lookup::Type) = hasdim(typeof(dims(A)), lookup)
@generated hasdim(dimtypes::Type{DTS}, lookup::Type{D}) where {DTS,D} = begin
    index = findfirst(dt -> D <: basetypeof(dt), DTS.parameters)
    if index == nothing
        :(false)
    else
        :(true)
    end
end


"""
Format the dimension to match internal standards.

Mostily this means converting tuples and UnitRanges to LinRange,
which is easier to handle. Errors are thrown if dims don't match the array dims or size.
"""
@inline formatdims(A::AbstractArray{T,N}, dims::Tuple) where {T,N} = begin
    dimlen = length(dims)
    dimlen == N || throw(ArgumentError("dims ($dimlen) don't match array dimensions $(N)"))
    formatdims(size(A), dims)
end
@inline formatdims(size::Tuple, dims::Tuple) = map(formatdims, size, dims)
@inline formatdims(len::Integer, dim::AbDim{<:AbstractArray}) =
    if length(val(dim)) == len
        index = val(dim)
        rebuild(dim; grid=identify(grid(dim), index)) 
    else
        throw(ArgumentError("length of $dim $(length(index)) does not match
                             size of array dimension $len"))
    end
@inline formatdims(len::Integer, dim::AbDim{<:Union{AbstractRange,NTuple{2}}}) = 
    linrange(dim, len)
@inline formatdims(len::Integer, dim::AbDim) = dim

linrange(dim, len) = begin
    start, stop = first(val(dim)), last(val(dim))
    rebuild(dim, LinRange(start, stop, len), regularise(grid(dim), start, stop, len))
end

identify(::UnknownGrid, index::AbstractVector) = begin
    order = orderof(first(index), last(index))
    sorted = indexorder(order) == Forward() ? issorted(index) : issorted(index; rev=true)
    if sorted
        AllignedGrid(; order=order)
    else
        CategoricalGrid(; order=Unordered())
    end
end
identify(grid::Grid, index) = grid

regularise(::UnknownGrid, start, stop, len) = 
    RegularGrid(order=orderof(start, stop), span=spanof(start, stop, len))
regularise(grid::Grid, start, stop, len) = grid

spanof(a, b, len) = (b - a)/(len - 1)
orderof(a, b) = Ordered(a <= b ? Forward() : Reverse(), Forward())


"""
Replace the specified dimensions with an index of length 1 to match
a new array size where the dimension has been reduced to a length
of 1, but the number of dimensions has not changed.

Used in mean, reduce, etc.

Grid traits are also updated to correspond to the change in cell span, sampling
type and order.
"""
@inline reducedims(A, dimstoreduce) = reducedims(A, (dimstoreduce,))
@inline reducedims(A, dimstoreduce::Tuple) = reducedims(dims(A), dimstoreduce)
@inline reducedims(dims::AbDimTuple, dimstoreduce::Tuple) =
    map(reducedims, dims, permutedims(dimstoreduce, dims))
@inline reducedims(dims::AbDimTuple, dimstoreduce::Tuple{Vararg{Int}}) =
    map(reducedims, dims, permutedims(map(i -> dims[i], dimstoreduce), dims))

# Reduce matching dims, ignore nothing vals - they are the dims not being reduced
@inline reducedims(dim::AbDim, ::Nothing) = dim
@inline reducedims(dim::AbDim, ::AbDim) = reducedims(grid(dim), dim)
# Reduce specialising on grid type
@inline reducedims(grid::UnknownGrid, dim) = 
    rebuild(dim, first(val(dim)), UnknownGrid())
@inline reducedims(grid::CategoricalGrid, dim) = 
    rebuild(dim, [:combined], CategoricalGrid(Unordered()))
@inline reducedims(grid::AllignedGrid, dim) = begin 
    grid = AllignedGrid(Unordered(), locus(grid), MultiSample(), bounds(grid))
    rebuild(dim, reducedims(locus(grid), dim), grid)
end
@inline reducedims(grid::RegularGrid, dim) = begin
    grid = RegularGrid(Unordered(), locus(grid), MultiSample(), span(grid) * length(val(dim)))
    rebuild(dim, reducedims(locus(grid), dim), grid)
end
@inline reducedims(grid::DependentGrid, dim) = 
    rebuild(dim, [nothing], UnknownGrid)

# Get the index value at the reduced locus.
# This is the start, center or end point of the whole index.
reducedims(locus::Start, dim) = [first(val(dim))]
reducedims(locus::End, dim) = [last(val(dim))]
reducedims(locus::Center, dim) = begin
    index = val(dim)
    len = length(index)
    if iseven(len)
        [(index[len ÷ 2] + index[len ÷ 2 + 1]) / 2]
    else
        [index[len ÷ 2 + 1]]
    end
end


"""
Get the dimension(s) matching the type(s) of the lookup dimension.
"""
@inline dims(A, lookup) = dims(dims(A), lookup)
@inline dims(ds::AbDimTuple, lookup::Integer) = ds[lookup]
@inline dims(ds::AbDimTuple, lookup::Tuple) =
    (dims(ds, lookup[1]), dims(ds, tail(lookup))...)
@inline dims(ds::AbDimTuple, lookup::Tuple{}) = ()
@inline dims(ds::AbDimTuple, lookup) = dims(ds, basetypeof(lookup))
@generated dims(ds::DT, lookup::Type{L}) where {DT<:AbDimTuple,L} = begin
    index = findfirst(dt -> dt <: L, DT.parameters)
    if index == nothing
        :(throw(ArgumentError("No $lookup in $dims")))
    else
        :(ds[$index])
    end
end
