# Minimal CONNECT proxy for integration tests.
# Usage: ruby test/blocking_proxy.rb PORT BLOCKED_HOST[,HOST...]
require 'socket'

port = Integer(ARGV[0])
blocked = ARGV[1].to_s.split(',').map { |h| h.strip.downcase }.reject(&:empty?)

def relay(a, b)
  loop do
    ready, = IO.select([a, b])
    ready.each do |io|
      data = io.readpartial(16_384)
      (io == a ? b : a).write(data)
    end
  end
rescue EOFError, SystemCallError, IOError
  nil
end

def handle(client, blocked)
  request = client.gets
  return unless request
  while (line = client.gets) && line != "\r\n"
    # headers (including Proxy-Authorization) are ignored
  end
  method, target, = request.split(' ')
  host, port = target.to_s.split(':')
  if method != 'CONNECT' || host.nil? || blocked.include?(host.downcase)
    client.write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    return
  end
  upstream = begin
    TCPSocket.new(host, Integer(port || 443))
  rescue StandardError
    client.write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    return
  end
  begin
    client.write("HTTP/1.1 200 Connection established\r\n\r\n")
    relay(client, upstream)
  ensure
    upstream.close rescue nil
  end
end

server = TCPServer.new('127.0.0.1', port)
puts "blocking proxy listening on 127.0.0.1:#{port}, blocking: #{blocked.join(',')}"
$stdout.flush
loop do
  client = server.accept
  Thread.new(client) do |c|
    begin
      handle(c, blocked)
    rescue StandardError
      nil
    ensure
      c.close rescue nil
    end
  end
end
