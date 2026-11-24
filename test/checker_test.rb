require 'minitest/autorun'
require 'socket'
require_relative '../checker'

class ClassifyTest < Minitest::Test
  def c(exit_code, http_code, connect_code = 0)
    classify(exit_code: exit_code, http_code: http_code, connect_code: connect_code)
  end

  def test_rule1_connect_refused
    assert_equal [:unreachable, 'proxy refused CONNECT (HTTP 502)'], c(0, 0, 502)
  end

  def test_rule1_wins_over_curl_error
    assert_equal [:unreachable, 'proxy refused CONNECT (HTTP 403)'], c(56, 0, 403)
  end

  def test_connect_200_is_fine
    assert_equal [:reachable, 'HTTP 200'], c(0, 200, 200)
  end

  def test_rule2_proxy_auth
    assert_equal [:unreachable, 'proxy authentication required (HTTP 407)'], c(0, 407)
  end

  def test_rule3_curl_exit
    status, reason = c(7, 0)
    assert_equal :unreachable, status
    assert_equal "#{CURL_EXIT_MESSAGES[7]} (curl exit 7)", reason
  end

  def test_rule3_unknown_exit_code
    assert_equal [:unreachable, 'curl error (curl exit 999)'], c(999, 0)
  end

  def test_rule3_http_zero_with_exit_zero
    assert_equal [:unreachable, "#{CURL_EXIT_MESSAGES[0]} (curl exit 0)"], c(0, 0)
  end

  def test_rule4_403
    assert_equal [:reachable, 'HTTP 403 (may come from a proxy, check the Server header)'], c(0, 403)
  end

  def test_rule5_other_codes
    assert_equal [:reachable, 'HTTP 301'], c(0, 301)
    assert_equal [:reachable, 'HTTP 404'], c(0, 404)
  end
end

class RedactTest < Minitest::Test
  def test_masks_url_credentials
    out = redact('http://bob:s3cret@proxy:8080')
    refute_includes out, 's3cret'
    refute_includes out, 'bob'
    assert_equal 'http://***:***@proxy:8080', out
  end

  def test_masks_proxy_authorization_trace_line
    out = redact('> Proxy-Authorization: Basic Ym9iOnMzY3JldA==')
    refute_includes out, 'Ym9i'
    assert_equal '> Proxy-Authorization: ***', out
  end

  def test_masks_authorization_case_insensitive
    out = redact("> authorization: Bearer abc.def\nother")
    refute_includes out, 'abc.def'
    assert_includes out, "other"
  end
  def test_masks_token_only_userinfo
    out = redact('http://tok@proxy:8080')
    refute_includes out, 'tok'
    assert_includes out, 'proxy:8080'
  end

  def test_masks_password_with_raw_at
    out = redact('http://bob:p@ss@proxy:8080/x')
    refute_includes out, 'p@ss'
    refute_includes out, 'ss@'
    refute_includes out, 'bob'
    assert_includes out, '@proxy:8080/x'
  end

  def test_masks_curl_auth_user_lines
    ["* Proxy auth using Basic with user 'bob'", "* Server auth using Basic with user 'bob'"].each do |line|
      out = redact(line)
      refute_includes out, 'bob'
      assert_includes out, 'auth using Basic with user'
    end
  end

  def test_leaves_plain_text_unchanged
    ['https://www.googleapis.com/', 'https://h/p?x=a@b', 'mail user@example.com now',
     'https_proxy=proxy.corp:3128', 'https://h?u=a@b.com', 'https://host#f@x'].each do |t|
      assert_equal t, redact(t)
    end
  end

  def test_masks_scheme_less_proxy_userinfo_in_env_line
    out = redact('HTTPS_PROXY=bob:s3cret@127.0.0.1:9')
    assert_equal 'HTTPS_PROXY=***:***@127.0.0.1:9', out
    assert_equal '***:***@127.0.0.1:9', redact('bob:s3cret@127.0.0.1:9')
  end

  def test_masks_scheme_less_proxy_userinfo_in_curl_trace
    out = redact("* Uses proxy env variable HTTPS_PROXY == 'bob:s3cret@127.0.0.1:9'")
    assert_equal "* Uses proxy env variable HTTPS_PROXY == '***:***@127.0.0.1:9'", out
  end

  def test_masks_scheme_less_token_only_userinfo_in_curl_trace
    out = redact("* Uses proxy env variable https_proxy == 'tok@127.0.0.1:9'")
    refute_includes out, 'tok'
    assert_includes out, '@127.0.0.1:9'
  end

  def test_already_masked_text_unchanged
    ['http://***:***@proxy:8080', 'HTTPS_PROXY=***:***@127.0.0.1:9',
     "* Uses proxy env variable HTTPS_PROXY == '***:***@127.0.0.1:9'"].each do |t|
      assert_equal t, redact(t)
    end
  end
