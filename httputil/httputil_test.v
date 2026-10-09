module httputil

import net.http
import net.urllib

fn test_user_agent_is_stable_and_nonempty() {
	assert user_agent() != ''
	assert user_agent() == user_agent()
	assert user_agent().contains('langchainv/')
}

fn test_fetch_config_user_agent_default_and_application_identifier() {
	default_config := http.FetchConfig{}
	configured_default := with_user_agent(default_config)
	assert configured_default.user_agent == user_agent()
	application_config := http.FetchConfig{
		user_agent: 'example/1.0'
	}
	configured_application := with_user_agent(application_config)
	assert configured_application.user_agent == 'example/1.0 ${user_agent()}'
}

fn test_add_api_key_preserves_query_and_existing_key() {
	with_key := add_api_key('https://example.test/path?x=1', 'secret value') or {
		panic(err)
	}
	parsed := urllib.parse(with_key) or { panic(err) }
	assert parsed.query().get('x') or { '' } == '1'
	assert parsed.query().get('key') or { '' } == 'secret value'

	existing := add_api_key('https://example.test/path?key=provided&x=2', 'other') or {
		panic(err)
	}
	existing_url := urllib.parse(existing) or { panic(err) }
	assert existing_url.query().get('key') or { '' } == 'provided'
	assert existing_url.query().get('x') or { '' } == '2'

	duplicate_key := add_api_key('https://example.test/?key=&key=provided', 'other') or {
		panic(err)
	}
	duplicate_url := urllib.parse(duplicate_key) or { panic(err) }
	assert duplicate_url.query().get_all('key') == ['', 'provided']
}

fn test_safe_diagnostics_redact_credentials_and_omit_body() {
	safe_headers := redact_headers({
		'Authorization': 'Bearer private'
		'X-Api-Key':     'private'
		'Content-Type':  'application/json'
	})
	assert safe_headers['Authorization'] == '[REDACTED]'
	assert safe_headers['X-Api-Key'] == '[REDACTED]'
	assert safe_headers['Content-Type'] == 'application/json'

	url := safe_url('https://user:password@example.test/data?token=secret&limit=5')
	assert !url.contains('password')
	assert !url.contains('secret')
	assert url.contains('limit=5')
	assert request_summary('POST', 'https://example.test?key=private') == 'POST https://example.test?key=%5BREDACTED%5D'
}

fn test_fetch_redacts_transport_error_details() {
	fetch(http.FetchConfig{
		url: 'http://user:private@[invalid]/?token=private'
	}) or {
		assert !err.msg().contains('private')
		assert err.msg() == 'HTTP request failed (details redacted)'
		return
	}
	assert false
}
