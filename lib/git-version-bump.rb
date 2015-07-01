require 'tempfile'
require 'digest/sha1'
require 'pathname'

module GitVersionBump
	class VersionUnobtainable < StandardError; end

	def self.version(use_local_git=false)
		if use_local_git
			unless git_available?
				raise RuntimeError,
				      "GVB.version(use_local_git=true) called, but git isn't installed"
			end

			sq_git_dir = "'#{Dir.pwd.gsub("'", "'\\''")}'"
		else
			# Shell Quoted, for your convenience
			sq_git_dir = "'" + (File.dirname(caller_file) rescue nil || Dir.pwd).gsub("'", "'\\''") + "'"
		end

		git_ver = `git -C #{sq_git_dir} describe --dirty='.1.dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}' --match='v[0-9]*.[0-9]*.*[0-9]' 2>/dev/null`.
		            strip.
		            gsub(/^v/, '').
		            gsub('-', '.')

		# If git returned success, then it gave us a described version.
		# Success!
		return git_ver if $? == 0

		# git failed us; we're either not in a git repo or else we've never
		# tagged anything before.

		# Are we in a git repo with no tags?  If so, dump out our
		# super-special version and be done with it, otherwise try to use the
		# gem version.
		system("git -C #{sq_git_dir} status >/dev/null 2>&1")
		 "0.0.0.1.ENOTAG" if $? == 0 ? "0.0.0.1.ENOTAG" : gem_version(use_local_git)
	end

	def self.major_version(use_local_git=false)
		ver = version(use_local_git)
		v   = ver.split('.')[0]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.minor_version(use_local_git=false)
		ver = version(use_local_git)
		v   = ver.split('.')[1]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.patch_version(use_local_git=false)
		ver = version(use_local_git)
		v   = ver.split('.')[2]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.internal_revision(use_local_git=false)
		version(use_local_git).split('.', 4)[3].to_s
	end

	def self.date(use_local_git=false)
		if use_local_git
			unless git_available?
				raise RuntimeError,
				      "GVB.date(use_local_git=true), but git is not installed"
			end

			sq_git_dir = "'#{Dir.pwd.gsub("'", "'\\''")}'"
		else
			# Shell Quoted, for your convenience
			sq_git_dir = "'" + (File.dirname(caller_file) rescue nil || Dir.pwd).gsub("'", "'\\''") + "'"
		end

		# Are we in a git tree?
		system("git -C #{sq_git_dir} status >/dev/null 2>&1")
		if $? == 0
			# Yes, we're in git.

			if dirty_tree?
				return Time.now.strftime("%F")
			else
				# Clean tree.  Date of last commit is needed.
				return `git -C #{sq_git_dir} show --format=format:%cd --date=short | head -n 1`.strip
			end
		else
			if use_local_git
				raise RuntimeError,
				      "GVB.date(use_local_git=true) called from non-git location"
			end

			# Not in git; time to hit the gemspecs
			if spec = caller_gemspec
				return spec.date.strftime("%F")
			end

			raise RuntimeError,
			      "GVB.date called from mysterious, non-gem location."
		end
	end

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

	# Calculate a version number based on the date of the most recent git commit.
	#
	# Return a version format string of the form `"0.YYYYMMDD.N"`, where
	# `YYYYMMDD` is the date of the "top-most" commit in the tree, and `N` is
	# the number of other commits also made on that date.
	#
	# This version format is not recommented for general use.  It has benefit
	# only in situations where the principles of Semantic Versioning have no
	# real meaning, such as packages where there is little or no concept of
	# "backwards compatibility" (eg packages which only contain images and
	# other assets), or where the package can, for reasons outside that of
	# the package itself, never break backwards compatibility (definitions of
	# binary-packed structures shared amongst multiple systems).
	#
	# The format of this commit-date-based version format allows for a strictly
	# monotonically-increasing version number, aligned with the progression of the
	# underlying git commit log.
	#
	# One limitation of the format is that it doesn't deal with the issue of
	# package builds made from multiple divergent trees.  Unlike
	# `git-describe`-based output, there is no "commit hash" identity
	# included in the version string.  This is because of (ludicrous)
	# limitations of the Rubygems format definition -- the moment there's a
	# letter in the version number, the package is considered a "pre-release"
	# version.  Since hashes are hex, we're boned.  Sorry about that.  Don't
	# make builds off a branch, basically.
	#
	def self.commit_date_version(use_local_git = false)
		if use_local_git
			unless git_available?
				raise RuntimeError,
				      "GVB.commit_date_version(use_local_git=true) called, but git isn't installed"
			end

			sq_git_dir = "'#{Dir.pwd.gsub("'", "'\\''")}'"
		else
			# Shell Quoted, for your convenience
			sq_git_dir = "'" + (File.dirname(caller_file) rescue nil || Dir.pwd).gsub("'", "'\\''") + "'"
		end

		commit_dates = `git -C #{sq_git_dir} log --format=%at`.
		               split("\n").
		               map { |l| Time.at(Integer(l)).strftime("%Y%m%d") }

		if $? == 0
			# We got a log; calculate our version number and we're done.
			version_date = commit_dates.first
			commit_count = commit_dates.select { |d| d == version_date }.length - 1
			dirty_suffix = if dirty_tree?
				".dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}"
			else
				""
			end

			return "0.#{version_date}.#{commit_count}#{dirty_suffix}"
		end

		# git failed us; either we're not in a git repo or else it's a git
		# repo that's not got any commits.

		# Are we in a git repo with no tags?  If so, dump out our
		# super-special version and be done with it.
		system("git -C #{sq_git_dir} status >/dev/null 2>&1")
		$? == 0 ? "0.0.0.1.ENOCOMMITS" : gem_version(use_local_git)
	end

	private

	def self.git_available?
		system("git --version >/dev/null 2>&1")

		$? == 0
	end

	def self.dirty_tree?
		# Are we in a dirty, dirty tree?
		system("! git diff --no-ext-diff --quiet --exit-code 2>/dev/null || ! git diff-index --cached --quiet HEAD 2>/dev/null")

		$? == 0
	end

	def self.caller_file
		# Who called us?  Because this method gets called from other methods
		# within this file, we can't just look at Gem.location_of_caller, but
		# instead we need to parse the caller stack ourselves to find which
		# gem we're trying to version all over.
		Pathname(
		  caller.
		  map  { |l| l.split(':')[0] }.
		  find { |l| l != __FILE__ }
		).realpath.to_s rescue nil
	end

	def self.caller_gemspec
		cf = caller_file or return nil

		# Grovel through all the loaded gems to try and find the gem
		# that contains the caller's file.
		Gem.loaded_specs.values.each do |spec|
			search_dirs = spec.require_paths.map { |d| "#{spec.full_gem_path}/#{d}" } +
			              [File.join(spec.gem_dir, spec.bindir)]
			search_dirs.map! do |d|
				begin
					Pathname(d).realpath.to_s
				rescue Errno::ENOENT
					nil
				end
			end.compact!

			if search_dirs.find { |d| cf.index(d) == 0 }
				return spec
			end
		end

		raise VersionUnobtainable,
		      "Unable to find gemspec for caller file #{cf}"
	end

	def self.gem_version(use_local_git = false)
		if use_local_git
			raise VersionUnobtainable,
			      "Unable to determine version from local git repo.  This should never happen."
		end

		if spec = caller_gemspec
			return spec.version.to_s
		else
			# If we got here, something went *badly* wrong -- presumably, we
			# weren't called from within a loaded gem, and so we've got *no*
			# idea what's going on.  Time to bail!
			if git_available?
				raise VersionUnobtainable,
				      "GVB.version(#{use_local_git.inspect}) failed, and I really don't know why."
			else
				raise VersionUnobtainable,
				      "GVB.version(#{use_local_git.inspect}) failed; perhaps you need to install git?"
			end
		end
	end
end

GVB = GitVersionBump unless defined? GVB

require 'git-version-bump/version'
