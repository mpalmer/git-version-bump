Maintain your program versions entirely within git.  No local files
required!

This gem contains a set of Rake tasks and associated code to manage the
versioning of your code via git tags.  No in-repo file is required to store
your version, which reduces unnecessary duplication of information.


# Usage

In your `Rakefile`, add the following line:

    require 'git-version-bump/rake-tasks'

You will now have the following rake tasks available:

    rake version:bump:major  # bump major version (x.y.z -> x+1.0.0)
    rake version:bump:minor  # bump minor version (x.y.z -> x.y+1.0)
    rake version:bump:patch  # bump patch version (x.y.z -> x.y.z+1)

By running any of those, a new tag will be created representing the newly
incremented version number at the current commit.  If no tags currently
exist, the previous version will be taken to be `0.0.0` and then incremented
accordingly.

To get access to this version information in your code (such as in your
`gemspec`, or the definition of a `::VERSION` constant), you can `require
'git-version-bump'` and use the following methods:

    GVB.version            # Return the entire version string
    GVB.major_version      # Return just the 'major' portion of the version
    GVB.minor_version      # Return just the 'minor' portion of the version
    GVB.patch_version      # Return just the 'patch' portion of the version
    GVB.internal_revision  # Return "internal revision" information, or nil
    GVB.date               # Return the date of the most recent commit, or
                           # today's date if the tree is dirty

The "internal revision" is set when the tree is dirty, or when the latest
git commit doesn't correspond with a tag.  In that case, the internal
revision will describe, in the manner of `git describe`, the full details of
the version of the code in use.  This information will be part of the
version string provided by `gvb_version`.

If any of these methods are called when there isn't a tag or other version
information available, the version will be assumed to be `0.0.0.1.ENOTAG`
with a date of `1970-01-01`.


## In your gemspec

Typically, you want to encode your version and commit date into your
gemspec, like this:

    Gem::Specification.new do |s|
      s.version = GVB.version
      s.date    = GVB.date
      
      ...
    end

The beauty of this method is that whenever you run a `rake build`, you'll
get a gem which is *accurately* versioned for the current state of your
repository.  No more wondering if the `foobar-1.2.3` gem installed on your
system was built from pristine sources, or with that experimental patch you
were trying out...


## In your gem

If, like me, you're one of those people who likes to be able to easily see
what version of a library I'm running, then you probably like to define a
`VERSION` constant somewhere in your gem's namespace.  That, too, is simple
to do:

    require 'git-version-bump'
    
    class Foobar
      VERSION = GVB.version
    end

This will work correctly inside your git tree, and also in your installed
gem.  Magical!
