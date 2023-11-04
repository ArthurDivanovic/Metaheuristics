"""
    tabu_search(g::ColoredGraph, nb_iter::Int, neigh_iter::Int, tabu_iter::Int)::Tuple{Vector{Int}, Int}

Tabu search over a Colored Graph with a random neighboor generation. 

# Arguments 
- g                     ::ColoredGraph  : Graph instance
- nb_iter               ::Int           : Number of iterations for the global algorithm 
- neigh_iter            ::Int           : Number of neighboors generated at each iteration
- tabu_iter             ::Int           : Number of iterations forbidden for a neighboor (v,c) visited
- distance_threshold    ::Float64       : Diversification if distance(g.colors, plateau) <= distance_threshold*|V| 

"""
function tabu_search(g::ColoredGraph, nb_iter::Int, neigh_iter::Int, tabu_iter::Int, distance_threshold::Float64)
    start_time = time()

    tabu_table = ones(Int, g.n, g.k)

    plateau = Dict{Int, Vector{Vector{Int}}}()
    distance_plateau =  Dict{Int, Vector{Int}}()
    # iter_plateau = Dict{Int, Vector{Int}}()
    # iter_diversification = Vector{Int}()
    # println("first_update : ", length(g.conflict_history) + 1)

    @showprogress dt=1 desc="Computing..." for i in 1:nb_iter

        #initialize a random neighbor
        v0, c0, delta0 = random_neighbor(g)

        best_v, best_c, best_delta = v0, c0, delta0

        still_v0_c0 = true
        for j = 1:neigh_iter
            #Get a new neighbor according to the tabu table
            v, c, delta = random_neighbor_with_tabu!(g, tabu_table, tabu_iter, i)
            
            #If this neighbor is not forbidden and is the best one so far : change best neighbor
            if !isnothing(delta) && delta <= best_delta
                still_v0_c0 = false
                best_v, best_c, best_delta = v, c, delta
            end
        end

        #If the best neighbor is still the initial one but it is forbidden : cancel this iteration
        if still_v0_c0 && tabu_table[v0,c0] >= i
            continue

        #Else update coloration
        else
            update!(g, best_v, best_c, best_delta)
            if g.nb_conflict < g.nb_conflict_min
                update_min!(g, start_time)
                if g.nb_conflict_min == 0
                    break
                end
            end

            # If the new coloration is not improving g.nb_conflict 
            if best_delta >= 0
                if haskey(plateau, g.nb_conflict)
                    # push!(distance_plateau[g.nb_conflict], get_distance(plateau[g.nb_conflict], g.colors, g.k))
                    # push!(iter_plateau[g.nb_conflict], i)

                    dist = minimum([get_distance(plateau[g.nb_conflict][i], g.colors, g.k) for i = 1:length(plateau[g.nb_conflict])])
                    
                    if dist < Int(floor(distance_threshold*g.n))
                        color_diversification(g, distance_threshold)
                        # push!(iter_diversification, length(g.conflict_history))
                    else
                        push!(plateau[g.nb_conflict], deepcopy(g.colors)) # new plateau identified
                    end
                else
                    plateau[g.nb_conflict] = Vector{Int}()
                    push!(plateau[g.nb_conflict], deepcopy(g.colors))
                    distance_plateau[g.nb_conflict] = Vector{Int}()
                    # iter_plateau[g.nb_conflict] = Int[i]
                end
            end
        end

        
    end
    println("plateaux : ", keys(plateau))
    println("distance_plateau : ", distance_plateau)
    # println("iter_plateau : ", iter_plateau)
    # println("iter_diversification : ", iter_diversification)
end


mutable struct TabuSearch <: Heuristic
    nb_iter             ::Int
    neigh_iter          ::Int
    tabu_iter           ::Int
    distance_threshold  ::Float64
end

