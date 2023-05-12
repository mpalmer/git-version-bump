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
	private_constant :VERSION_TAG_GLOB

	DEVNULL = Gem.win_platform? ? "NUL" : "/dev/null"
	private_constant :DEVNULL

	def self.version(use_local_dir=false, include_lite_tags=false)
		if use_local_dir
			repo_version(true, include_lite_tags)
		else
			gem_version || repo_version(false, include_lite_tags)
		end.tap { |v| p :GVB_VERSION, v if debug? }
	end

	def self.major_version(use_local_dir=false, include_lite_tags=false)
		ver = version(use_local_dir, include_lite_tags)
		v   = ver.split('.')[0]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.minor_version(use_local_dir=false, include_lite_tags=false)
		ver = version(use_local_dir, include_lite_tags)
		v   = ver.split('.')[1]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.patch_version(use_local_dir=false, include_lite_tags=false)
		ver = version(use_local_dir, include_lite_tags)
		v   = ver.split('.')[2]

		unless v =~ /^[0-9]+$/
			raise ArgumentError,
			        "#{v} (part of #{ver.inspect}) is not a numeric version component.  Abandon ship!"
		end

		return v.to_i
	end

	def self.internal_revision(use_local_dir=false, include_lite_tags=false)
		version(use_local_dir, include_lite_tags).split('.', 4)[3].to_s
	end

	def self.date(use_local_dir=false, include_lite_tags = false)
		if use_local_dir
			repo_date(true, include_lite_tags)
		else
			gem_date || repo_date(false, include_lite_tags)
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
	def self.commit_date_version(use_local_dir = false)
		if use_local_dir
			commit_date_version_string(true)
		else
			gem_version || commit_date_version_string(false)
		end
	end

	def self.commit_date_version_string(use_local_dir = false)
		commit_dates = run_command(["git", "-C", git_dir(use_local_dir).to_s, "log", "--no-show-signature", "--format=%at"], "getting dates of all commits").
		               split("\n").
		               map { |l| Time.at(Integer(l)).strftime("%Y%m%d") }

		version_date = commit_dates.first
		commit_count = commit_dates.select { |d| d == version_date }.length - 1
		dirty_suffix = if dirty_tree?
			".dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}"
		else
			""
		end

		return "0.#{version_date}.#{commit_count}#{dirty_suffix}"
	rescue CommandFailure => ex
		p :GVB_CDVS_CMD_FAIL, ex.output if debug?
		if ex.output =~ /fatal: your current branch .* does not have any commits yet/
			return "0.0.0.1.ENOCOMMITS"
		else
			raise VersionUnobtainable, "Could not get commit date-based version from git repository at #{git_dir(use_local_dir)}"
		end
	end

	def self.git_available?
		try_command(["git", "--version"])
	end
	private_class_method :git_available?

	def self.dirty_tree?(dir='.')
		# Are we in a dirty, dirty tree?
		! run_command(["git", "-C", dir.to_s, "status", "--porcelain"], "checking for tree cleanliness").empty?
	end
	private_class_method :dirty_tree?

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

		out, status = Open3.capture2e({"LC_MESSAGES" => "C"}, *cmd)

		if status.exitstatus != 0
			raise CommandFailure.new("Failed while #{desc}", out, status.exitstatus)
		else
			out
		end
	end
	private_class_method :run_command

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
	private_class_method :try_command

	def self.run_git(git_args, desc, use_local_dir)
		run_command(["git", "-C", git_dir(use_local_dir).to_s] + git_args, desc)
	end
	private_class_method :run_git

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
		).realpath rescue nil
	end
	private_class_method :caller_file

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

			if search_dirs.find { |d| cf.to_s.index(d) == 0 }
				return spec
			end
		end

		if debug?
			p :GVB_NO_GEMSPEC, cf
		end

		nil
	end
	private_class_method :caller_gemspec

	def self.gem_version
		caller_gemspec&.version&.to_s
	end
	private_class_method :gem_version

	def self.gem_date
		caller_gemspec&.date&.strftime("%F")
	end
	private_class_method :gem_version

	def self.repo_version(use_local_dir, include_lite_tags)
		begin
			run_git(["config", "versionBump.versionOverride"], "getting versionOverride", use_local_dir).chomp
		rescue CommandFailure => ex
			p :NO_OVERRIDE_VERSION, [ex.class, ex.message] if debug?
			repo_version_from_tag(use_local_dir, include_lite_tags)
		end
	end
	private_class_method :repo_version

	def self.repo_version_from_tag(use_local_dir, include_lite_tags)
		git_cmd = ["git", "-C", git_dir(use_local_dir).to_s, "describe", "--dirty=.1.dirty.#{Time.now.strftime("%Y%m%d.%H%M%S")}", "--match=#{VERSION_TAG_GLOB}"]
		git_cmd << "--tags" if include_lite_tags

		begin
			run_command(git_cmd, "getting current version descriptor").
			            strip.
			            gsub(/^v/, '').
			            gsub('-', '.')
		rescue CommandFailure => ex
			p :GVB_REPO_VERSION_FAILURE, ex.output if debug?
			if ex.output =~ /fatal: No names found, cannot describe anything/
				# aka "no tags, bro"
				"0.0.0.1.ENOTAG"
			else
				raise VersionUnobtainable, "Could not get version from gemspec or git repository at #{git_dir(use_local_dir)}"
			end
		end
	end
	private_class_method :repo_version_from_tag

	def self.repo_date(use_local_dir, include_lite_tags)
		begin
			run_git(["config", "versionBump.dateOverride"], "getting dateOverride", use_local_dir).chomp
		rescue CommandFailure => ex
			p :NO_OVERRIDE_DATE, [ex.class, ex.message] if debug?
			repo_date_from_commit(use_local_dir, include_lite_tags)
		end
	end
	private_class_method :repo_date

	def self.repo_date_from_commit(use_local_dir, include_lite_tags)
		if dirty_tree?(git_dir(use_local_dir))
			Time.now.strftime("%F")
		else
			# Clean tree.  Date of last commit is needed.
			(run_command(["git", "-C", git_dir(use_local_dir).to_s, "show", "--no-show-signature", "--format=format:%cd", "--date=short"], "getting date of last commit").lines.first || "").strip
		end
	rescue CommandFailure
		raise VersionUnobtainable, "Could not get commit date from git repository at #{git_dir(use_local_dir)}"
	end
	private_class_method :repo_date_from_commit

	def self.git_dir(use_local_dir = false)
		if use_local_dir
			Dir.pwd
		else
			caller_file&.dirname || Dir.pwd
		end.tap { |d| p :GVB_GIT_DIR, use_local_dir, d if debug? }
	end
	private_class_method :git_dir

	def self.debug?
		ENV.key?("GVB_DEBUG")
	end
	private_class_method :debug?
end

GVB = GitVersionBump unless defined? GVB

require 'git-version-bump/version'
