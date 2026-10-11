// Package scraper provides a bounded same-origin HTML crawler.
module scraper

import context
import encoding.html as html_entities
import json2
import net.html
import net.urllib
import strings
import time
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const default_max_depth = 1
const default_max_pages = 10
const max_allowed_depth = 3
const max_allowed_pages = 20
const max_url_bytes = 4096
const default_max_page_bytes = i64(2 * 1024 * 1024)
const default_max_total_bytes = i64(8 * 1024 * 1024)
const default_max_output_bytes = i64(1024 * 1024)
const default_blacklist = ['login', 'signup', 'signin', 'register', 'logout', 'download', 'redirect']

// Options sets explicit bounds for a crawl. Zero selects a documented default.
pub struct Options {
pub:
	max_depth        int
	max_pages        int
	delay_ms         int
	max_page_bytes   i64
	max_total_bytes  i64
	max_output_bytes i64
	blacklist        []string
}

// Scraper follows same-origin links with sequential, bounded requests.
pub struct Scraper {
pub:
	max_depth        int
	max_pages        int
	delay_ms         int
	max_page_bytes   i64
	max_total_bytes  i64
	max_output_bytes i64
	blacklist        []string
mut:
	http_client httputil.HTTPClient
}

struct CrawlTask {
	url   string
	depth int
}

// new_scraper constructs a bounded scraper with an injectable HTTP transport.
pub fn new_scraper(http_client httputil.HTTPClient, options Options) !Scraper {
	max_depth := if options.max_depth == 0 { default_max_depth } else { options.max_depth }
	max_pages := if options.max_pages == 0 { default_max_pages } else { options.max_pages }
	max_page_bytes := if options.max_page_bytes == 0 {
		default_max_page_bytes
	} else {
		options.max_page_bytes
	}
	max_total_bytes := if options.max_total_bytes == 0 {
		default_max_total_bytes
	} else {
		options.max_total_bytes
	}
	max_output_bytes := if options.max_output_bytes == 0 {
		default_max_output_bytes
	} else {
		options.max_output_bytes
	}
	if max_depth < 0 || max_depth > max_allowed_depth {
		return error('scraper maximum depth must be between 0 and ${max_allowed_depth}')
	}
	if max_pages < 1 || max_pages > max_allowed_pages {
		return error('scraper maximum pages must be between 1 and ${max_allowed_pages}')
	}
	if options.delay_ms < 0 || options.delay_ms > 60000 {
		return error('scraper delay must be between 0 and 60000 milliseconds')
	}
	if max_page_bytes < 1 || max_page_bytes > i64(8 * 1024 * 1024) {
		return error('scraper page byte limit must be between 1 byte and 8 MiB')
	}
	if max_total_bytes < max_page_bytes || max_total_bytes > i64(32 * 1024 * 1024) {
		return error('scraper total byte limit must be at least the page limit and at most 32 MiB')
	}
	if max_output_bytes < 1 || max_output_bytes > i64(8 * 1024 * 1024) {
		return error('scraper output byte limit must be between 1 byte and 8 MiB')
	}
	blacklist := if options.blacklist.len == 0 { default_blacklist } else { options.blacklist }
	if blacklist.len > 64 {
		return error('scraper blacklist must contain at most 64 entries')
	}
	return Scraper{
		max_depth:        max_depth
		max_pages:        max_pages
		delay_ms:         options.delay_ms
		max_page_bytes:   max_page_bytes
		max_total_bytes:  max_total_bytes
		max_output_bytes: max_output_bytes
		blacklist:        blacklist.clone()
		http_client:      http_client
	}
}

// new_default_scraper uses the bounded default HTTP transport.
pub fn new_default_scraper(options Options) !Scraper {
	return new_scraper(httputil.HTTPClient(httputil.new_default_client()), options)
}

// spec describes the URL expected by the scraper tool.
pub fn (scraper Scraper) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'Web Scraper'
		description: 'Read a web page and a bounded number of same-origin linked pages.'
		parameters:  json2.Any({
			'type':       json2.Any('object')
			'properties': json2.Any({
				'url': json2.Any({
					'type': json2.Any('string')
				})
			})
			'required':   json2.Any([json2.Any('url')])
		})
	}
}

