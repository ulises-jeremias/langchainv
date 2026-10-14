module alloydbutil

fn test_instance_connection_name_and_dsn() {
	options := Options{
		project:  'my-project'
		region:   'us-central1'
		cluster:  'my-cluster'
		instance: 'my-instance'
		database: 'docs'
		user:     'svc@example.iam'
		password: 'p@ss:word'
	}
	name := instance_connection_name(options) or { panic(err) }
	assert name == 'my-project:us-central1:my-cluster:my-instance'
	dsn := postgres_dsn(options, '127.0.0.1', 5432) or { panic(err) }
	assert dsn == 'postgres://svc%40example.iam:p%40ss%3Aword@127.0.0.1:5432/docs?sslmode=require'
}

fn test_iam_dsn_omits_password() {
	options := Options{
		project:  'my-project'
		region:   'us-central1'
		cluster:  'my-cluster'
		instance: 'my-instance'
		database: 'docs'
		user:     'svc@example.iam'
	}
	dsn := postgres_dsn(options, '10.0.0.5', 5432) or { panic(err) }
	assert dsn == 'postgres://svc%40example.iam@10.0.0.5:5432/docs?sslmode=require'
}

fn test_options_reject_invalid_components() {
	Options{
		project:  'Bad_Project'
		region:   'us-central1'
		cluster:  'my-cluster'
		instance: 'my-instance'
		database: 'docs'
		user:     'svc'
	}.validate() or {
		assert err.msg().contains('project')
		return
	}
	assert false, 'expected an invalid project to fail'
}

fn test_options_reject_unknown_ip_type_and_bad_port() {
	options := Options{
		project:  'my-project'
		region:   'us-central1'
		cluster:  'my-cluster'
		instance: 'my-instance'
		database: 'docs'
		user:     'svc'
		ip_type:  'SIDEWAYS'
	}
	options.validate() or {
		assert err.msg().contains('ip_type')
		postgres_dsn(Options{
			project:  'my-project'
			region:   'us-central1'
			cluster:  'my-cluster'
			instance: 'my-instance'
			database: 'docs'
			user:     'svc'
		}, '127.0.0.1', 70000) or {
			assert err.msg().contains('port')
			return
		}
		assert false, 'expected an invalid port to fail'
	}
	assert false, 'expected an unknown ip_type to fail'
}
