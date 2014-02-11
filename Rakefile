require 'rubygems'
require 'bundler'
require_relative 'lib/git-version-bump/rake-tasks'

begin
	Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
	$stderr.puts e.message
	$stderr.puts "Run `bundle install` to install missing gems"
	exit e.status_code
end

Bundler::GemHelper.install_tasks

require 'rdoc/task'

Rake::RDocTask.new do |rd|
	rd.main = "README.md"
	rd.title = 'git-version-bump'
	rd.rdoc_files.include("README.md", "lib/**/*.rb")
end
