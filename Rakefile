require 'rubygems'
require 'bundler'

Bundler::GemHelper.install_tasks

require 'rdoc/task'

Rake::RDocTask.new do |rd|
	rd.main = "README.md"
	rd.title = 'git-version-bump'
	rd.rdoc_files.include("README.md", "lib/**/*.rb")
end

task :release do
	sh "git push --follow-tags"
	sh "git release"
end
