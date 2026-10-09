// Package textsplitter includes a Markdown-aware splitter that keeps section
// headings and block boundaries available to downstream retrieval pipelines.
module textsplitter

// MarkdownTextSplitterOptions configures structural Markdown chunking.
@[params]
pub struct MarkdownTextSplitterOptions {
pub:
	chunk_size             int = 512
	chunk_overlap          int = 100
	code_blocks            bool
	reference_links        bool
	keep_heading_hierarchy bool
	join_table_rows        bool
	length_fn              fn (string) int = rune_count
}

// MarkdownTextSplitter retains Markdown source syntax while splitting sections
// at headings, paragraphs, fenced code blocks, and table rows.
pub struct MarkdownTextSplitter {
	chunk_size             int
	chunk_overlap          int
	code_blocks            bool
	reference_links        bool
	keep_heading_hierarchy bool
	join_table_rows        bool
	length_fn              fn (string) int = rune_count
}

// new_markdown_text_splitter creates a Markdown splitter with validated chunk
// limits. Fenced code blocks are omitted by default, matching LangChainGo.
pub fn new_markdown_text_splitter(options MarkdownTextSplitterOptions) !MarkdownTextSplitter {
	if options.chunk_size <= 0 {
		return error('chunk size must be greater than zero')
	}
	if options.chunk_overlap < 0 || options.chunk_overlap >= options.chunk_size {
		return error('chunk overlap must be non-negative and less than chunk size')
	}
	return MarkdownTextSplitter{
		chunk_size:             options.chunk_size
		chunk_overlap:          options.chunk_overlap
		code_blocks:            options.code_blocks
		reference_links:        options.reference_links
		keep_heading_hierarchy: options.keep_heading_hierarchy
		join_table_rows:        options.join_table_rows
		length_fn:              options.length_fn
	}
}

// split_text chunks Markdown while preserving the source spelling of retained
// lines. Heading context is prepended to each generated chunk.
pub fn (splitter MarkdownTextSplitter) split_text(text string) ![]string {
	if text == '' {
		return []string{}
	}
	mut lines := text.split_into_lines()
	if splitter.reference_links {
		resolve_markdown_reference_links(text, mut lines)
	}
	mut headings := []string{}
	mut chunks := []string{}
	mut block := []string{}
	mut table_header := []string{}
	mut table_rows := []string{}
	mut in_table := false
	mut in_fence := false
	mut fence_marker := ''
	mut fence_length := 0
	for i := 0; i < lines.len; i++ {
		line := lines[i]
		if in_fence {
			if splitter.code_blocks {
				block << line
			}
			if is_closing_fence(line, fence_marker, fence_length) {
				in_fence = false
				if splitter.code_blocks {
					chunks << splitter.flush_markdown_block(block, headings)!
				}
				block = []string{}
			}
			continue
		}
		if fence := opening_fence(line) {
			if block.len > 0 {
				chunks << splitter.flush_markdown_block(block, headings)!
				block = []string{}
			}
			in_fence = true
			fence_marker = fence.marker
			fence_length = fence.length
			if splitter.code_blocks {
				block << line
			}
			continue
		}
		level, is_heading := markdown_heading_level(line)
		if is_heading {
			if in_table && table_rows.len > 0 {
				chunks << splitter.flush_table_group(table_header, table_rows, headings)!
				table_rows = []string{}
			}
			if block.len > 0 {
				chunks << splitter.flush_markdown_block(block, headings)!
				block = []string{}
			}
			set_heading(mut headings, level, line)
			in_table = false
			table_header = []string{}
			continue
		}
		setext_level, is_setext := markdown_setext_level(line)
		if is_setext && block.len > 0 {
			title := block[block.len - 1]
			if title.trim_space() != '' {
				block.delete(block.len - 1)
				if block.len > 0 {
					chunks << splitter.flush_markdown_block(block, headings)!
					block = []string{}
				}
				mut heading := ''
				for _ in 0 .. setext_level {
					heading += '#'
				}
				heading += ' ${title.trim_space()}'
				set_heading(mut headings, setext_level, heading)
				in_table = false
				table_header = []string{}
				continue
			}
		}
		if !in_table {
			if is_table_start(lines, i) {
				if block.len > 0 {
					chunks << splitter.flush_markdown_block(block, headings)!
					block = []string{}
				}
				in_table = true
				table_header = [normalize_markdown_table_row(line)]
				table_header << normalize_table_delimiter(lines[i + 1])
				i++
				continue
			}
		}
		if in_table {
			if is_table_row(line) {
				row := normalize_markdown_table_row(line)
				if !splitter.join_table_rows {
					chunks << splitter.flush_table_group(table_header, [row], headings)!
					continue
				}
				mut candidate := table_header.clone()
				candidate << table_rows
				candidate << row
				if table_rows.len > 0 && splitter.length_fn(candidate.join('\n')) > splitter.chunk_size {
					chunks << splitter.flush_table_group(table_header, table_rows, headings)!
					table_rows = [row]
				} else {
					table_rows << row
				}
				continue
			}
			if table_rows.len > 0 {
				chunks << splitter.flush_table_group(table_header, table_rows, headings)!
				table_rows = []string{}
			}
			in_table = false
			table_header = []string{}
		}
		block << line
	}
	if in_table && table_rows.len > 0 {
		chunks << splitter.flush_table_group(table_header, table_rows, headings)!
	}
	if in_fence && splitter.code_blocks && block.len > 0 {
		chunks << splitter.flush_markdown_block(block, headings)!
	} else if block.len > 0 {
		chunks << splitter.flush_markdown_block(block, headings)!
	}
	return chunks
}

