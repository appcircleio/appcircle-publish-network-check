require 'open3'
require 'socket'
require 'uri'
require_relative 'config'
require_relative 'checker'
require_relative 'curl_exit_codes'

ENV_VARS_TO_SHOW = %w[
  HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
  SSL_CERT_FILE CURL_CA_BUNDLE
].freeze

GREEN = "\e[32m".freeze
RED = "\e[31m".freeze
RESET = "\e[0m".freeze

HUAWEI_ROW = ['Huawei upload host (*.obs.*.otc.t-systems.com)', 'NOT CHECKED',
              'dynamic, add it via AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS'].freeze

def print_environment(env = ENV, io = $stdout)
  begin
    out, _err, _status = Open3.capture3('curl', '-V')
    io.puts out.lines.first.to_s.strip
  rescue SystemCallError => e
    io.puts "@@[warning] Could not run curl -V: #{e.message}"
  end
  set_vars = ENV_VARS_TO_SHOW.select { |name| !env[name].to_s.empty? }
  if set_vars.empty?
    io.puts 'Proxy/CA environment: none set'
  else
    io.puts 'Proxy/CA environment:'
    set_vars.each { |name| io.puts "  #{name}=#{redact(env[name])}" }
  end
end

def dns_lookup(host)
  ips = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
  "DNS lookup #{host}: #{ips.join(', ')}"
rescue StandardError => e
  "DNS lookup failed: #{e.message}"
end

def print_result(result, io = $stdout)
  reachable = result.status == :reachable
  word = reachable ? "#{GREEN}REACHABLE#{RESET}" : "#{RED}NOT REACHABLE#{RESET}"
  io.puts "[#{result.store}] #{result.url}"
  io.puts "  Result: #{word}"
  io.puts "  HTTP status: #{result.http_code}"
  io.puts "  Time: #{format('%.3f', result.time_total.to_f)}s"
  if result.http_code == 403
    server = server_header(result.trace)
    io.puts "  Server header: #{server}" if server
  end
  return if reachable

  io.puts "  Reason: #{result.reason}"
  io.puts "  curl exit #{result.exit_code}: #{CURL_EXIT_MESSAGES[result.exit_code] || 'Unknown exit code'}"
  io.puts '  curl -v trace:'
  io.puts result.trace
  host = begin
    URI.parse(result.url).host
  rescue URI::InvalidURIError
    nil
  end
  io.puts host ? "  #{dns_lookup(host)}" : "  DNS lookup skipped: could not parse host from #{result.url}"
end

def huawei_warning
  '@@[warning] The Huawei AppGallery upload host (for example ' \
  'nsp-appgallery-agcfs-dre.obs.eu-de.otc.t-systems.com) is not verified by this component. ' \
  'It depends on your account and region and is returned by an authenticated AppGallery Connect API call. ' \
  "If you know it, add it to #{EXTRA_URLS_ENV}."
end

def summary_table(results, huawei_not_checked:)
  rows = results.map do |r|
    [r.url, r.status == :reachable ? 'REACHABLE' : 'NOT REACHABLE', r.reason.to_s]
  end
  rows << HUAWEI_ROW if huawei_not_checked
  header = %w[Endpoint Result Reason]
  widths = (0..1).map { |i| ([header] + rows).map { |row| row[i].length }.max }
  reason_width = ([header] + rows).map { |row| row[2].length }.max
  line = lambda do |row|
    [row[0].ljust(widths[0]), row[1].ljust(widths[1]), row[2]].join(' | ').rstrip
  end
  sep = [('-' * widths[0]), ('-' * widths[1]), ('-' * reason_width)].join('-+-')
  ([line.call(header), sep] + rows.map { |row| line.call(row) }).join("\n")
end
