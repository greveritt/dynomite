require 'logger'

module Dynomite
  module Core
    # Ensures trailing slash
    # Useful for appending a './' in front of a path or leaving it alone.
    # Returns: '/path/with/trailing/slash/' or './'
    @@app_root = nil
    def app_root
      return @@app_root if @@app_root
      @@app_root = ENV['APP_ROOT'] || ENV['JETS_ROOT'] || ENV['RAILS_ROOT']
      @@app_root = '.' if @@app_root.nil? || @app_root == ''
      @@app_root = "#{@@app_root}/" unless @@app_root.ends_with?('/')
      @@app_root
    end

    @@config = nil
    def config
      @@config ||= Config.new
    end
  end
end