function (heuristic::TabuSearch)(g::ColoredGraph)
    solving_time = @elapsed begin
        tabu_search(g, heuristic.nb_iter, heuristic.neigh_iter, heuristic.tabu_iter, heuristic.distance_threshold)
    end
    
    g.resolution_time += solving_time

    push!(g.heuristics_applied, heuristic)
end

function save_parameters(heuristic::TabuSearch, file_name::String)
    file = open("results/$file_name", "a")

    write(file, "h TabuSearch = nb_iter:$(heuristic.nb_iter) neigh_iter:$(heuristic.neigh_iter) tabu_iter:$(heuristic.tabu_iter)\n")

    close(file)
end

"""
    random_neighbor_with_tabu(g::ColoredGraph)::Tuple{Int,Int,Int}

Return a random neighbor of 'g.colors', i.e. the same coloration but one vertice with a different color if it's not forbidden by tabu_table. 
Update tabu_table.

# Arguments 
- g             ::ColoredGraph  : Graph instance
- tabu_table    ::Matrix{Int}   : Tabu table with tabu_table[v,c] = the minimum algorithm iteration number allowed to put colors[v] = c
- tabu_iter     ::Int           : Number of iterations forbidden for a neighboor (v,c) visited
- iter          ::Int           : Current algorithm iteration number 

# Outputs
- v             ::Int           : Vertice from g
- new_c         ::Int           : New color for v (different than 'g.colors[v]')
- delta         ::Int           : Delta between g.nb_conflict and the conflict number from the neighbor generated
"""

function random_neighbor_with_tabu!(g::ColoredGraph, tabu_table::Matrix{Int}, tabu_iter::Int, iter::Int)::Tuple{Int,Int,Union{Nothing,Int}}
    v = rand(1:g.n)

    current_c = g.colors[v]
    new_c_idx = rand(1:(g.k-1))

    new_c = 0
    if new_c_idx < current_c
        new_c = new_c_idx
    else
        new_c = new_c_idx + 1
    end

    delta = nothing

    if !is_tabu(g, v, new_c, tabu_table, iter)
        delta = eval_delta_modif(g, v, new_c)
        tabu_table[v,new_c] = iter + tabu_iter

        for i = 1:g.n
            tabu_table[i,g.colors[i]] =  iter + tabu_iter
        end
    end
    
    return v, new_c, delta
end

"""
    is_tabu(g::ColoredGraph, v::Int, c::Int, tabu_table::Matrix{Int}, iter::Int)::Bool

Returns true if changing the color of vertice v to c is tabu, and false otherwise.

# Arguments 
- g             ::ColoredGraph  : Graph instance
- v             ::Int           : Index of the vertice under scrutiny 
- c             ::Int           : Index of the color under scrutiny 
- tabu_table    ::Matrix{Int}   : Tabu table with tabu_table[v,c] = the minimum algorithm iteration number allowed to put colors[v] = c

# Outputs
- tabu_neighbor ::Bool          : Boolean describing if the change is tabu or not
"""

function is_tabu(g::ColoredGraph, v::Int, c::Int, tabu_table::Matrix{Int}, iter::Int)::Bool
    tabu_neighbor = true
    if tabu_table[v, c] <= iter
        tabu_neighbor = false
    else
        for i = 1:g.n
            if tabu_table[i,g.colors[i]] <= iter 
                tabu_neighbor = false
                break
            end
        end
    end
    return tabu_neighbor
end

"""
    color_diversification(g::ColoredGraph, distance_threshold::Float64)

This step belongs to the diversification process of the tabu search. It updates the colors of a percentage of the vertices of the graph.

# Arguments 
- g                     ::ColoredGraph  : Graph instance
- distance_threshold    ::Float64       : Distance threshold used in the diversification process. It represents the percentage of |V| 
                                            used to define a configuration as close to another.


# Outputs
None, the function only updates the graph.
"""

function color_diversification(g::ColoredGraph, distance_threshold::Float64)
    nb_iter = Int(floor(distance_threshold*g.n))

    for i = 1:nb_iter
        v, c, delta = random_neighbor(g)
        update!(g, v, c, delta)
    end
end