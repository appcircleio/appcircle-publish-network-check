require 'minitest/autorun'
require 'yaml'
require_relative '../config'

class ComponentYamlTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SHARED = %w[AC_CHECK_CONNECTION_TIMEOUT AC_CHECK_CONNECTION_MAX_TIMEOUT AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS].freeze
  MIRRORS = {
    'component-ios.yaml' => { platform: 'iOS', stores: ['App Store'] },
    'component-android.yaml' => { platform: 'Android', stores: ['Google Play', 'Huawei AppGallery'] }
  }.freeze
  ENTERPRISE = 'AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM'.freeze

  def load_mirror(name)
    YAML.load_file(File.join(ROOT, name))
  end

  def test_input_keys_match_endpoints_then_shared_keys
    MIRRORS.each do |name, meta|
      expected = ENDPOINTS.select { |e| meta[:stores].include?(e[:store]) }.map { |e| e[:env] } + SHARED
      assert_equal expected, load_mirror(name)['inputs'].map { |i| i['key'] }, name
    end
  end

  def test_boolean_defaults
    MIRRORS.each_key do |name|
      ENDPOINTS.each do |e|
        input = load_mirror(name)['inputs'].find { |i| i['key'] == e[:env] }
        next unless input
        assert_equal(e[:env] == ENTERPRISE ? 'false' : 'true', input['defaultValue'], "#{name} #{e[:env]}")
        assert_equal 'select', input['editorType']
        assert_equal 'true,false', input['options']
      end
    end
  end

  def test_shared_input_defaults
    MIRRORS.each_key do |name|
      defaults = load_mirror(name)['inputs'].last(3).map { |i| i['defaultValue'] }
      assert_equal ['8', '20', '$AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'], defaults, name
    end
  end

  def test_top_level_fields
    MIRRORS.each do |name, meta|
      y = load_mirror(name)
      assert_equal meta[:platform], y['platform'], name
      assert_equal 'Publish', y['purpose'], name
      assert_equal 'ruby', y['processFilename'], name
      assert_equal '%AC_STEP_TEMP%/main.rb', y['processArguments'], name
      refute y.key?('runOn'), name
      refute y.key?('marketPlace'), name
    end
  end

  def test_files_match_repo_ruby_files
    top_level = Dir.children(ROOT).select { |f| f.end_with?('.rb') }.sort
    MIRRORS.each_key do |name|
      files = load_mirror(name)['files']
      files.each { |f| assert File.exist?(File.join(ROOT, f)), "#{name}: missing #{f}" }
      assert_equal top_level, files.sort, name
    end
  end
end
