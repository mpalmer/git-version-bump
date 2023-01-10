module GitVersionBump
	def self.VERSION
		GVB.version
	end

	def self.MAJOR_VERSION
		GVB.major_version
	end

	def self.MINOR_VERSION
		GVB.minor_version
	end

	def self.PATCH_VERSION
		GVB.patch_version
	end

	def self.INTERNAL_REVISION
		GVB.internal_revision
	end

	def self.DATE
		GVB.date
	end

	def self.const_missing(c)
		if self.respond_to?(c) && c =~ /\A[A-Z_]+\z/
			public_send c
		else
			super
		end
	end
end
