package game

import pq "core:container/priority_queue"
import "core:fmt"
import math "core:math/linalg"

WorldPosition :: distinct [2]int

WorldPathfinder :: struct {
	entity: EntityHandle,
	start:  WorldPosition,
	dest:   WorldPosition,
	game:   ^GameMemory,
}

world_path_finder_init :: proc(wpf: ^WorldPathfinder, entity: EntityHandle, dest: WorldPosition) {
	wpf.entity = entity
	wpf.game = g_mem
	wpf.dest = dest

	entity, found := data_pool_get(&wpf.game.entities, wpf.entity)
	assert(found, "Programmer Error: Should never try to find a new path for non-existing entity")
	wpf.start = entity.world_pos
}

world_path_finder_get_path_t :: proc(wpf: WorldPathfinder) -> []Step {
	start := wpf.start

	to_search := SearchNodePQueue{}
	start_node := SearchNode{}
	start_node.pos = start
	start_node.h = get_estimated_distance(start, wpf.dest)

	pq.init(&to_search, search_node_less, search_node_swap, 128, context.temp_allocator)
	processed := make(map[WorldPosition]SearchNode, 128, context.temp_allocator)

	pq.push(&to_search, start_node)

	for pq.len(to_search) > 0 {
		current := pq.pop(&to_search)
		if current.pos in processed {
			continue
		}

		processed[current.pos] = current

		if current.pos == wpf.dest {
			path := make([dynamic]Step, context.temp_allocator)
			append(&path, Step{current.pos, current.step_cost})

			count := 0
			next := current.connection
			for {
				pos, is_pos := next.(WorldPosition)
				if !is_pos {
					return path[:]
				}
				node := processed[pos]
				append(&path, Step{pos, node.step_cost})
				next = node.connection
			}

			assert(false, "We did not actually find a good path")
		}

		neighbors := world_path_finder_get_neighbors(wpf, current)
		for n in neighbors {
			if n.pos in processed {
				continue
			}
			pq.push(&to_search, n)
		}
	}

	assert(false, "We should have a path")


	return []Step{}
}

world_path_finder_get_neighbors :: proc(wpf: WorldPathfinder, node: SearchNode) -> []SearchNode {
	nodes := make([dynamic]SearchNode, 0, 4, context.temp_allocator)
	offsets := [4]WorldPosition{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
	corners := [4]WorldPosition{{-1, 1}, {1, -1}, {-1, -1}, {1, 1}}

	for pos, i in &offsets {
		neighbor_node := SearchNode{}
		neighbor_node.pos = node.pos + pos
		neighbor_node.g = node.g + 10
		neighbor_node.h = get_estimated_distance(node.pos, wpf.dest)
		neighbor_node.step_cost = 1
		neighbor_node.connection = node.pos


		append(&nodes, neighbor_node)
	}
	for pos, i in &corners {
		// Special Case PF2E rule. Only first diagnal is 5ft, rest is 10ft
		cost := 1 if node.pos == wpf.start else 2

		neighbor_node := SearchNode{}
		neighbor_node.pos = node.pos + pos
		neighbor_node.g = node.g + cast(f32)(cost * 10)
		neighbor_node.h = get_estimated_distance(node.pos, wpf.dest)
		neighbor_node.step_cost = cost
		neighbor_node.connection = node.pos


		append(&nodes, neighbor_node)
	}
	return nodes[:]

}

Step :: struct {
	position:  WorldPosition,
	step_cost: int,
}

SearchNode :: struct {
	pos:        WorldPosition,
	g:          f32,
	h:          f32,
	step_cost:  int,
	connection: Connection,
}

Connection :: union {
	WorldPosition,
}

SearchNodePQueue :: pq.Priority_Queue(SearchNode)

search_node_less :: proc(a, b: SearchNode) -> bool {
	a_f := get_f(a)
	b_f := get_f(b)
	return a_f < b_f || a_f == b_f && a.h < b.h
}

search_node_swap :: proc(q: []SearchNode, i, j: int) {
	q[i], q[j] = q[j], q[i]
}

find_path_t :: proc(s_pos: WorldPosition, t_pos: WorldPosition) -> []Step {
	to_search := SearchNodePQueue{}
	pq.init(&to_search, search_node_less, search_node_swap, 128, context.temp_allocator)
	processed := make(map[WorldPosition]SearchNode, 128, context.temp_allocator)

	start := SearchNode{}
	start.pos = s_pos
	start.h = math.length(world_pos_to_vec(s_pos - t_pos))

	pq.push(&to_search, start)

	for pq.len(to_search) > 0 {
		current := pq.pop(&to_search)
		if current.pos in processed {
			continue
		}

		processed[current.pos] = current

		if current.pos == t_pos {
			path := make([dynamic]Step, context.temp_allocator)
			append(&path, Step{current.pos, current.step_cost})

			count := 0
			next := current.connection
			for {
				pos, is_pos := next.(WorldPosition)
				if !is_pos {
					return path[:]
				}
				node := processed[pos]
				append(&path, Step{pos, node.step_cost})
				next = node.connection
			}

			panic("Bad Branch")
		}

		neighbors := get_neighbors(current, t_pos, current.pos == s_pos)
		for n in neighbors {
			if n.pos in processed {
				continue
			}
			pq.push(&to_search, n)
		}
	}

	return []Step{}
}

get_f :: proc(n: SearchNode) -> f32 {
	return n.h + n.g
}

get_neighbors :: proc(
	search_node: SearchNode,
	target: WorldPosition,
	no_extra_corner_movement: bool,
) -> []SearchNode {
	nodes := make([dynamic]SearchNode, 0, 4, context.temp_allocator)
	offsets := [4]WorldPosition{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
	corners := [4]WorldPosition{{-1, 1}, {1, -1}, {-1, -1}, {1, 1}}

	for offset, i in &offsets {
		node := SearchNode{}
		node.pos = search_node.pos + offset
		node.g = search_node.g + 10
		node.h = math.length(world_pos_to_vec(node.pos - target)) * 10
		node.step_cost = 1
		node.connection = search_node.pos

		append(&nodes, node)
	}
	for offset, i in &corners {
		cost := 1 if no_extra_corner_movement else 2

		node := SearchNode{}
		node.pos = search_node.pos + offset
		node.g = search_node.g + cast(f32)(cost * 10)
		node.h = math.length(world_pos_to_vec(node.pos - target)) * 10
		node.step_cost = cost
		node.connection = search_node.pos


		append(&nodes, node)
	}
	return nodes[:]
}

step_total_cost :: proc(steps: []Step) -> int {
	total: int = 0
	for step in steps {
		total += step.step_cost
	}
	return total
}

@(private = "file")
get_estimated_distance :: proc(start, end: WorldPosition) -> f32 {
	return math.floor(math.length(world_pos_to_vec(start - end)) * 10)
}