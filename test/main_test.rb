require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'socket'

class MainTest < Minitest::Test
  MAIN = File.expand_path('../main.rb', __dir__)

  PROXY_VARS = %w[HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy].freeze

  def run_main(env)
    clean = ENV.to_h.reject { |k, _| k.start_with?('AC_CHECK') || PROXY_VARS.include?(k) }
    Open3.capture3(clean.merge(env), RbConfig.ruby, MAIN, unsetenv_others: true)
  end

  # Serves one HTTP response on a local port; yields the port.
  def with_server(response)
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      client.write(response)
      client.close
    end
    yield server.addr[1]
  ensure
    thread.join(5) if thread
    server.close if server
  end

  def test_c_locale_with_non_ascii_server_header
    response = "HTTP/1.1 403 Forbidden\r\nServer: Kurumsal G\u00fcvenlik Duvar\u0131\r\n" \
               "Content-Length: 0\r\nConnection: close\r\n\r\n"
    with_server(response.b) do |port|
      out, err, status = run_main('LANG' => 'C', 'LC_ALL' => 'C',
                                  'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => "http://127.0.0.1:#{port}/")
      text = out.b
      assert_equal 0, status.exitstatus, text + err.b
      assert_match(%r{^http://127\.0\.0\.1:#{port}/ +\| REACHABLE}, text)
      assert_includes text, 'Kurumsal G'.b
    end
  end

  def test_no_endpoints_exits_zero
    out, _err, status = run_main({})
    assert_equal 0, status.exitstatus
    assert_includes out, "There aren't any URLs given to the component, exiting."
  end

  def test_timeout_fallback_is_printed
    out, _err, status = run_main('AC_CHECK_CONNECTION_TIMEOUT' => 'abc')
    assert_equal 0, status.exitstatus
    assert_match(/^@@\[warning\] AC_CHECK_CONNECTION_TIMEOUT .*"abc".*default/, out)
  end

  def test_unreachable_endpoint_exits_one_after_summary
    out, _err, status = run_main('AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => 'https://127.0.0.1:1/',
                                 'AC_CHECK_CONNECTION_TIMEOUT' => '2', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '5')
    assert_equal 1, status.exitstatus
    assert_match(%r{^https://127\.0\.0\.1:1/ +\| NOT REACHABLE +\| }, out)
    assert_includes out, '@@[error] 1 of 1 endpoints are not reachable.'
    assert out.index('| NOT REACHABLE') < out.index('@@[error]')
  end

  def test_proxy_password_with_hash_never_printed
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    out, err, status = run_main('HTTPS_PROXY' => "http://bob:pa#ss@127.0.0.1:#{port}",
                                'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => 'https://127.0.0.1:1/',
                                'AC_CHECK_CONNECTION_TIMEOUT' => '2', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '5')
    assert_equal 1, status.exitstatus
    assert_includes out, '@@[error] 1 of 1 endpoints are not reachable.'
    assert_includes out, 'HTTPS_PROXY=http://***:***@127.0.0.1:'
    [out, err].each do |text|
      refute_includes text, 'pa#ss'
      refute_includes text, 'Ym9iOnBhI3Nz'
    end
  end

  def test_bad_timeouts_exit_one
    out, _err, status = run_main('AC_CHECK_CONNECTION_TIMEOUT' => '5', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '3')
    assert_equal 1, status.exitstatus
    assert_includes out, '@@[error]'
  end
end