fn (splitter MarkdownTextSplitter) flush_markdown_block(lines []string, headings []string) ![]string {
	content := lines.join('\n')
	context := splitter.heading_context(headings)
	parts := split_with_recursive_character(content, splitter.chunk_size, splitter.chunk_overlap,
		splitter.length_fn)!
	mut result := []string{}
	for part in parts {
		if context == '' {
			result << part
		} else {
			prefix := '${context}\n'
			if splitter.length_fn('${prefix}${part}') <= splitter.chunk_size {
				result << '${prefix}${part}'
			} else {
				bounded_parts := split_runes_with_prefix(part, splitter.chunk_size,
					splitter.chunk_overlap, default_max_fallback_runes, splitter.length_fn,
					prefix)!
				for bounded_part in bounded_parts {
					result << '${prefix}${bounded_part}'
				}
			}
		}
	}
	return result
}

fn (splitter MarkdownTextSplitter) flush_table_group(header []string, rows []string, headings []string) ![]string {
	mut table_lines := header.clone()
	table_lines << rows
	return splitter.flush_markdown_block(table_lines, headings)
}

fn (splitter MarkdownTextSplitter) heading_context(headings []string) string {
	if headings.len == 0 {
		return ''
	}
	if splitter.keep_heading_hierarchy {
		mut non_empty_headings := []string{}
		for heading in headings {
			if heading != '' {
				non_empty_headings << heading
			}
		}
		return non_empty_headings.join('\n')
	}
	for i := headings.len - 1; i >= 0; i-- {
		if headings[i] != '' {
			return headings[i]
		}
	}
	return ''
}

fn markdown_heading_level(line string) (int, bool) {
	mut offset := 0
	for offset < line.len && line[offset] == ` ` {
		offset++
	}
	if offset > 3 || offset == line.len {
		return 0, false
	}
	mut level := 0
	for offset + level < line.len && line[offset + level] == `#` && level < 6 {
		level++
	}
	if level == 0 || (offset + level < line.len && line[offset + level] != ` `
		&& line[offset + level] != `\t`) {
		return 0, false
	}
	return level, true
}

fn markdown_setext_level(line string) (int, bool) {
	trimmed := line.trim_space()
	if trimmed == '' {
		return 0, false
	}
	marker := trimmed[0]
	if marker != `=` && marker != `-` {
		return 0, false
	}
	for i in 0 .. trimmed.len {
		if trimmed[i] != marker {
			return 0, false
		}
	}
	if marker == `=` {
		return 1, true
	}
	return 2, true
}

fn set_heading(mut headings []string, level int, heading string) {
	for headings.len >= level {
		headings.delete(headings.len - 1)
	}
	for headings.len < level - 1 {
		headings << ''
	}
	headings << heading
}

struct MarkdownFence {
	marker string
	length int
}

fn opening_fence(line string) ?MarkdownFence {
	mut offset := 0
	for offset < line.len && line[offset] == ` ` {
		offset++
	}
	if offset > 3 || offset >= line.len || line[offset] == `\t` {
		return none
	}
	marker := line[offset]
	if marker != 96 && marker != `~` {
		return none
	}
	mut length := 0
	for offset + length < line.len && line[offset + length] == marker {
		length++
	}
	if length < 3 {
		return none
	}
	if marker == 96 && line[offset + length..].contains('`') {
		return none
	}
	return MarkdownFence{
		marker: line[offset..offset + 1]
		length: length
	}
}

fn is_closing_fence(line string, marker string, fence_length int) bool {
	mut offset := 0
	for offset < line.len && line[offset] == ` ` {
		offset++
	}
	if offset > 3 || offset >= line.len || line[offset] == `\t` {
		return false
	}
	mut length := 0
	for offset + length < line.len && line[offset + length..offset + length + 1] == marker {
		length++
	}
	if length < fence_length {
		return false
	}
	return line[offset + length..].trim_space() == ''
}

