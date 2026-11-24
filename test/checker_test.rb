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
