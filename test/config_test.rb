require 'minitest/autorun'
require_relative '../config'

class ConfigTest < Minitest::Test
  APP_STORE_KEYS = %w[
    AC_CHECK_NETWORK_API_APPSTORECONNECT_APPLE_COM
    AC_CHECK_NETWORK_APPSTORECONNECT_APPLE_COM
    AC_CHECK_NETWORK_CONTENTDELIVERY_ITUNES_APPLE_COM
    AC_CHECK_NETWORK_NORTHAMERICA_1_OBJECT_STORAGE_APPLE_COM
  ].freeze

  def test_selects_only_true_inputs
    env = {}
    APP_STORE_KEYS.each { |k| env[k] = 'true' }
    env['AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM'] = nil
    selected = selected_endpoints(env)
    assert_equal 4, selected.size
    assert_equal ['App Store'], selected.map { |e| e[:store] }.uniq
    assert_equal [
      'https://api.appstoreconnect.apple.com/',
      'https://appstoreconnect.apple.com/',
      'https://contentdelivery.itunes.apple.com/',
      'https://northamerica-1.object-storage.apple.com/'
    ], selected.map { |e| e[:url] }
  end

  def test_true_is_case_and_space_insensitive
    env = { 'AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM' => ' TRUE ' }
    assert_equal [{ store: 'Google Play', url: 'https://www.googleapis.com/' }], selected_endpoints(env)
  end

  def test_parse_extra_urls
    assert_equal ['https://a.example.com', 'https://b.example.com'],
                 parse_extra_urls(' a.example.com, https://b.example.com ,,https://b.example.com,')
  end

  def test_parse_extra_urls_ignores_unexpanded_variables
    assert_equal ['https://a.example.com'],
                 parse_extra_urls('$AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS, a.example.com, $OTHER')
    assert_equal [], parse_extra_urls('$AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS')
  end

  def test_extra_duplicate_of_catalog_dropped
    env = {
      'AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM' => 'true',
      'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => 'https://www.googleapis.com/'
    }
    selected = selected_endpoints(env)
    assert_equal 1, selected.size
    assert_equal 'Google Play', selected.first[:store]
  end

  def test_bare_host_extra_url_is_duplicate_of_catalog_url
    env = {
      'AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM' => 'true',
      'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => 'https://www.googleapis.com, www.googleapis.com'
    }
    assert_equal [{ store: 'Google Play', url: 'https://www.googleapis.com/' }], selected_endpoints(env)
    assert_equal ['https://a.example.com'], parse_extra_urls('a.example.com, https://a.example.com/')
    assert_equal ['https://a.example.com/x', 'https://a.example.com/x/'],
                 parse_extra_urls('a.example.com/x, a.example.com/x/')
  end

  def test_extra_urls_are_custom
    env = { 'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS' => 'x.example.com' }
    assert_equal [{ store: 'Custom', url: 'https://x.example.com' }], selected_endpoints(env)
  end

  def test_timeout_fallback_notes
    notes = []
    assert_equal [8, 20], read_timeouts({}, notes)
    assert_equal [], notes

    notes = []
    assert_equal [8, 30], read_timeouts({ 'AC_CHECK_CONNECTION_TIMEOUT' => 'abc', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '30' }, notes)
    assert_equal 1, notes.size
    assert notes.first.start_with?('@@[warning]')
    assert_includes notes.first, 'AC_CHECK_CONNECTION_TIMEOUT'
    assert_includes notes.first, '"abc"'
    assert_includes notes.first, '8'

    notes = []
    assert_equal [8, 20], read_timeouts({ 'AC_CHECK_CONNECTION_TIMEOUT' => '5', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '0' }, notes)
    assert_equal 1, notes.size
    assert_includes notes.first, 'greater than 0'
    assert_includes notes.first, '8 and 20'
  end

  def test_timeouts
    assert_equal [8, 20], read_timeouts({})
    assert_equal [8, 20], read_timeouts('AC_CHECK_CONNECTION_TIMEOUT' => 'abc')
    assert_equal [8, 20], read_timeouts('AC_CHECK_CONNECTION_TIMEOUT' => '0')
    assert_equal [10, 30], read_timeouts('AC_CHECK_CONNECTION_TIMEOUT' => '10', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '30')
    assert_raises(ArgumentError) do
      read_timeouts('AC_CHECK_CONNECTION_TIMEOUT' => '5', 'AC_CHECK_CONNECTION_MAX_TIMEOUT' => '3')
    end
  end
end