fn is_table_row(line string) bool {
	trimmed := line.trim_space()
	return trimmed.contains('|') && trimmed.len > 1
}

fn is_table_start(lines []string, index int) bool {
	if index + 1 >= lines.len {
		return false
	}
	return is_table_row(lines[index]) && is_table_delimiter(lines[index + 1])
}

fn is_table_delimiter(line string) bool {
	trimmed := line.trim_space()
	if !trimmed.contains('|') {
		return false
	}
	for cell in trimmed.trim('|').split('|') {
		value := cell.trim_space()
		if !value.contains('-')
			|| value.replace('-', '').replace(':', '').replace(' ', '').len != 0 {
			return false
		}
	}
	return true
}

fn normalize_markdown_table_row(line string) string {
	mut cells := []string{}
	for cell in line.trim_space().trim('|').split('|') {
		cells << cell.trim_space()
	}
	return '| ${cells.join(' | ')} |'
}

fn normalize_table_delimiter(line string) string {
	mut cells := []string{}
	for cell in line.trim_space().trim('|').split('|') {
		alignment := cell.trim_space()
		if alignment.starts_with(':') && alignment.ends_with(':') {
			cells << ':---:'
		} else if alignment.starts_with(':') {
			cells << ':---'
		} else if alignment.ends_with(':') {
			cells << '---:'
		} else {
			cells << '---'
		}
	}
	return '| ${cells.join(' | ')} |'
}

struct MarkdownLinkReference {
	destination string
	title       string
}

fn resolve_markdown_reference_links(source string, mut lines []string) {
	mut references := map[string]MarkdownLinkReference{}
	collect_markdown_link_references(source, mut references)
	mut in_fence := false
	mut fence_marker := ''
	mut fence_length := 0
	for i in 0 .. lines.len {
		line := lines[i]
		is_indented_code := line.starts_with('    ') || line.starts_with('\t')
		trimmed := line.trim_left(' \t')
		if in_fence {
			if is_closing_fence(line, fence_marker, fence_length) {
				in_fence = false
			}
			continue
		}
		if fence := opening_fence(line) {
			in_fence = true
			fence_marker = fence.marker
			fence_length = fence.length
			continue
		}
		if is_indented_code {
			continue
		}
		if is_reference_definition_line(trimmed) {
			continue
		}
		lines[i] = inline_reference_links(line, references)
	}
}

fn collect_markdown_link_references(source string, mut references map[string]MarkdownLinkReference) {
	mut in_fence := false
	mut fence_marker := ''
	mut fence_length := 0
	lines := source.split_into_lines()
	for i, line in lines {
		trimmed := line.trim_left(' \t')
		if in_fence {
			if is_closing_fence(line, fence_marker, fence_length) {
				in_fence = false
			}
			continue
		}
		if fence := opening_fence(line) {
			in_fence = true
			fence_marker = fence.marker
			fence_length = fence.length
			continue
		}
		if line.starts_with('    ') || line.starts_with('\t') || !is_reference_definition_line(trimmed) {
			continue
		}
		label_end := markdown_bracket_close(trimmed, 0)
		label := normalize_markdown_reference_label(trimmed[1..label_end])
		mut value := trimmed[label_end + 2..].trim_space()
		mut destination := ''
		if value.starts_with('<') {
			close := value.index('>') or { continue }
			destination = value[1..close]
			value = value[close + 1..].trim_space()
		} else {
			mut end := 0
			mut parentheses := 0
			for end < value.len {
				if value[end] == `\\` && end + 1 < value.len {
					end += 2
					continue
				}
				if value[end] in [` `, `\t`] {
					break
				}
				if value[end] == `(` {
					parentheses++
				} else if value[end] == `)` {
					if parentheses == 0 {
						break
					}
					parentheses--
				}
				end++
			}
			if parentheses != 0 {
				continue
			}
			destination = value[..end]
			value = value[end..].trim_space()
		}
		if destination == '' {
			continue
		}
		mut title := ''
		if value != '' {
			title = parse_markdown_reference_title(value) or { continue }
		} else if i + 1 < lines.len {
			next_line := lines[i + 1].trim_left(' \t')
			if parsed_title := parse_markdown_reference_title(next_line) {
				title = parsed_title
			}
		}
		if label !in references {
			references[label] = MarkdownLinkReference{
				destination: destination
				title:       title
			}
		}
	}
}

