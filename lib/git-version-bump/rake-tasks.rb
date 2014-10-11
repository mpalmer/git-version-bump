require 'git-version-bump'

namespace :version do
	namespace :bump do
   	desc "bump major version (x.y.z -> x+1.0.0)"
   	task :major do
			GVB.tag_version "#{GVB.major_version + 1}.0.0"

			puts "Version is now #{GVB.version}"
		end
		
   	desc "bump minor version (x.y.z -> x.y+1.0)"
   	task :minor do
			GVB.tag_version "#{GVB.major_version}.#{GVB.minor_version+1}.0"

			puts "Version is now #{GVB.version}"
		end
		
    	desc "bump patch version (x.y.z -> x.y.z+1)"
		task :patch do
			GVB.tag_version "#{GVB.major_version}.#{GVB.minor_version}.#{GVB.patch_version+1}"

			puts "Version is now #{GVB.version}"
		end

		desc "Print current version"
		task :show do
			puts GVB.version
		end
	end
end

namespace :v do
	namespace :b do
		task :major => "version:bump:major"
		task :maj   => "version:bump:major"
		
		task :minor => "version:bump:minor"
		task :min   => "version:bump:minor"

		task :patch => "version:bump:patch"
		task :pat   => "version:bump:patch"
		task :p     => "version:bump:patch"

		task :show  => "version:bump:show"
		task :sh    => "version:bump:show"
		task :s     => "version:bump:show"
	end
end
