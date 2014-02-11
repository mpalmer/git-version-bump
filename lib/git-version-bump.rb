module GitVersionBump
	def self.version
		git_ver = `git describe --dirty --match='v[0-9]*.[0-9]*.*[0-9]' 2>/dev/null`.
		            strip.
		            gsub(/^v/, '').
		            gsub('-', '.')
		
		# If git returned success, then it gave us a described version.
		# Success!
		return git_ver if $? == 0

		# git failed us; we're either not in a git repo or else we've never
		# tagged anything before.
		
		# Are we in a git repo with no tags?  If so, dump out our
		# super-special version and be done with it.
		system("git status >/dev/null 2>&1")
		return "0.0.0.1.ENOTAG" if $? == 0

		# We're not in a git repo.  This means that we need to get version
		# information out of rubygems, given only the filename of who called
		# us.  This takes a little bit of effort.

		if spec = GVB.caller_gemspec
			return spec.version.to_s
		else
			# If we got here, something went *badly* wrong -- presumably, we
			# weren't called from within a loaded gem, and so we've got *no*
			# idea what's going on.  Time to bail!
			raise RuntimeError,
					  "GVB.version called from mysterious, non-gem location."
		end
	end
	
	def self.major_version
		ver = GVB.version
		v   = ver.split('.')[0]
		
		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end
		
		return v.to_i
	end
	
	def self.minor_version
		ver = GVB.version
		v   = ver.split('.')[1]
		
		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end
		
		return v.to_i
	end
	
	def self.patch_version
		ver = GVB.version
		v   = ver.split('.')[2]
		
		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end
		
		return v.to_i
	end
	
	def self.internal_revision
		GVB.version.split('.', 4)[3].to_s
	end
	
	def self.date
		# Are we in a git tree?
		system("git status >/dev/null 2>&1")
		if $? == 0
			# Yes, we're in git.
			
			if GVB.dirty_tree?
				return Time.now.strftime("%F")
			else
				# Clean tree.  Date of last commit is needed.
				return `git show --format=format:%ad --date=short | head -n 1`.strip
			end
		else
			# Not in git; time to hit the gemspecs
			if spec = GVB.caller_gemspec
				return spec.version.to_s
			else
				raise RuntimeError,
					  "GVB.date called from mysterious, non-gem location."
			end
		end
	end
	
	def self.tag_version(v)
		if GVB.dirty_tree?
			puts "You have uncommitted files.  Refusing to tag a dirty tree."
		else
			puts "Tagging version #{v}..."
			system("git tag -a -m 'Version v#{v}' v#{v}")
		end
	end
	
	def self.caller_gemspec
		# First up, who called us?  Because this method gets called from other
		# methods within this file, we can't just look at Gem.location_of_caller,
		# but instead we need to parse the whole caller stack ourselves.
		caller_file = caller.
		                map  { |l| l.split(':')[0] }.
		                find { |l| l != __FILE__ }
		
		# Next we grovel through all the loaded gems to try and find the gem
		# that contains the caller's file.
		Gem.loaded_specs.values.each do |spec|
			if Dir.
				  glob(spec.lib_dirs_glob).
				  find { |d| caller_file.index(d) == 0 }
				# The caller_file is in this
				# gem!  Woohoo!
				return spec
			end
		end

		nil
	end

	def self.dirty_tree?
		# Are we in a dirty, dirty tree?
		system("! git diff --no-ext-diff --quiet --exit-code || ! git diff-index --cached --quiet HEAD")

		$? == 0
	end
end

GVB = GitVersionBump
