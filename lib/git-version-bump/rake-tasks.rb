require_relative '../git-version-bump'

namespace :version do
	namespace :bump do
   	desc "bump major version (x.y.z -> x+1.0.0)"
   	task :major do
			GVB.tag_version "#{GVB.major_version + 1}.0.0"
		end
		
   	desc "bump minor version (x.y.z -> x.y+1.0)"
   	task :minor do
			GVB.tag_version "#{GVB.major_version}.#{GVB.minor_version+1}.0"
		end
		
    	desc "bump patch version (x.y.z -> x.y.z+1)"
   	task :minor do
			GVB.tag_version "#{GVB.major_version}.#{GVB.minor_version}.#{GVB.patch_version+1}"
		end
	end
end
