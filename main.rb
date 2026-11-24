require_relative 'config'
require_relative 'checker'
require_relative 'report'

begin
  connect_timeout, max_time = read_timeouts
rescue ArgumentError => e
  puts "@@[error] #{e.message}"
  exit 1
end

print_environment

endpoints = selected_endpoints
if endpoints.empty?
  puts "There aren't any URLs given to the component, exiting."
  exit 0
end

results = endpoints.map do |endpoint|
  result = check(endpoint, connect_timeout, max_time)
  print_result(result)
  result
end

huawei = enabled?(ENV, HUAWEI_ENV)
puts huawei_warning if huawei

puts
puts summary_table(results, huawei_not_checked: huawei)

failed = results.count { |r| r.status == :unreachable }
if failed > 0
  puts "@@[error] #{failed} of #{results.size} endpoints are not reachable."
  exit 1
end
exit 0
