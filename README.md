Maintain your program versions entirely within git.  No local files
required!  All versioning information is stored using git tags.

This gem contains a command-line tool and set of Rake tasks to increment
and display your version numbers via git tags, and some associated Ruby code to use
inside a gemspec or your program to retrieve the current version number, for
use in builds and at runtime.


# Usage

Most of your day-to-day usage of `git-version-bump` will be via the command
line.  When you bump a version, a new tag will be created representing the newly
incremented version number at the current commit.  If no tags currently
exist, the previous version will be taken to be `0.0.0` and then incremented
accordingly.


## On the command line

Pretty damned trivial:

    git version-bump <major|minor|patch|show>

You can also shorten the specifier to any unique substring:

    git version-bump ma
    git version-bump mi
    git version-bump p
    git version-bump s

I recommend adding an alias to your `~/.gitconfig` file, for less typing:

    [alias]
        vb = version-bump

You can also add your own release notes to your release tags, by using the
`-n` (or `--notes`, if you like typing) option:

    git version-bump -n minor

This will open an editor, containing a list of the commits since the last
release tag, in which you can type your release notes.  If you follow
standard git commit style (a "heading" line, then a blank line, followed by
free-form text) you're perfectly positioned to use
[github-release](http://theshed.hezmatt.org/github-release) to make
gorgeous-looking release announcements to Github.


## In your `Rakefile`

If you'd like to have access to the version-bumping goodness via `rake`, add
the following line to your `Rakefile`:

    require 'git-version-bump/rake-tasks'

You will now have the following rake tasks available:

    rake version:bump:major  # bump major version (x.y.z -> x+1.0.0)
    rake version:bump:minor  # bump minor version (x.y.z -> x.y+1.0)
    rake version:bump:patch  # bump patch version (x.y.z -> x.y.z+1)
    rake version:bump:show   # Print current version number

(Since `version:bump:major` is a lot of typing, there are also shortcuts:
`v:b:major`, `v:b:maj`, `v:b:minor`, `v:b:min`, `v:b:patch`, `v:b:pat`, and
`v:b:p`)


## In your Ruby code

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


### In your gemspec

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


### In your gem

If, like me, you're one of those people who likes to be able to easily see
what version of a library you're running, then you probably like to define a
`VERSION` constant somewhere in your gem's namespace.  That, too, is simple
to do:

    require 'git-version-bump'
    
    class Foobar
      VERSION = GVB.version
    end

This will work correctly inside your git tree, and also in your installed
gem.  Magical!


# Contributing

Send your pull requests to the [Github
repo](https://github.com/mpalmer/git-version-bump), or send patches to
`theshed+git-version-bump@hezmatt.org`.  Bug reports can be sent to the same
place, although I greatly prefer patches.


# Licence

Unless otherwise specified, all code in this repository is licenced under
the terms of the GNU Public Licence, version 3, as published by the Free
Software Foundation.  The full terms of this licence can be found in the
file LICENCE.
