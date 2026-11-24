require 'open3'
require 'shellwords'
require_relative 'curl_exit_codes'

Result = Struct.new(:store, :url, :status, :reason, :http_code, :connect_code, :exit_code, :time_total, :trace, keyword_init: true)

WRITE_OUT = '{"code":"%{http_code}","connect":"%{http_connect}","time_total":"%{time_total}"}'.freeze

def classify(exit_code:, http_code:, connect_code:)
  if ![0, 200].include?(connect_code)
    [:unreachable, "proxy refused CONNECT (HTTP #{connect_code})"]
  elsif http_code == 407
    [:unreachable, 'proxy authentication required (HTTP 407)']
  elsif exit_code != 0 || http_code == 0
    [:unreachable, "#{CURL_EXIT_MESSAGES[exit_code] || 'curl error'} (curl exit #{exit_code})"]
  elsif http_code == 403
    [:reachable, 'HTTP 403 (may come from a proxy, check the Server header)']
  else
    [:reachable, "HTTP #{http_code}"]
  end
end

def redact(text)
  text.to_s
      .gsub(%r{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}, '\1***:***@')
      .gsub(/(auth using \w+ with user )'[^']*'/i, "\\1'***'")
      .gsub(/((?:proxy-)?authorization:[ \t]*)[^\r\n]*/i, '\1***')
end

def server_header(trace)
  value = nil
  trace.to_s.each_line do |line|
    m = line.match(/\A<\s*server:\s*(.*?)\s*\z/i)
    value = m[1] if m
  end
  value
end

def parse_metrics(stdout)
  code = stdout.to_s[/"code":"(\d*)"/, 1].to_i
  connect = stdout.to_s[/"connect":"(\d*)"/, 1].to_i
  time = stdout.to_s[/"time_total":"([0-9.]*)"/, 1].to_f
  [code, connect, time]
end

def check(endpoint, connect_timeout, max_time)
  cmd = ['curl', '-sS', '-v', '-o', '/dev/null', '-w', WRITE_OUT,
         '--connect-timeout', connect_timeout.to_s, '--max-time', max_time.to_s, endpoint[:url]]
  puts "@@[command] #{redact(cmd.shelljoin)}"
  begin
    stdout, stderr, status = Open3.capture3(*cmd)
    exit_code = status.exitstatus || 1
  rescue SystemCallError => e
    stdout = ''
    stderr = "failed to run curl: #{e.message}"
    exit_code = 127
  end
  http_code, connect_code, time_total = parse_metrics(stdout)
  state, reason = classify(exit_code: exit_code, http_code: http_code, connect_code: connect_code)
  Result.new(store: endpoint[:store], url: endpoint[:url], status: state, reason: reason,
             http_code: http_code, connect_code: connect_code, exit_code: exit_code,
             time_total: time_total, trace: redact(stderr))
end
