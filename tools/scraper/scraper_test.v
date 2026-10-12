module scraper

import context
import ulises_jeremias.langchainv.httputil

@[heap]
struct ScraperFixtureState {
mut:
	requests []httputil.Request
}

struct ScraperFixtureHTTP {
	state     &ScraperFixtureState
	responses []string
}

fn (client ScraperFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	index := state.requests.len - 1
	if index >= client.responses.len {
		return error('unexpected scraper fixture request')
	}
	return httputil.Response{
		status_code: 200
		body:        client.responses[index]
	}
}

fn test_scraper_extracts_page_content_and_follows_bounded_same_origin_links() {
	mut state := &ScraperFixtureState{}
	http := ScraperFixtureHTTP{
		state:     state
		responses: [
			'<html><head><title>Home</title><meta name="description" content="Start here"></head><body><h1>Welcome</h1><p>Home text.</p><a href="/about">About</a><a href="https://other.example/">External</a><a href="/login">Login</a><a href="/about#team">About again</a></body></html>',
			'<html><head><title>About</title></head><body><h2>About us</h2><p>About text.</p></body></html>',
		]
	}
	crawler := new_scraper(httputil.HTTPClient(http), Options{
		max_pages: 2
	}) or { panic(err) }
	mut ctx := context.background()
	result := crawler.call(mut ctx, 'https://example.com/') or { panic(err) }
	assert state.requests.len == 2
	assert state.requests[0].url == 'https://example.com/'
	assert state.requests[0].headers['Accept'] == 'text/html,application/xhtml+xml'
	assert state.requests[1].url == 'https://example.com/about'
	assert result.contains('Page Title: Home')
	assert result.contains('Page Description: Start here')
	assert result.contains('Welcome')
	assert result.contains('Home text.')
	assert result.contains('About text.')
	assert !result.contains('External')
	assert !result.contains('Login')
	assert result.contains('Scraped Links:\nhttps://example.com/\nhttps://example.com/about')
}

fn test_scraper_accepts_json_url_and_rejects_non_https_urls() {
	mut state := &ScraperFixtureState{}
	crawler := new_scraper(httputil.HTTPClient(ScraperFixtureHTTP{
		state:     state
		responses: ['<html><body><p>ok</p></body></html>']
	}), Options{
		max_depth: 1
	}) or { panic(err) }
	mut ctx := context.background()
	assert crawler.call(mut ctx, '{"url":"https://example.com"}') or { panic(err) }.contains('ok')
	crawler.call(mut ctx, 'http://example.com') or {
		assert err.msg().contains('valid HTTPS URL')
		return
	}
	assert false, 'expected HTTP URL to be rejected'
}

fn test_scraper_enforces_page_and_output_limits() {
	new_scraper(httputil.HTTPClient(ScraperFixtureHTTP{
		state:     &ScraperFixtureState{}
		responses: []
	}), Options{
		max_pages: 21
	}) or {
		assert err.msg().contains('maximum pages')
		return
	}
	assert false, 'expected excessive page count to fail'
	mut state := &ScraperFixtureState{}
	crawler := new_scraper(httputil.HTTPClient(ScraperFixtureHTTP{
		state:     state
		responses: ['<html><body><p>very long paragraph</p></body></html>']
	}), Options{
		max_depth:        1
		max_page_bytes:   1024
		max_total_bytes:  1024
		max_output_bytes: 16
	}) or { panic(err) }
	mut ctx := context.background()
	crawler.call(mut ctx, 'https://example.com') or {
		assert err.msg().contains('output exceeds')
		return
	}
	assert false, 'expected output size limit to fail'
}

fn test_scraper_omits_http_error_body() {
	crawler := new_scraper(httputil.HTTPClient(ScraperErrorHTTP{}), Options{}) or { panic(err) }
	mut ctx := context.background()
	crawler.call(mut ctx, 'https://example.com') or {
		assert err.msg() == 'scraper request returned HTTP 403'
		assert !err.msg().contains('private provider details')
		return
	}
	assert false, 'expected failed scrape request'
}

struct ScraperErrorHTTP {}

fn (client ScraperErrorHTTP) do(mut _ctx context.Context, _request httputil.Request) !httputil.Response {
	return httputil.Response{
		status_code: 403
		body:        'private provider details'
	}
}
