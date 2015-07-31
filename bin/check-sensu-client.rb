#! /usr/bin/env ruby
#
# sensu-health-check
#
# DESCRIPTION:
#   Finds a given tag set from EC2 and ensures sensu clients exist
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk'
require 'net/http'
require 'json'
require 'sensu-plugins-sensu-check/filter'

class EC2Filter < Sensu::Plugin::Check::CLI
  include Filter
  option :aws_access_key,
         short: '-a AWS_ACCESS_KEY',
         long: '--aws-access-key AWS_ACCESS_KEY',
         description: "AWS Access Key. Either set ENV['AWS_ACCESS_KEY_ID'] or provide it as an option"

  option :aws_secret_access_key,
         short: '-k AWS_SECRET_ACCESS_KEY',
         long: '--aws-secret-access-key AWS_SECRET_ACCESS_KEY',
         description: "AWS Secret Access Key. Either set ENV['AWS_SECRET_ACCESS_KEY'] or provide it as an option"

  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (such as us-east-1).',
         default: 'us-east-1'

  option :sense_host,
         short: '-h SENSU_HOST',
         long: '--host SENSU_HOST',
         description: 'Sensu host to query',
         default: 'sensu'

  option :sensu_port,
         short: '-p SENSU_PORT',
         long: '--port SENSU_PORT',
         description: 'Sensu API port',
         proc: proc(&:to_i),
         default: 4567

  option :warn,
         short: '-w WARN',
         description: 'Warn if instance has been up longer (Minutes)',
         proc: proc(&:to_i)

  option :critical,
         short: '-c CRITICAL',
         description: 'Critical if instance has been up longer (Minutes)',
         proc: proc(&:to_i)

  option :min,
         short: '-m MIN_TIME',
         description: 'Minimum Time an instance must be running (Minutes)',
         proc: proc(&:to_i),
         default: 5

  option :filter,
         short: '-f FILTER',
         description: 'Filter to use to find ec2 instances',
         default: '{}'


  def aws_config
    hash = {}
    hash.update access_key_id: config[:access_key_id], secret_access_key: config[:secret_access_key] if config[:access_key_id] && config[:secret_access_key]
    hash.update region: config[:aws_region]
    hash
  end

  def run


      client = Aws::EC2::Client.new aws_config

      parsed_filter = parse(config[:filter])

      unless parsed_filter.empty?
        filter = {filters: Filter.parse(config[:filter])}
      else
        filter ={}
      end

      data = client.describe_instances(filter)

      currentTime = Time.now.utc
      aws_instances = Set.new
      data.reservations.each do |r|
        r.instances.each do |i|
          aws_instances << {
            id:i[:instance_id],
            up_time: (currentTime - i[:launch_time])/60
          }
        end
      end

      sensu_clients = client_check

      missing = Set.new

      aws_instances.each do |i|
        if sensu_clients.include?(i[:id]) == false
          if i[:up_time] > config[:min]
            missing << i
            output "Missing instance #{i[:id]}. Uptime: #{i[:up_time]} Minutes"
          end
        end
      end

      warn_flag = false;
      crit_flag = false;

      missing.each do |m|
        if(config[:critical].nil? == false) &&( m[:up_time] > config[:critical])
          crit_flag = true;
        elsif (config[:warn].nil? == false) && ( m[:up_time] > config[:warn])
          warn_flag = true;
        end
      end

      if crit_flag
        critical
      elsif warn_flag
        warning
      end
      ok
  end

  def client_check
    uri = URI("http://#{config[:sense_host]}:#{config[:sensu_port]}/clients")
    response = JSON.parse(Net::HTTP.get(uri))

    clients = Set.new
    response.each do |client|
      clients << client['name']
    end

    clients
  end
end
