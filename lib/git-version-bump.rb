require 'tempfile'
require 'digest/sha1'

module GitVersionBump
	def self.dirty_tree?
		# Are we in a dirty, dirty tree?
		system("! git diff --no-ext-diff --quiet --exit-code || ! git diff-index --cached --quiet HEAD")

		$? == 0
	end

	def self.caller_gemspec
		# First up, who called us?  Because this method gets called from other
		# methods within this file, we can't just look at
		# Gem.location_of_caller, but instead we need to parse the caller
		# stack ourselves to find which gem we're trying to version all over.
		caller_file = caller.
		                map  { |l| l.split(':')[0] }.
		                find { |l| l != __FILE__ }

		# Real paths, please.
		caller_file = File.realpath(caller_file)

		# Next we grovel through all the loaded gems to try and find the gem
		# that contains the caller's file.
		Gem.loaded_specs.values.each do |spec|
			if Dir.
				  glob(spec.lib_dirs_glob).
				  find { |d| caller_file.index(File.realpath(d)) == 0 }
				# The caller_file is in this
				# gem!  Woohoo!
				return spec
			end
		end

		nil
	end

	def self.version(gem = nil)
		@version_cache ||= {}

		return @version_cache[gem] if @version_cache[gem]

		git_ver = `git describe --dirty='.1.dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}' --match='v[0-9]*.[0-9]*.*[0-9]' 2>/dev/null`.
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

		if gem
			return Gem.loaded_specs[gem].version.to_s
		end

		# We're not in a git repo.  This means that we need to get version
		# information out of rubygems, given only the filename of who called
		# us.  This takes a little bit of effort.

		if spec = caller_gemspec
			return spec.version.to_s
		else
			# If we got here, something went *badly* wrong -- presumably, we
			# weren't called from within a loaded gem, and so we've got *no*
			# idea what's going on.  Time to bail!
			raise RuntimeError,
					  "GVB.version(#{gem.inspect}) failed.  Is git installed?"
		end
	end

	VERSION = version('git-version-bump')

	def self.major_version(gem = nil)
		ver = version(gem)
		v   = ver.split('.')[0]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	MAJOR_VERSION = major_version('git-version-bump')

	def self.minor_version(gem = nil)
		ver = version(gem)
		v   = ver.split('.')[1]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	MINOR_VERSION = minor_version('git-version-bump')

	def self.patch_version(gem = nil)
		ver = version(gem)
		v   = ver.split('.')[2]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	PATCH_VERSION = patch_version('git-version-bump')

	def self.internal_revision(gem = nil)
		version(gem).split('.', 4)[3].to_s
	end

	INTERNAL_REVISION = internal_revision('git-version-bump')

	def self.date(gem = nil)
		# Are we in a git tree?
		system("git status >/dev/null 2>&1")
		if $? == 0
			# Yes, we're in git.

			if dirty_tree?
				return Time.now.strftime("%F")
			else
				# Clean tree.  Date of last commit is needed.
				return `git show --format=format:%ad --date=short | head -n 1`.strip
			end
		else
			# Not in git; time to hit the gemspecs
			if gem
				return Gem.loaded_specs[gem].date.strftime("%F")
			end

			if spec = caller_gemspec
				return spec.date.strftime("%F")
			end

			raise RuntimeError,
				  "GVB.date(#{gem.inspect}) called from mysterious, non-gem location."
		end
	end

	DATE = date('git-version-bump')

	def self.tag_version(v, release_notes = false)
		if dirty_tree?
			puts "You have uncommitted files.  Refusing to tag a dirty tree."
		else
			if release_notes
				# We need to find the tag before this one, so we can list all the commits
				# between the two.  This is not a trivial operation.
				prev_tag = `git describe --always`.strip.gsub(/-\d+-g[0-9a-f]+$/, '')

				log_file = Tempfile.new('gvb')

				log_file.puts <<-EOF.gsub(/^\t\t\t\t\t/, '')



					# Write your release notes above.  The first line should be the release name.
					# To help you remember what's in here, the commits since your last release
					# are listed below. This will become v#{v}
					#
				EOF

				log_file.close
				system("git log --format='# %h  %s' #{prev_tag}..HEAD >>#{log_file.path}")

				pre_hash = Digest::SHA1.hexdigest(File.read(log_file.path))
				system("git config -e -f #{log_file.path}")
				if Digest::SHA1.hexdigest(File.read(log_file.path)) == pre_hash
					puts "Release notes not edited; aborting"
					log_file.unlink
					return
				end

				puts "Tagging version #{v}..."
				system("git tag -a -F #{log_file.path} v#{v}")
				log_file.unlink
			else
				# Crikey this is a lot simpler
				system("git tag -a -m 'Version v#{v}' v#{v}")
			end

			system("git push >/dev/null 2>&1")
			system("git push --tags >/dev/null 2>&1")
		end
	end
end

GVB = GitVersionBump
