require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class MainTest < Minitest::Test
  MAIN = File.expand_path('../main.rb', __dir__)

  def run_main(env)
    clean = ENV.to_h.reject { |k, _| k.start_with?('AC_CHECK') }
    Open3.capture3(clean.merge(env), RbConfig.ruby, MAIN)
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
