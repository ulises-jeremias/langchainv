// Package cloudsqlutil builds validated Cloud SQL connection settings.
module cloudsqlutil

import strings

// user_agent identifies this client family to Google services.
pub const user_agent = 'langchainv-cloud-sql-pg/0.1.0'

// Options identifies one Cloud SQL instance and database. Field rules follow
// Google resource naming: lowercase letters, digits, and dashes, bounded
// lengths, and no leading or trailing dash.
pub struct Options {
pub:
	project     string
	region      string
	instance    string
	database    string
	user        string
	password    string
	ip_type     string = 'PUBLIC'
	schema_name string = 'public'
}

// instance_connection_name returns project:region:instance after
// validating every component.
pub fn instance_connection_name(options Options) !string {
	options.validate()!
	return '${options.project}:${options.region}:${options.instance}'
}

// postgres_dsn builds a PostgreSQL DSN for the instance through a caller
// supplied host and port, for example a local Cloud SQL Auth Proxy or a
// private endpoint the caller resolved. The password segment is omitted
// when empty, which suits IAM database authentication where the caller
// supplies a token through its own driver setup. Credentials are
// percent-encoded; the returned string still contains the password when one
// is set, so do not log it.
pub fn postgres_dsn(options Options, host string, port int) !string {
	options.validate()!
	if host.trim_space() == '' || host.bytes().any(it in [` `, `/`, `@`, `?`, `#`]) {
		return error('Cloud SQL host must be a non-empty host name or address')
	}
	if port < 1 || port > 65535 {
		return error('Cloud SQL port must be between 1 and 65535')
	}
	mut auth := percent_encode(options.user)
	if options.password != '' {
		auth += ':${percent_encode(options.password)}'
	}
	return 'postgres://${auth}@${host}:${port}/${options.database}?sslmode=require'
}

// validate checks every connection component without network access.
pub fn (options Options) validate() ! {
	validate_component('project', options.project, 63)!
	validate_component('region', options.region, 63)!
	validate_component('instance', options.instance, 63)!
	if options.database.trim_space() == '' || options.database.len > 63
		|| options.database.bytes().any(it in [`\0`, ` `, `/`, `?`, `#`]) {
		return error('Cloud SQL database must contain 1..63 bytes without spaces or URL separators')
	}
	if options.user.trim_space() == '' || options.user.len > 256 || options.user.contains('\0') {
		return error('Cloud SQL user must contain 1..256 bytes')
	}
	if options.password.len > 4096 || options.password.contains('\0') {
		return error('Cloud SQL password must contain at most 4096 bytes')
	}
	if options.ip_type !in ['PUBLIC', 'PRIVATE', 'PSC'] {
		return error('Cloud SQL ip_type must be PUBLIC, PRIVATE, or PSC')
	}
	if options.schema_name.trim_space() == '' || options.schema_name.len > 63 {
		return error('Cloud SQL schema_name must contain 1..63 bytes')
	}
}

fn validate_component(name string, value string, max_len int) ! {
	if value.len == 0 || value.len > max_len {
		return error('Cloud SQL ${name} must contain 1..${max_len} bytes')
	}
	if value.starts_with('-') || value.ends_with('-') {
		return error('Cloud SQL ${name} must not start or end with a dash')
	}
	for character in value.bytes() {
		if !(character >= `a` && character <= `z`) && !(character >= `0` && character <= `9`)
			&& character != `-` {
			return error('Cloud SQL ${name} must use lowercase letters, digits, and dashes')
		}
	}
}

fn percent_encode(value string) string {
	mut builder := strings.new_builder(value.len)
	for character in value.bytes() {
		if (character >= `a` && character <= `z`) || (character >= `A` && character <= `Z`)
			|| (character >= `0` && character <= `9`) || character in [`-`, `_`, `.`, `~`] {
			builder.write_u8(character)
		} else {
			hex_digits := '0123456789ABCDEF'
			builder.write_u8(`%`)
			builder.write_u8(hex_digits[character >> 4])
			builder.write_u8(hex_digits[character & 15])
		}
	}
	return builder.str()
}
