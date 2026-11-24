require 'minitest/autorun'
require 'stringio'
require_relative '../report'

module ReportHelpers
  def strip_ansi(text)
    text.gsub(/\e\[[0-9;]*m/, '')
  end

  def ok_result
    Result.new(store: 'Google Play', url: 'https://www.googleapis.com/', status: :reachable,
               reason: 'HTTP 404', http_code: 404, connect_code: 0, exit_code: 0,
               time_total: 0.123, trace: "* Connected\n< HTTP/2 404\n")
  end

  def bad_result
    Result.new(store: 'App Store', url: 'https://does-not-exist.invalid/', status: :unreachable,
               reason: 'Could not resolve host (curl exit 6)', http_code: 0, connect_code: 0,
               exit_code: 6, time_total: 0.01, trace: "* Could not resolve host: does-not-exist.invalid\n")
  end
end

class SummaryTableTest < Minitest::Test
  include ReportHelpers

  def test_two_results
    expected = [
      'Endpoint                        | Result        | Reason',
      '--------------------------------+---------------+-------------------------------------',
      'https://www.googleapis.com/     | REACHABLE     | HTTP 404',
      'https://does-not-exist.invalid/ | NOT REACHABLE | Could not resolve host (curl exit 6)'
    ].join("\n")
    assert_equal expected, summary_table([ok_result, bad_result], huawei_not_checked: false)
  end

  def test_url_credentials_masked_in_summary
    r = bad_result
    r.url = 'https://alice:hunter2@127.0.0.1:1/'
    table = summary_table([r], huawei_not_checked: false)
    refute_includes table, 'hunter2'
    assert_includes table, 'https://***:***@127.0.0.1:1/ | NOT REACHABLE'
  end

  def test_huawei_row_present_only_when_flagged
    with = summary_table([ok_result], huawei_not_checked: true)
    without = summary_table([ok_result], huawei_not_checked: false)
    row = 'Huawei upload host (*.obs.*.otc.t-systems.com) | NOT CHECKED | ' \
          'dynamic, add it via AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'
    assert_includes with, row
    refute_includes without, 'Huawei'
  end
end

class PrintResultTest < Minitest::Test
  include ReportHelpers

  def test_reachable_has_no_trace
    io = StringIO.new
    print_result(ok_result, io)
    out = strip_ansi(io.string)
    assert_includes out, 'Google Play'
    assert_includes out, 'https://www.googleapis.com/'
    assert_includes out, 'REACHABLE'
    assert_includes out, '404'
    refute_includes out, '* Connected'
    refute_includes out, 'DNS lookup'
  end

  def test_unreachable_prints_diagnostics
    io = StringIO.new
    print_result(bad_result, io)
    out = strip_ansi(io.string)
    assert_includes out, 'NOT REACHABLE'
    assert_includes out, 'Could not resolve host (curl exit 6)'
    assert_includes out, 'curl exit 6: Could not resolve host'
    assert_includes out, '* Could not resolve host: does-not-exist.invalid'
    assert_includes out, 'DNS lookup failed:'
  end

  def test_403_shows_server_header
    r = ok_result
    r.http_code = 403
    r.trace = "< HTTP/1.1 403 Forbidden\n< Server: squid/5.0\n"
    io = StringIO.new
    print_result(r, io)
    assert_includes strip_ansi(io.string), 'squid/5.0'
  end

  def test_url_credentials_never_printed
    r = bad_result
    r.store = 'Custom'
    r.url = 'https://alice:hunter2@127.0.0.1:1/'
    io = StringIO.new
    print_result(r, io)
    refute_includes io.string, 'hunter2'
    assert_includes strip_ansi(io.string), '[Custom] https://***:***@127.0.0.1:1/'
    r.url = 'http://alice:hunter2@exa mple/'
    io = StringIO.new
    print_result(r, io)
    refute_includes io.string, 'hunter2'
    assert_includes io.string, 'DNS lookup skipped'
  end

  def test_dns_line_notes_proxy
    proxy_note = '(local DNS is not needed when a proxy is used)'
    [
      [{ 'HTTPS_PROXY' => 'http://p:3128' }, true],
      [{ 'all_proxy' => 'http://p:3128' }, true],
      [{ 'https_proxy' => 'http://p:3128', 'NO_PROXY' => 'localhost,.invalid' }, false],
      [{ 'https_proxy' => 'http://p:3128', 'no_proxy' => 'does-not-exist.invalid' }, false],
      [{ 'https_proxy' => 'http://p:3128', 'NO_PROXY' => '*' }, false],
      [{ 'https_proxy' => 'http://p:3128', 'NO_PROXY' => 'other.invalid' }, true],
      [{ 'HTTP_PROXY' => 'http://p:3128', 'http_proxy' => 'http://p:3128' }, false],
      [{}, false]
    ].each do |env, expected|
      io = StringIO.new
      print_result(bad_result, io, env)
      line = io.string.lines.find { |l| l.include?('DNS lookup') }
      assert_equal expected, line.include?(proxy_note), "#{env.inspect}: #{line}"
    end
  end

  def test_unparseable_url_does_not_crash
    r = bad_result
    r.url = 'http://exa mple/'
    io = StringIO.new
    print_result(r, io)
    assert_includes strip_ansi(io.string), 'DNS lookup skipped'
  end
end

class DnsLookupTest < Minitest::Test
  def test_localhost
    out = dns_lookup('localhost')
    assert(out.include?('127.0.0.1') || out.include?('::1'), out)
  end

  def test_failure
    assert dns_lookup('does-not-exist.invalid').start_with?('DNS lookup failed:')
  end
end

class HuaweiWarningTest < Minitest::Test
  def test_phrases
    w = huawei_warning
    assert w.start_with?('@@[warning]')
    ['nsp-appgallery-agcfs-dre.obs.eu-de.otc.t-systems.com', 'not verified',
     'depends on your account and region and is returned by an authenticated AppGallery Connect API call',
     'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'].each { |p| assert_includes w, p }
  end
end

class PrintEnvironmentTest < Minitest::Test
  def test_none_set
    io = StringIO.new
    print_environment({}, io)
    assert_includes io.string, 'Proxy/CA environment: none set'
  end

  def test_masks_credentials
    io = StringIO.new
    print_environment({ 'HTTPS_PROXY' => 'http://user:secret@proxy.local:3128', 'NO_PROXY' => 'localhost' }, io)
    assert_includes io.string, 'HTTPS_PROXY=http://***:***@proxy.local:3128'
    assert_includes io.string, 'NO_PROXY=localhost'
    refute_includes io.string, 'secret'
    refute_includes io.string, 'none set'
  end

  def test_masks_scheme_less_proxy_credentials
    io = StringIO.new
    print_environment({ 'HTTPS_PROXY' => 'bob:s3cret@127.0.0.1:9', 'all_proxy' => 'tok@127.0.0.1:9' }, io)
    assert_includes io.string, 'HTTPS_PROXY=***:***@127.0.0.1:9'
    assert_includes io.string, 'all_proxy=***:***@127.0.0.1:9'
    refute_includes io.string, 's3cret'
    refute_includes io.string, 'tok@'
  end

  def test_notes_http_proxy_only
    note = 'not used for https:// endpoints'
    io = StringIO.new
    print_environment({ 'HTTP_PROXY' => 'http://p:3128' }, io)
    assert_includes io.string, note
    io = StringIO.new
    print_environment({ 'http_proxy' => 'http://p:3128', 'HTTPS_PROXY' => 'http://p:3128' }, io)
    refute_includes io.string, note
    io = StringIO.new
    print_environment({ 'NO_PROXY' => 'localhost' }, io)
    refute_includes io.string, note
  end

  def test_prints_curl_version
    io = StringIO.new
    print_environment({}, io)
    assert_match(/curl/i, io.string)
  end
end
