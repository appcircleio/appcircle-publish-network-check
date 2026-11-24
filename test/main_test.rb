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

  def test_bad_timeouts_exit_one
    out, _err, status = run_main('AC_CHECK_CONNECTION_TIMEOUT' => '5', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '3')
    assert_equal 1, status.exitstatus
    assert_includes out, '@@[error]'
  end
end