end

class EncodingTest < Minitest::Test
  def test_redact_survives_invalid_utf8
    out = redact("< Server: caf\xE9\n> Proxy-Authorization: Basic abc\n".b)
    assert_equal Encoding::UTF_8, out.encoding
    assert out.valid_encoding?
    assert_includes out, '< Server: caf?'
    refute_includes out, 'abc'
  end

  def test_redact_survives_us_ascii_with_high_bytes
    text = "< Server: Kurumsal G\u00fcvenlik Duvar\u0131\n".b.force_encoding(Encoding::US_ASCII)
    assert_includes redact(text), "Kurumsal G\u00fcvenlik Duvar\u0131"
  end

  def test_server_header_survives_invalid_bytes
    assert_equal 'caf?', server_header("< Server: caf\xE9\r\n".b)
    text = "< Server: G\u00fcvenlik\n".b.force_encoding(Encoding::US_ASCII)
    assert_equal "G\u00fcvenlik", server_header(text)
  end
end

class ServerHeaderTest < Minitest::Test
  def test_extracts_server
    assert_equal 'squid', server_header("< HTTP/1.1 403 Forbidden\n< Server: squid\n< Content-Length: 0\n")
  end

  def test_last_server_wins_and_case_insensitive
    assert_equal 'nginx', server_header("< Server: squid\n< server: nginx\r\n")
  end

  def test_nil_when_absent
    assert_nil server_header("< HTTP/1.1 200 OK\n")
  end
end

class CheckTest < Minitest::Test
  PROXY_VARS = %w[HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy].freeze

  def setup
    @saved = PROXY_VARS.each_with_object({}) { |k, h| h[k] = ENV[k] }
    PROXY_VARS.each { |k| ENV.delete(k) }
  end

  def teardown
    @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def test_reachable_on_404
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      client.write("HTTP/1.1 404 Not Found\r\nServer: unit-test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      client.close
    end
    endpoint = { store: 'Custom', url: "http://127.0.0.1:#{port}/" }
    result = nil
    out, = capture_io { result = check(endpoint, 5, 10) }
    thread.join(5)
    server.close
    assert_includes out, '@@[command]'
    assert_equal :reachable, result.status
    assert_equal 404, result.http_code
    assert_equal 0, result.exit_code
    assert_equal 'unit-test', server_header(result.trace)
    assert_equal 'Custom', result.store
    assert_equal endpoint[:url], result.url
  end

  def test_non_utf8_server_header_does_not_crash
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      client.write("HTTP/1.1 403 Forbidden\r\nServer: caf\xE9 proxy\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".b)
      client.close
    end
    result = nil
    capture_io { result = check({ store: 'Custom', url: "http://127.0.0.1:#{port}/" }, 5, 10) }
    thread.join(5)
    server.close
    assert_kind_of Result, result
    assert_equal :reachable, result.status
    assert_equal 403, result.http_code
    assert_equal 'caf? proxy', server_header(result.trace)
  end

  def test_unreachable_when_nothing_listens
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    result = nil
    capture_io { result = check({ store: 'Custom', url: "http://127.0.0.1:#{port}/" }, 5, 10) }
    assert_equal :unreachable, result.status
    assert_equal 7, result.exit_code
    assert_equal 0, result.http_code
  end

  def test_command_line_is_redacted
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    out, = capture_io { check({ store: 'Custom', url: "http://bob:s3cret@127.0.0.1:#{port}/" }, 5, 10) }
    refute_includes out, 's3cret'
  end
end
