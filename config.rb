DEFAULT_CONNECT_TIMEOUT = 8
DEFAULT_MAX_TIMEOUT = 20
EXTRA_URLS_ENV = 'AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'.freeze
HUAWEI_ENV = 'AC_CHECK_NETWORK_CONNECT_API_CLOUD_HUAWEI_COM'.freeze

ENDPOINTS = [
  { store: 'Google Play', env: 'AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM', url: 'https://www.googleapis.com/' },
  { store: 'Google Play', env: 'AC_CHECK_NETWORK_ANDROIDPUBLISHER_GOOGLEAPIS_COM', url: 'https://androidpublisher.googleapis.com/' },
  { store: 'Huawei AppGallery', env: HUAWEI_ENV, url: 'https://connect-api.cloud.huawei.com/' },
  { store: 'App Store', env: 'AC_CHECK_NETWORK_API_APPSTORECONNECT_APPLE_COM', url: 'https://api.appstoreconnect.apple.com/' },
  { store: 'App Store', env: 'AC_CHECK_NETWORK_APPSTORECONNECT_APPLE_COM', url: 'https://appstoreconnect.apple.com/' },
  { store: 'App Store', env: 'AC_CHECK_NETWORK_CONTENTDELIVERY_ITUNES_APPLE_COM', url: 'https://contentdelivery.itunes.apple.com/' },
  { store: 'App Store', env: 'AC_CHECK_NETWORK_NORTHAMERICA_1_OBJECT_STORAGE_APPLE_COM', url: 'https://northamerica-1.object-storage.apple.com/' },
  { store: 'App Store', env: 'AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM', url: 'https://api.enterprise.developer.apple.com/' }
].map(&:freeze).freeze

def enabled?(env, key)
  env[key].to_s.strip.downcase == 'true'
end

def parse_extra_urls(value)
  value.to_s.split(',').map(&:strip).reject(&:empty?).map do |u|
    u =~ %r{\A[a-zA-Z][a-zA-Z0-9+.-]*://} ? u : "https://#{u}"
  end.uniq
end

def selected_endpoints(env = ENV)
  selected = ENDPOINTS.select { |e| enabled?(env, e[:env]) }.map { |e| { store: e[:store], url: e[:url] } }
  parse_extra_urls(env[EXTRA_URLS_ENV]).each { |u| selected << { store: 'Custom', url: u } }
  selected.uniq { |e| e[:url] }
end

def read_timeouts(env = ENV)
  connect = Integer(env['AC_CHECK_CONNECTION_TIMEOUT'].to_s.strip) rescue DEFAULT_CONNECT_TIMEOUT
  max = Integer(env['AC_CHECK_CONNECTION_MAX_TIMEOUT'].to_s.strip) rescue DEFAULT_MAX_TIMEOUT
  if connect <= 0 || max <= 0
    connect = DEFAULT_CONNECT_TIMEOUT
    max = DEFAULT_MAX_TIMEOUT
  end
  raise ArgumentError, 'Max Timeout Value must be greater than Connect Timeout Value' if max < connect
  [connect, max]
end