fn parse_markdown_reference_title(value string) ?string {
	if value.len < 2 {
		return none
	}
	opening := value[0]
	closing := if opening == `(` { `)` } else { opening }
	if opening !in [`"`, `\'`, `(`] || value[value.len - 1] != closing {
		return none
	}
	mut preceding_backslashes := 0
	mut previous := value.len - 2
	for previous >= 0 && value[previous] == `\\` {
		preceding_backslashes++
		previous--
	}
	if preceding_backslashes % 2 == 1 {
		return none
	}
	mut index := 1
	for index < value.len - 1 {
		if value[index] == `\\` && index + 1 < value.len - 1 {
			index += 2
			continue
		}
		if value[index] == closing {
			return none
		}
		index++
	}
	return unescape_markdown_reference_component(value[1..value.len - 1])
}

fn unescape_markdown_reference_component(value string) string {
	mut output := ''
	mut index := 0
	for index < value.len {
		if value[index] == `\\` && index + 1 < value.len && is_ascii_punctuation(value[index + 1]) {
			output += value[index + 1..index + 2]
			index += 2
		} else {
			output += value[index..index + 1]
			index++
		}
	}
	return output
}

fn is_ascii_punctuation(character u8) bool {
	return character >= `!` && character <= `~`
		&& !(character >= `0` && character <= `9`)
		&& !(character >= `A` && character <= `Z`)
		&& !(character >= `a` && character <= `z`)
}

fn inline_reference_links(line string, references map[string]MarkdownLinkReference) string {
	mut output := ''
	mut index := 0
	for index < line.len {
		if line[index] == `\\` && index + 1 < line.len {
			output += line[index..index + 2]
			index += 2
			continue
		}
		if line[index] == `\`` {
			mut marker_end := index + 1
			for marker_end < line.len && line[marker_end] == `\`` {
				marker_end++
			}
			marker := line[index..marker_end]
			mut closing := marker_end
			mut matched := false
			for closing < line.len {
				found := line.index_after(marker, closing) or { break }
				candidate_end := found + marker.len
				if (found == 0 || line[found - 1] != `\``)
					&& (candidate_end == line.len || line[candidate_end] != `\``) {
					output += line[index..found + marker.len]
					index = found + marker.len
					matched = true
					break
				}
				closing = candidate_end
			}
			if !matched {
				output += marker
				index = marker_end
			}
			continue
		}
		if line[index] != `[` {
			output += line[index..index + 1]
			index++
			continue
		}
		close := markdown_bracket_close(line, index)
		if close < 0 {
			output += '['
			index++
			continue
		}
		if close + 1 < line.len && line[close + 1] == `(` {
			output += line[index..close + 1]
			index = close + 1
			continue
		}
		mut label := line[index + 1..close]
		mut final_close := close
		if close + 1 < line.len && line[close + 1] == `[` {
			reference_close := markdown_bracket_close(line, close + 1)
			if reference_close > close + 1 {
				label = line[close + 2..reference_close]
				final_close = reference_close
			}
		}
		normalized_label := normalize_markdown_reference_label(label)
		if reference := references[normalized_label] {
			output += line[index..close + 1] + markdown_inline_destination(reference)
			index = final_close + 1
		} else {
			output += line[index..close + 1]
			index = close + 1
		}
	}
	return output
}

fn markdown_inline_destination(reference MarkdownLinkReference) string {
	mut target := if reference.destination.contains(' ') {
		reference.destination
	} else {
		'<${reference.destination}>'
	}
	if reference.title != '' {
		title := reference.title
		if title.contains('"') && !title.contains("'") {
			target += " '${title}'"
		} else {
			escaped_title := title.replace('"', '\\"')
			target += ' "${escaped_title}"'
		}
	}
	return '(${target})'
}

fn markdown_bracket_close(line string, opening int) int {
	mut depth := 0
	mut index := opening
	for index < line.len {
		if line[index] == `\\` {
			index += 2
			continue
		}
		if line[index] == `[` {
			depth++
		} else if line[index] == `]` {
			depth--
			if depth == 0 {
				return index
			}
		}
		index++
	}
	return -1
}

fn normalize_markdown_reference_label(label string) string {
	mut words := []string{}
	for word in label.trim_space().to_lower().split_any(' \t\n\r') {
		if word != '' {
			words << word
		}
	}
	return words.join(' ')
}

fn is_reference_definition_line(line string) bool {
	if !line.starts_with('[') {
		return false
	}
	close := markdown_bracket_close(line, 0)
	if close <= 1 || close + 1 >= line.len || line[close + 1] != `:` {
		return false
	}
	return normalize_markdown_reference_label(line[1..close]) != ''
}

fn split_with_recursive_character(text string, chunk_size int, chunk_overlap int, length_fn fn (string) int) ![]string {
	splitter := new_recursive_character_text_splitter(
		chunk_size:     chunk_size
		chunk_overlap:  chunk_overlap
		separators:     ['\n\n', '\n', ' ', '']
		keep_separator: true
		length_fn:      length_fn
	)!
	return splitter.split_text(text)
}