// call reads the page, extracts titles, descriptions, headings, paragraphs,
// and root-page links, and crawls same-origin links within configured limits.
pub fn (scraper Scraper) call(mut ctx context.Context, input string) !string {
	start_url := parse_url(input) or { return error('invalid scraper URL: ${err.msg()}') }
	mut queue := [CrawlTask{
		url:   start_url
		depth: 0
	}]
	mut seen := map[string]bool{}
	seen[start_url] = true
	mut output := strings.new_builder(4096)
	mut visited := []string{}
	mut total_bytes := i64(0)
	for queue.len > 0 && visited.len < scraper.max_pages {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		task := queue[0]
		queue.delete(0)
		if visited.len > 0 && scraper.delay_ms > 0 {
			time.sleep(time.Duration(scraper.delay_ms) * time.millisecond)
			ctx_error_after_delay := ctx.err()
			if ctx_error_after_delay !is none {
				return ctx_error_after_delay
			}
		}
		response := scraper.http_client.do(mut ctx, httputil.Request{
			url:     task.url
			headers: {
				'Accept': 'text/html,application/xhtml+xml'
			}
		})!
		if response.status_code < 200 || response.status_code >= 300 {
			return error('scraper request returned HTTP ${response.status_code}')
		}
		page_bytes := i64(response.body.len)
		if page_bytes > scraper.max_page_bytes {
			return error('scraper page exceeds the configured byte limit')
		}
		total_bytes += page_bytes
		if total_bytes > scraper.max_total_bytes {
			return error('scraper crawl exceeds the configured total byte limit')
		}
		visited << task.url
		dom := html.parse(response.body)
		root := dom.get_root()
		scraper.append_page(task.url, root, mut output)!
		if task.depth < scraper.max_depth {
			for anchor in root.get_tags('a') {
				if queue.len + visited.len >= scraper.max_pages {
					break
				}
				href := anchor.attributes['href'] or { continue }
				link := resolve_same_origin(task.url, href) or { continue }
				if link in seen || scraper.is_blacklisted(link) {
					continue
				}
				seen[link] = true
				queue << CrawlTask{
					url:   link
					depth: task.depth + 1
				}
			}
		}
	}
	if visited.len == 0 {
		return error('scraper did not visit any pages')
	}
	append_bounded(mut output, scraper.max_output_bytes, '\n\nScraped Links:')!
	for url in visited {
		append_bounded(mut output, scraper.max_output_bytes, '\n${url}')!
	}
	return output.str()
}

fn (scraper Scraper) append_page(url string, root &html.Tag, mut output strings.Builder) ! {
	append_bounded(mut output, scraper.max_output_bytes, '\n\nPage URL: ${url}')!
	if title := root.get_tag('title') {
		append_bounded(mut output, scraper.max_output_bytes, '\nPage Title: ${clean_text(title.text())}')!
	}
	if meta := root.get_tag_by_attribute_value('name', 'description') {
		description := meta.attributes['content'] or { '' }
		if description.trim_space() != '' {
			append_bounded(mut output, scraper.max_output_bytes, '\nPage Description: ${clean_text(description)}')!
		}
	}
	append_bounded(mut output, scraper.max_output_bytes, '\nHeaders:')!
	for name in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'] {
		for heading in root.get_tags(name) {
			text := clean_text(heading.text())
			if text != '' {
				append_bounded(mut output, scraper.max_output_bytes, '\n${text}')!
			}
		}
	}
	append_bounded(mut output, scraper.max_output_bytes, '\nContent:')!
	for paragraph in root.get_tags('p') {
		text := clean_text(paragraph.text())
		if text != '' {
			append_bounded(mut output, scraper.max_output_bytes, '\n${text}')!
		}
	}
}

fn (scraper Scraper) is_blacklisted(url string) bool {
	parsed := urllib.parse(url) or { return true }
	path := parsed.path.to_lower()
	for item in scraper.blacklist {
		if item != '' && path.contains(item.to_lower()) {
			return true
		}
	}
	return false
}

fn parse_url(input string) !string {
	url := if input.trim_space().starts_with('{') {
		values := json2.decode[map[string]json2.Any](input, json2.DecoderOptions{}) or {
			return error('input must be a URL or JSON object')
		}
		value := values['url'] or { return error('missing `url` field') }
		if value !is string {
			return error('`url` must be a string')
		}
		value as string
	} else {
		input
	}
	if url.trim_space() == '' || url.len > max_url_bytes {
		return error('scraper URL must be between 1 and ${max_url_bytes} bytes')
	}
	trimmed := url.trim_space()
	httputil.validate_url(trimmed, 'https') or {
		return error('scraper URL must be a valid HTTPS URL without user information')
	}
	return trimmed
}

fn resolve_same_origin(base_url string, href string) ?string {
	if href.trim_space() == '' || href.len > max_url_bytes {
		return none
	}
	base := urllib.parse(base_url) or { return none }
	reference := urllib.parse(href.trim_space()) or { return none }
	mut resolved := base.resolve_reference(reference) or { return none }
	if resolved.scheme.to_lower() != 'https' || resolved.host.to_lower() != base.host.to_lower() {
		return none
	}
	resolved.fragment = ''
	link := resolved.str()
	httputil.validate_url(link, 'https') or { return none }
	return link
}

fn append_bounded(mut output strings.Builder, max_bytes i64, value string) ! {
	if i64(output.len + value.len) > max_bytes {
		return error('scraper output exceeds the configured byte limit')
	}
	output.write_string(value)
}

fn clean_text(value string) string {
	return html_entities.unescape(value.replace('\n', ' ').replace('\t', ' ').trim_space(),
		all: true
	)
}
