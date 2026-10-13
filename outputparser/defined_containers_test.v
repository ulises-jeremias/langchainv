module outputparser

struct DefinedContainers {
	maybe_labels ?[]string
	maybe_active ?[]bool
	maybe_scores ?[]int
	maybe_map    ?map[string]string
	maybe_counts ?map[string]int
	matrix       [][]string
	switches     [][]bool
	grid         [][]int
	dicts        []map[string]int
	word_lists   map[string][]string
	flag_lists   map[string][]bool
}

fn test_defined_parser_supports_optional_and_nested_containers() {
	parser := new_defined(DefinedContainers{}) or { panic(err) }
	instructions := parser.format_instructions()
	assert instructions.contains('"maybe_labels": string[] | null;')
	assert instructions.contains('"maybe_active": boolean[] | null;')
	assert instructions.contains('"maybe_scores": number[] | null;')
	assert instructions.contains('"maybe_map": Record<string, string> | null;')
	assert instructions.contains('"maybe_counts": Record<string, number> | null;')
	assert instructions.contains('"matrix": string[][];')
	assert instructions.contains('"switches": boolean[][];')
	assert instructions.contains('"grid": number[][];')
	assert instructions.contains('"dicts": Record<string, number>[];')
	assert instructions.contains('"word_lists": Record<string, string[]>;')
	assert instructions.contains('"flag_lists": Record<string, boolean[]>;')
	parsed := parser.parse('```json\n{"maybe_labels":["a"],"maybe_active":null,"maybe_scores":[1,2],"maybe_map":{"k":"v"},"maybe_counts":null,"matrix":[["x","y"]],"switches":[[true]],"grid":[[1,2],[3]],"dicts":[{"n":1}],"word_lists":{"w":["a","b"]},"flag_lists":{"f":[true,false]}}\n```') or {
		panic(err)
	}
	labels := parsed.maybe_labels or { panic('expected maybe_labels') }
	assert labels == ['a']
	assert parsed.maybe_active == none
	scores := parsed.maybe_scores or { panic('expected maybe_scores') }
	assert scores == [1, 2]
	counts_is_none := parsed.maybe_counts == none
	assert counts_is_none
	assert parsed.matrix[0] == ['x', 'y']
	assert parsed.grid[1] == [3]
	assert parsed.dicts[0]['n'] == 1
	assert parsed.word_lists['w'] == ['a', 'b']
	assert parsed.flag_lists['f'] == [true, false]
}
