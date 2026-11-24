require 'minitest/autorun'
require 'yaml'
require_relative '../config'

class ComponentYamlTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SHARED = %w[AC_CHECK_CONNECTION_TIMEOUT AC_CHECK_CONNECTION_MAX_TIMEOUT AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS].freeze
  ENTERPRISE = 'AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM'.freeze
  # "Android Publisher" is the name of the Google Play API, not a platform reference.
  PLATFORM_WORD = /\biOS\b|\bAndroid\b(?! Publisher)/

  def component
    @component ||= YAML.load_file(File.join(ROOT, 'component.yaml'))
  end

  def test_single_yaml_layout
    assert_equal ['component.yaml'], Dir.children(ROOT).grep(/\Acomponent.*\.ya?ml\z/)
  end

  def test_input_keys_match_endpoints_then_shared_keys
    expected = ENDPOINTS.map { |e| e[:env] } + SHARED
    assert_equal expected, component['inputs'].map { |i| i['key'] }
  end

  def test_boolean_defaults
    ENDPOINTS.each do |e|
      input = component['inputs'].find { |i| i['key'] == e[:env] }
      refute_nil input, e[:env]
      assert_equal(e[:env] == ENTERPRISE ? 'false' : 'true', input['defaultValue'], e[:env])
      assert_equal 'select', input['editorType'], e[:env]
      assert_equal 'true,false', input['options'], e[:env]
    end
  end

  def test_shared_input_defaults
    defaults = component['inputs'].last(3).map { |i| i['defaultValue'] }
    assert_equal ['8', '20', '$AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'], defaults
  end

  def test_top_level_fields
    assert_equal 'Common', component['platform']
    assert_equal 'Publish', component['purpose']
    assert_equal 'ruby', component['processFilename']
    assert_equal '%AC_STEP_TEMP%/main.rb', component['processArguments']
    refute component.key?('runOn')
    refute component.key?('marketPlace')
  end

  def test_files_match_repo_ruby_files
    top_level = Dir.children(ROOT).select { |f| f.end_with?('.rb') }.sort
    files = component['files']
    files.each { |f| assert File.exist?(File.join(ROOT, f)), "missing #{f}" }
    assert_equal top_level, files.sort
  end

  def test_texts_are_platform_neutral
    component['inputs'].each do |i|
      refute_match PLATFORM_WORD, i['title'].to_s, i['key']
      refute_match PLATFORM_WORD, i['description'].to_s, i['key']
    end
    refute_match PLATFORM_WORD, component['description'].to_s
  end
end
