require 'tempfile'
require 'digest/sha1'
require 'open3'
require 'pathname'

module GitVersionBump
	class VersionUnobtainable < StandardError; end
	class CommandFailure < StandardError
		attr_accessor :output, :exitstatus

		def initialize(m, output, exitstatus)
			super(m)
			@output, @exitstatus = output, exitstatus
		end
	end

	VERSION_TAG_GLOB = 'v[0-9]*.[0-9]*.*[0-9]'

	DEVNULL = Gem.win_platform? ? "NUL" : "/dev/null"

	def self.version(use_local_git=false, include_lite_tags=false)
		git_cmd = ["git", "-C", git_dir(use_local_git), "describe", "--dirty=.1.dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}", "--match=#{VERSION_TAG_GLOB}"]
		git_cmd << "--tags" if include_lite_tags

		begin
			run_command(git_cmd, "getting current version descriptor").
			            strip.
			            gsub(/^v/, '').
			            gsub('-', '.')
		rescue CommandFailure
			# git failed us; we're either not in a git repo or else we've never
			# tagged anything before.

			# Are we in a git repo with no tags?  If so, try to use the gemspec
			# and if that fails then abort
			begin
				gem_version(use_local_git)
			rescue VersionUnobtainable
				"0.0.0.1.ENOTAG"
			end
		end
	end

	def self.major_version(use_local_git=false, include_lite_tags=false)
		ver = version(use_local_git, include_lite_tags)
		v   = ver.split('.')[0]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.minor_version(use_local_git=false, include_lite_tags=false)
		ver = version(use_local_git, include_lite_tags)
		v   = ver.split('.')[1]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.patch_version(use_local_git=false, include_lite_tags=false)
		ver = version(use_local_git, include_lite_tags)
		v   = ver.split('.')[2]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.internal_revision(use_local_git=false, include_lite_tags=false)
		version(use_local_git, include_lite_tags).split('.', 4)[3].to_s
	end

	def self.date(use_local_git=false)
		# Are we in a git tree?
		begin
			try_command(["git", "-C", git_dir(use_local_git), "status"])

			if dirty_tree?(git_dir(use_local_git))
				Time.now.strftime("%F")
			else
				# Clean tree.  Date of last commit is needed.
				(run_command(["git", "-C", git_dir(use_local_git), "show", "--no-show-signature", "--format=format:%cd", "--date=short"], "getting date of last commit").lines.first || "").strip
			end
		rescue CommandFailure
			# Presumably not in a git tree
			if use_local_git
				raise RuntimeError,
				      "GVB.date(use_local_git=true) called from non-git location"
			end

			if spec = caller_gemspec
				spec.date.strftime("%F")
			else
				raise RuntimeError,
				      "GVB.date called from mysterious, non-gem location."
			end
		end
	end

	def self.tag_version(v, release_notes = false, include_lite_tags=false)
		if dirty_tree?
			puts "You have uncommitted files.  Refusing to tag a dirty tree."
			return false
		end
		if release_notes
			log_file = Tempfile.new('gvb')

			begin
				# We need to find the tag before this one, so we can list all the commits
				# between the two.  This is not a trivial operation.
				git_cmd = ["git", "describe", "--match=#{VERSION_TAG_GLOB}", "--always"]
				git_cmd << "--tags" if include_lite_tags

				prev_tag = run_command(git_cmd, "getting previous release tag").strip.gsub(/-\d+-g[0-9a-f]+$/, '')

				log_file.puts <<-EOF.gsub(/^\t\t\t\t\t/, '')



					# Write your release notes above.  The first line should be the release name.
					# To help you remember what's in here, the commits since your last release
					# are listed below. This will become v#{v}
					#
				EOF
				log_file.puts run_command(["git", "log", "--no-show-signature", "--format=# %h  %s", "#{prev_tag}..HEAD"], "getting commit range of release")

				log_file.close

				pre_hash = Digest::SHA1.hexdigest(File.read(log_file.path))
				run_command(["git", "config", "-e", "-f", log_file.path], "editing release notes")
				if Digest::SHA1.hexdigest(File.read(log_file.path)) == pre_hash
					puts "Release notes not edited; not making release"
					log_file.unlink
					return
				end

				puts "Tagging version #{v}..."
				run_command(["git", "tag", "-a", "-F", log_file.path, "v#{v}"], "tagging release with annotations")
			ensure
				log_file.unlink
			end
		else
			# Crikey this is a lot simpler
			run_command(["git", "tag", "-a", "-m", "Version v#{v}", "v#{v}"], "tagging release")
		end

		run_command(["git", "push"], "pushing commits to the default remote repository")
		run_command(["git", "push", "--tags"], "pushing tags to the default remote repository")
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
		commit_dates = run_command(["git", "-C", git_dir(use_local_git), "log", "--no-show-signature", "--format=%at"], "getting dates of all commits").
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

		# Are we in a git repo with no commits?  If so, try to use the gemspec
		# and if that fails then abort
		begin
			return gem_version(use_local_git)
		rescue VersionUnobtainable
			return "0.0.0.1.ENOCOMMITS"
		end
	end

	private

	def self.git_available?
		try_command(["git", "--version"])
	end

	def self.dirty_tree?(dir='.')
		# Are we in a dirty, dirty tree?
		! run_command(["git", "-C", dir, "status", "--porcelain"], "checking for tree cleanliness").empty?
	end

	# Execute a command, specified as an array.
	#
	# On success, the full output of the command (stdout+stderr, interleaved) is returned.
	# On error, a `CommandFailure` exception is raised.
	#
	def self.run_command(cmd, desc)
		unless cmd.is_a?(Array)
			raise ArgumentError, "Must pass command line arguments in an array"
		end

		unless cmd.all? { |s| s.is_a?(String) }
			raise ArgumentError, "Command line arguments must be strings"
		end

		if debug?
			p :GVB_CMD, desc, cmd
		end

		out, status = Open3.capture2e(*cmd)

		if status.exitstatus != 0
			raise CommandFailure.new("Failed while #{desc}", out, status.exitstatus)
		else
			out
		end
	end

	# Execute a command, and return whether it succeeded or failed.
	#
	def self.try_command(cmd)
		begin
			run_command(cmd, "try_command")
			true
		rescue CommandFailure
			false
		end
	end

	def self.caller_file
		# Who called us?  Because this method gets called from other methods
		# within this file, we can't just look at Gem.location_of_caller, but
		# instead we need to parse the caller stack ourselves to find which
		# gem we're trying to version all over.
		Pathname(
		  caller_locations.
		  map(&:path).
		  tap { |c| p :CALLER_LOCATIONS, c if debug? }.
		  find { |l| l != __FILE__ }
		).realpath.to_s rescue nil
	end

	def self.caller_gemspec
		cf = caller_file or return nil

		# Grovel through all the loaded gems to try and find the gem
		# that contains the caller's file.
		Gem.loaded_specs.values.each do |spec|
			# On Windows I have encountered gems that already have an absolute
			# path, verify that the path is relative before appending to it
			search_dirs = spec.require_paths.map do |path|
				if Pathname(path).absolute?
					path
				else
					File.join(spec.full_gem_path, path)
				end
			end
			search_dirs << File.join(spec.full_gem_path, spec.bindir)
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

	def self.git_dir(use_local_git = false)
		if use_local_git
			unless git_available?
				raise RuntimeError,
				      "Cannot use git-version-bump with use_local_git, as git is not installed"
			end

			Dir.pwd
		else
			File.dirname(caller_file) rescue nil || Dir.pwd
		end.tap { |d| p :GVB_GIT_DIR, use_local_git, d if debug? }
	end
	private_class_method :git_dir

	def self.debug?
		ENV.key?("GVB_DEBUG")
	end
end

GVB = GitVersionBump unless defined? GVB

require 'git-version-bump/version'
